#+build linux
package frostrig_platform

import linux "core:sys/linux"

_alloc_large_pages :: proc(size: uint) -> (ptr: rawptr, ok: bool) {
	aligned := align_to_huge_page(size)
	if aligned == 0 {
		return nil, false
	}
	flags := linux.Map_Flags{.PRIVATE, .ANONYMOUS, .HUGETLB} + linux.MAP_HUGE_2MB
	addr, errno := linux.mmap(0, aligned, {.READ, .WRITE}, flags)
	if errno != .NONE || addr == nil {
		return nil, false
	}
	return addr, true
}

_free_large_pages :: proc(ptr: rawptr, size: uint) {
	if ptr == nil {
		return
	}
	aligned := align_to_huge_page(size)
	if aligned == 0 {
		return
	}
	_ = linux.munmap(ptr, aligned)
}
