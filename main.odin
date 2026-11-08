package main

import core "./core"
import algo "./algo"
import worker "./worker"
import net "./net"

main :: proc() {
	_ = core.Error.Not_Implemented
	_ = algo.count()
	_ = worker.MAX_QUEUE
	_ = net.Session_State.Idle
}

