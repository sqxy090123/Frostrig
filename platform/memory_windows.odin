#+build windows
package frostrig_platform

import win "core:sys/windows"

_alloc_large_pages :: proc(size: uint) -> (ptr: rawptr, ok: bool) {
	aligned := align_to_huge_page(size)
	if aligned == 0 {
		return nil, false
	}
	addr := win.VirtualAlloc(
		nil,
		win.SIZE_T(aligned),
		win.MEM_RESERVE | win.MEM_COMMIT | win.MEM_LARGE_PAGES,
		win.PAGE_READWRITE,
	)
	if addr == nil {
		return nil, false
	}
	return addr, true
}

_free_large_pages :: proc(ptr: rawptr, size: uint) {
	if ptr == nil {
		return
	}
	_ = size
	_ = win.VirtualFree(ptr, 0, win.MEM_RELEASE)
}
