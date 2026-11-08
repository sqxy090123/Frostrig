package frostrig_platform

import core "../core"

HUGE_PAGE_SIZE :: 2 * 1024 * 1024

align_to_huge_page :: proc(size: uint) -> uint {
	if size == 0 {
		return 0
	}
	mask := uint(HUGE_PAGE_SIZE - 1)
	return (size + mask) &~ mask
}

alloc_large_pages :: proc(size: uint) -> (ptr: rawptr, ok: bool) {
	return _alloc_large_pages(size)
}

free_large_pages :: proc(ptr: rawptr, size: uint) {
	_free_large_pages(ptr, size)
}

bind_current_thread_to_cpu :: proc(cpu_index: u32) -> core.Error {
	return _bind_current_thread_to_cpu(cpu_index)
}

get_numa_node_for_current_thread :: proc() -> (node: u32, ok: bool) {
	return _get_numa_node_for_current_thread()
}
