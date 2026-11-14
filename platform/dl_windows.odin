#+build windows
package frostrig_platform

import c "core:c"

// C-side dynamic-library loader, compiled from platform/dl.c.
// All platform differences (dlopen vs LoadLibrary) live in C; the Odin
// side only foreign-imports the stable C symbols.
foreign import dl_mod "./dl.o"

@(default_calling_convention = "c")
foreign dl_mod {
	frostrig_dl_load          :: proc(path: rawptr) -> rawptr ---
	frostrig_dl_sym           :: proc(h: rawptr, name: rawptr) -> rawptr ---
	frostrig_dl_close         :: proc(h: rawptr) ---
	frostrig_dl_error         :: proc() -> rawptr ---
	frostrig_dl_suffix        :: proc() -> rawptr ---
	frostrig_dl_cstr_to_buf   :: proc(src: rawptr, dst: rawptr, cap: c.int) -> c.int ---
	frostrig_dl_read_ptr      :: proc(base: rawptr, offset: c.size_t) -> rawptr ---
}

// Dl_Handle is an opaque handle to a loaded dynamic library.
// A zero-valued Dl_Handle (ptr == nil) means "no library loaded".
Dl_Handle :: struct {
	ptr: rawptr,
}

// dl_load opens a dynamic library by path and returns a handle.
// The caller owns the handle and must call dl_close to unload it.
dl_load :: proc(path: string) -> Dl_Handle {
	if len(path) == 0 {
		return Dl_Handle{}
	}
	buf := make([]byte, len(path))
	copy(buf, path)
	h := frostrig_dl_load(rawptr(&buf[0]))
	return Dl_Handle{ptr = h}
}

// dl_is_nil reports whether handle represents an unloaded library.
dl_is_nil :: proc(h: Dl_Handle) -> bool {
	return h.ptr == nil
}

// dl_sym resolves a symbol by name within the library referenced by h.
// Returns nil if the symbol is not present.
dl_sym :: proc(h: Dl_Handle, name: string) -> rawptr {
	if dl_is_nil(h) || len(name) == 0 {
		return nil
	}
	buf := make([]byte, len(name))
	copy(buf, name)
	return frostrig_dl_sym(h.ptr, rawptr(&buf[0]))
}

// dl_close unloads the library.  The caller must ensure all per-thread
// handles produced by the library have been destroyed before calling
// this, otherwise the process may crash on the next touch of freed pages.
dl_close :: proc(h: Dl_Handle) {
	if dl_is_nil(h) {
		return
	}
	frostrig_dl_close(h.ptr)
}

// dl_error returns the most recent error indicator; on Windows the C
// layer returns NULL, so the caller should use the OS error code.
dl_error :: proc() -> string {
	msg := frostrig_dl_error()
	if msg == nil {
		return ""
	}
	return dl_c_from_ptr(msg)
}

// dl_suffix returns the host dynamic-library extension (".dll").
dl_suffix :: proc() -> string {
	s := frostrig_dl_suffix()
	if s == nil {
		return ""
	}
	return dl_c_from_ptr(s)
}

// dl_c_from_ptr converts a C NUL-terminated rawptr to an Odin string by
// copying it into an Odin buffer via the C helper.
dl_c_from_ptr :: proc(p: rawptr) -> string {
	if p == nil {
		return ""
	}
	max_len := 512
	buf := make([]byte, max_len)
	n := frostrig_dl_cstr_to_buf(p, rawptr(&buf[0]), c.int(max_len))
	if n <= 0 {
		return ""
	}
	if n >= c.int(max_len) {
		return cast(string) buf[:]
	}
	return cast(string) buf[:int(n)]
}
