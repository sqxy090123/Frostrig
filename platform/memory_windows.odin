#+build windows
package frostrig_platform

import win "core:sys/windows"

// WinRing0 ring0 note:
// On Windows, MEM_LARGE_PAGES requires SeLockMemoryPrivilege.  If the
// host has disabled the "Lock pages in memory" policy or runs under an
// unprivileged account, VirtualAlloc(..., MEM_LARGE_PAGES) returns nil.
// A reliable fallback is to load the signed WinRing0 kernel driver
// (ring0.sys) via SCM and use its ioctl to allocate 2 MiB huge pages
// from ring0.  The control layer should attempt VirtualAlloc first and
// fall back to the WinRing0 path on failure.
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
		// TODO: WinRing0 ring0 fallback
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
