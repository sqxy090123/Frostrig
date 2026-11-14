#ifndef FROSTRIG_DL_H
#define FROSTRIG_DL_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Opaque handle to a loaded shared library.  NULL = not loaded. */
void *frostrig_dl_load(const char *path);
void *frostrig_dl_sym(void *h, const char *name);
void  frostrig_dl_close(void *h);

/* Returns the most recent dl* error string (POSIX), or NULL (Windows /
 * no error).  The pointer is owned by the C runtime; do not free. */
const char *frostrig_dl_error(void);

/* Returns the shared-library suffix for the host OS: ".so", ".dylib",
 * or ".dll".  The pointer is a string literal; do not free. */
const char *frostrig_dl_suffix(void);

/*
 * Copies the NUL-terminated C string `src` into the Odin-owned buffer
 * `dst` (capacity `cap`).  Returns the full source length (excluding the
 * NUL terminator); 0 if src is NULL.  Truncates to cap bytes when the
 * source is longer.  This lets the Odin side read C strings without
 * indexing into C memory.
 */
	int frostrig_dl_cstr_to_buf(const char *src, char *dst, int cap);

	/*
	 * Reads the 8-byte pointer value stored at (base + offset) and returns it.
	 * Used by the plugin loader to extract function-pointer fields from a
	 * C frostrig_algo_vtable without indexing into C memory (which the Odin
	 * compiler rejects).
	 */
	void *frostrig_dl_read_ptr(const void *base, size_t offset);

#ifdef __cplusplus
}
#endif

#endif /* FROSTRIG_DL_H */
