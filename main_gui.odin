package main

import core "./core"
import algo "./algo"
import worker "./worker"
import gui "./gui"
import cnet "core:net"
import fmt "core:fmt"
import time "core:time"

// gui_worm2 viewer serves the Worm/2 walk in 3D while the workers keep hashing.
//
// It is only reachable when the selected algorithm is Worm/2 and no pool URL was
// given: against a live pool the same CPU time belongs to submitting shares, so
// the viewer is an offline-only facility.  The bench/test flags decide whether
// the workers run once and freeze or keep walking so the trail stays alive.
gui_worm2 :: proc(config: Cli_Config) -> core.Error {
	miner_cfg := core.Miner_Config{
		thread_count = config.threads,
		huge_pages   = config.huge_pages,
		cpu_affinity = config.cpu_affinity != "",
		algo         = algo.Worm2_Id,
	}
	pool, perr := worker.create(miner_cfg)
	if perr != .None {
		return perr
	}
	serr := worker.start(&pool)
	if serr != .None {
		return serr
	}
	defer worker.stop(&pool)

	state := new(algo.Gui_State)
	if worker.gui_trace_attach(&pool, state) == false {
		return core.Error.Internal
	}
	// tune the sampling density the viewer asked for; defaults are the
	// library constants, so an unset flag keeps the current look
	if !algo.Set_Worm2_Gui_Config(state, config.gui_stride, config.gui_trail) {
		return core.Error.Internal
	}

	server := new(gui.Gui_Server)
	if err := gui.start(server, state, cnet.Address(cnet.IP4_Any), config.gui_port); err != nil {
		fmt.printfln("[gui] listen failed on 0.0.0.0:%v: %v", config.gui_port, err)
		return core.Error.Internal
	}
	defer gui.stop(server)

	fmt.printfln("[gui] worm/2 walk viewer: http://127.0.0.1:%v/", config.gui_port)
	fmt.printfln("[gui] drag to rotate, wheel or pinch to zoom, double-click to reset")

	if config.test {
		worker.benchmark(&pool, 1)
	} else {
		for {
			worker.benchmark(&pool, config.bench_count)
		}
	}

	// Hashing finished (the --test path); the server stays up so the last
	// position can still be orbited.  Nothing else is worth doing here.
	for {
		time.sleep(1 * time.Second)
	}
}
