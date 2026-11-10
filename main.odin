package main

import core "./core"
import algo "./algo"
import worker "./worker"
import os "core:os"
import fmt "core:fmt"
import time "core:time"

register_algos :: proc() -> core.Error {
	entries := []algo.Algo_Entry{
		algo.randomx_entry,
		algo.randomx_wow_entry,
		algo.randomx_2_entry,
		algo.randomx_c64_entry,
		algo.randomx_v_entry,
		algo.randomx_xeq_entry,
	}
	for e in entries {
		err := algo.register(e)
		if err != .None {
			return err
		}
	}
	return .None
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
		fmt.printfln("      --no-gui                run without GUI")
		fmt.printfln("      --list-algos            list registered algorithms and exit")
		fmt.printfln("      --bench                 run benchmark and exit")
	}

// os_args returns the full argv slice including the program name at index 0.
os_args :: proc() -> []string {
	return os.args
}

main :: proc() {
	err := register_algos()
	if err != .None {
		fmt.printfln("failed to register algorithms: %v", err)
		os.exit(1)
	}

	argv := os_args()
	config, err_msg := parse_args(argv)
	if err_msg != "" {
		fmt.printfln("%s", err_msg)
		print_usage("frostrig")
		os.exit(1)
	}

	if config.algo_name == "" {
		config.algo_name = "randomx"
	}

	if config.list_algos {
		list_algos()
		return
	}

	a_id, a_err := resolve_algo(config.algo_name)
	if a_err != "" {
		fmt.printfln("%s", a_err)
		os.exit(1)
	}

	miner_cfg := build_miner_config(config, a_id)
	pool, perr := worker.create(miner_cfg)
	if perr != .None {
		fmt.printfln("pool init failed: %v", perr)
		os.exit(1)
	}

	serr := worker.start(&pool)
	if serr != .None {
		fmt.printfln("pool start failed: %v", serr)
		os.exit(1)
	}

	if config.bench {
		worker.benchmark(&pool, 100)
		worker.stop(&pool)
		return
	}

	if config.no_gui == false {
		fmt.printfln("frostrig running (algo: %s, threads: %v)",
			config.algo_name, miner_cfg.thread_count)
	}

	for {
		time.sleep(1 * time.Second)
	}
}
