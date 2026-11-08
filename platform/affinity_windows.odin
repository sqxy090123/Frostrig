#+build windows
package frostrig_platform

import core "../core"

_bind_current_thread_to_cpu :: proc(cpu_index: u32) -> core.Error {
	_ = cpu_index
	return .Affinity_Failed
}
