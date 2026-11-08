#+build windows
package frostrig_platform

_get_numa_node_for_current_thread :: proc() -> (node: u32, ok: bool) {
	return 0, false
}
