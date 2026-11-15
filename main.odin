package main

import core "./core"
import algo "./algo"
import worker "./worker"
import net "./net"
import os "core:os"
import fmt "core:fmt"
import time "core:time"

// trace_step appends a timestamped marker to ./frostrig_trace.log so we can
// see how far main() progressed when the process hangs / exits silently.
// File I/O flushes on each call (no stdout-style buffering), so it survives
// abnormal termination.  Writing to the CWD keeps it trivially discoverable
// next to the exe (the user runs it from F:\miner\<build>\).
trace_step :: proc(step: string) {
	f, _ := os.open("frostrig_trace.log", os.File_Flags{.Write, .Append, .Create})
	if f != nil {
		defer os.close(f)
		line := fmt.tprintf("%v pid=%v %v\n", time.now(), os.get_pid(), step)
		buf := make([]u8, len(line))
		copy(buf, line)
		_, _ = os.write(f, buf)
	}
}

register_algos :: proc() -> core.Error {
	entries := []algo.Algo_Entry{
		algo.randomx_entry,
		algo.randomx_wow_entry,
		algo.randomx_2_entry,
		algo.randomx_c64_entry,
		algo.randomx_v_entry,
		algo.randomx_xeq_entry,
		algo.randomx_keva_entry,
		algo.argon2id_entry,
		algo.argon2d16000_entry,
		algo.argon2d1000_entry,
		algo.vh22_entry,
		algo.vh31_entry,
		algo.blake2b_entry,
		algo.cn_pico_entry,
		algo.cn_heavy_entry,
		algo.ghostrider_entry,
	}
	for e in entries {
		err := algo.register(e)
		if err != .None {
			return err
		}
	}
	return .None
}

// register_plugin_algos loads every shared library in paths, registers its
// algorithm vtable in the global registry, and keeps the handles alive in
// the plugin registry so the thunks stay valid for the process lifetime.
register_plugin_algos :: proc(paths: []string) -> core.Error {
	if len(paths) == 0 {
		return .None
	}
	_, err := algo.load_plugin_paths(paths)
	return err
}

	print_usage :: proc(prog: string) {
		fmt.printfln("usage: %s [options]", prog)
		fmt.printfln("")
		fmt.printfln("options:")
		fmt.printfln("  -a, --algo <name>       algorithm to mine (default: randomx)")
		fmt.printfln("      --coin <coin>       coin name (informational)")
		fmt.printfln("  -o, --url <url>         pool URL")
		fmt.printfln("  -u, --user <user>       pool username / wallet")
		fmt.printfln("  -p, --pass <pass>       pool password")
		fmt.printfln("  -t, --threads <n>       thread count (default: 1)")
		fmt.printfln("      --cpu-affinity <mask>   CPU affinity mask")
		fmt.printfln("      --cpu-priority <n>      CPU priority (nice value)")
		fmt.printfln("      --no-huge-pages         disable huge page allocation")
		fmt.printfln("      --stratum               (legacy) a pool URL now auto-enables stratum")
		fmt.printfln("      --no-gui                run without GUI")
		fmt.printfln("      --list-algos            list registered algorithms and exit")
		fmt.printfln("      --bench                 run benchmark and exit")
		fmt.printfln("      --plugin <path>         load an algorithm plugin (.so/.dll); may repeat")
	}

// os_args returns the full argv slice including the program name at index 0.
os_args :: proc() -> []string {
	return os.args
}

main :: proc() {
	trace_step("main-entry")
	err := register_algos()
	if err != .None {
		trace_step("register-fail")
		fmt.printfln("failed to register algorithms: %v", err)
		os.exit(1)
	}
	trace_step("register-done")

	argv := os_args()
	config, err_msg := parse_args(argv)
	if err_msg != "" {
		trace_step("parse-fail")
		fmt.printfln("%s", err_msg)
		print_usage("frostrig")
		os.exit(1)
	}
	trace_step("parse-done")

	// Load any user-supplied algorithm plugins before resolving the
	// requested algorithm, so plugin-provided names are visible to
	// resolve_algo.  Plugins that fail to load are skipped (logged by
	// the platform layer), never fatal.
	perr := register_plugin_algos(config.plugin_paths[:])
	if perr != .None {
		fmt.printfln("failed to load plugin algorithms: %v", perr)
		os.exit(1)
	}

	if config.algo_name == "" {
		config.algo_name = "randomx"
	}

	if config.list_algos {
		trace_step("list-algos")
		list_algos()
		trace_step("list-algos-done")
		return
	}

	a_id, a_err := resolve_algo(config.algo_name)
	if a_err != "" {
		trace_step("resolve-fail")
		fmt.printfln("%s", a_err)
		os.exit(1)
	}
	trace_step("resolve-done")

	miner_cfg := build_miner_config(config, a_id)
	pool, pool_err := worker.create(miner_cfg)
	if pool_err != .None {
		trace_step("pool-create-fail")
		fmt.printfln("pool init failed: %v", pool_err)
		os.exit(1)
	}
	trace_step("pool-create-done")

	serr := worker.start(&pool)
	if serr != .None {
		trace_step("pool-start-fail")
		fmt.printfln("pool start failed: %v", serr)
		os.exit(1)
	}
	trace_step("pool-start-done")

	// enable mining-loop diagnostics when FROSTRIG_DEBUG is set
	debug_buf := make([]u8, 32)
	if os.get_env_buf(debug_buf, "FROSTRIG_DEBUG") != "" {
		pool.debug = true
	}

	if config.bench {
		trace_step("bench-start")
		worker.benchmark(&pool, config.bench_count)
		trace_step("bench-done")
		worker.stop(&pool)
		algo.unload_all_plugins()
		return
	}

	if config.no_gui == false {
		trace_step("loop-start")
		fmt.printfln("frostrig running (algo: %s, threads: %v)",
			config.algo_name, miner_cfg.thread_count)
	}

	// Decide the mining seed.  A pool URL present on the command line means
	// the user wants to connect to a real pool, so we dial it, log in, and
	// seed the workers from the live job.  Only when there is no pool URL do
	// we run the synthetic offline demo loop (the path CI and no-arg runs
	// take, so they stay network-free).
	use_stratum := config.pool_url != ""
	stratum_session := net.Session{}
	if use_stratum {
		host, port, perr := net.parse_stratum_url(config.pool_url)
		if perr != "" {
			trace_step("stratum-parse-fail")
			fmt.printfln("invalid pool URL: %v", perr)
			fmt.printfln("falling back to offline H/s demo loop")
			use_stratum = false
		} else {
			stratum_session.user = config.username
			stratum_session.pass = config.password
			terr := net.connect(&stratum_session, net.Endpoint{host = host, port = port})
			if terr != .None {
				trace_step("stratum-connect-fail")
				fmt.printfln("stratum connect to %v:%v failed: %v", host, port, terr)
				#partial switch terr {
				case core.Error.Stratum_Dial_Failed:
					fmt.printfln("  the TCP connection could not be established; check the host/port and any firewall.")
				case core.Error.Stratum_Login_Failed:
					fmt.printfln("  the login request could not be sent; the socket closed early.")
				case core.Error.Stratum_Ack_Timeout:
					fmt.printfln("  connected but the pool never replied to login.")
					fmt.printfln("  if this pool only speaks TLS (stratum+ssl), a raw stratum+tcp client cannot log in;")
					fmt.printfln("  use the pool's plaintext stratum+tcp host:port or a TLS-capable client.")
				}
				fmt.printfln("falling back to offline H/s demo loop")
				use_stratum = false
			} else {
				trace_step("stratum-connected")
				if len(stratum_session.job.blob) > 0 {
					fmt.printfln("stratum connected to %v:%v, job id=%v, blob len=%v",
						host, port, stratum_session.job.job_id, len(stratum_session.job.blob))
				} else {
					// login succeeded but no job has arrived yet; start the
					// loop with the synthetic seed and let the reader push
					// the real job in via mining.set_job.
					fmt.printfln("stratum connected to %v:%v; waiting for first job", host, port)
				}
			}
		}
	}

	// Start the hashing loop.  With a live stratum session we seed it from
	// the pool's current job blob (or the synthetic seed when the first
	// job is still pending); otherwise we run the synthetic demo loop.
	if use_stratum {
		serr2 := worker.mine_with_blob(&pool, stratum_session.job.blob)
		if serr2 != .None {
			trace_step("stratum-mine-start-fail")
			fmt.printfln("stratum mine loop start failed: %v", serr2)
			net.close(&stratum_session)
			worker.stop(&pool)
			os.exit(1)
		}
	} else {
		if config.no_gui == false {
			fmt.printfln("running offline H/s demo loop (no pool URL supplied)")
		}
		merr := worker.mine(&pool)
		if merr != .None {
			trace_step("mine-start-fail")
			fmt.printfln("mine loop start failed: %v", merr)
			worker.stop(&pool)
			os.exit(1)
		}
	}
	trace_step("mine-start-done")

	// Periodically print H/s so the miner is visibly doing work.
	REPORT_INTERVAL :: 5 * time.Second
	last := time.now()
	for {
		time.sleep(1 * time.Second)
		if time.since(last) >= REPORT_INTERVAL {
			last = time.now()
			worker.report(&pool, config.algo_name)
		}
	}
}
