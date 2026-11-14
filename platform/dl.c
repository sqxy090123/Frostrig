/*
 * frostrig platform: dynamic-library loader
 *
 * C wrapper over dlopen/dlsym/dlclose (POSIX) and LoadLibrary/GetProcAddress
 * (Windows).  The Odin side foreign-imports these symbols; all platform
 * differences live here so the Odin plugin loader stays clean.
 *
 * Exported entry points (see dl_linux.odin / dl_windows.odin for the
 * Odin-side signatures):
 *   frostrig_dl_load(const char *path) -> void*
 *   frostrig_dl_sym(void *h, const char *name) -> void*
 *   frostrig_dl_close(void *h) -> void
 *   frostrig_dl_error() -> const char*   // NULL if no error
 *   frostrig_dl_suffix() -> const char*  // ".so" / ".dll" / ".dylib"
 */
#include "dl.h"
#include <stdio.h>
#include <string.h>

#if defined(_WIN32)

#define WIN32_LEAN_AND_MEAN
#include <windows.h>

void *frostrig_dl_load(const char *path) {
	if (path == NULL) {
		return NULL;
	}
	return (void *)LoadLibraryA(path);
}

void *frostrig_dl_sym(void *h, const char *name) {
	if (h == NULL || name == NULL) {
		return NULL;
	}
	return (void *)GetProcAddress((HMODULE)h, name);
}

void frostrig_dl_close(void *h) {
	if (h == NULL) {
		return;
	}
	FreeLibrary((HMODULE)h);
}

const char *frostrig_dl_error(void) {
	/* Windows: no global error string; callers use GetLastError. */
	return NULL;
}

const char *frostrig_dl_suffix(void) {
	return ".dll";
}

/*
 * frostrig_dl_cstr_to_buf copies the NUL-terminated C string `src` into
 * Odin-owned buffer `dst` (capacity `cap`).  Returns the number of
 * characters copied (excluding the NUL terminator); 0 if src is NULL.
 */
int frostrig_dl_cstr_to_buf(const char *src, char *dst, int cap) {
	if (src == NULL) {
		return 0;
	}
	int i = 0;
	while (src[i] != 0) {
		i++;
	}
	if (cap > i) {
		cap = i;
	}
	int n = 0;
	for (n = 0; n < cap; n++) {
		dst[n] = src[n];
	}
	if (cap < i) {
		dst[cap] = 0;
	} else {
		dst[i] = 0;
	}
	return i;
}

#else /* POSIX */

#include <dlfcn.h>

void *frostrig_dl_load(const char *path) {
	if (path == NULL) {
		return NULL;
	}
	/* RTLD_LAZY: resolve symbols on first use.
	 * RTLD_GLOBAL: export this library's symbols to the global scope so a
	 * nested dlopen of a plugin that depends on symbols already linked
	 * into the host can resolve against them. */
	return dlopen(path, RTLD_LAZY | RTLD_GLOBAL);
}

void *frostrig_dl_sym(void *h, const char *name) {
	if (h == NULL || name == NULL) {
		return NULL;
	}
	dlerror(); /* clear any pending error */
	return dlsym(h, name);
}

void frostrig_dl_close(void *h) {
	if (h == NULL) {
		return;
	}
	dlclose(h);
}

const char *frostrig_dl_error(void) {
	return dlerror();
}

const char *frostrig_dl_suffix(void) {
#if defined(__APPLE__)
	return ".dylib";
#else
	return ".so";
#endif
}

/*
 * frostrig_dl_cstr_to_buf copies the NUL-terminated C string `src` into
 * Odin-owned buffer `dst` (capacity `cap`).  Returns the number of
 * characters copied (excluding the NUL terminator); 0 if src is NULL.
 * If cap is too small, truncates and returns the full length so the
 * caller can detect truncation.
 */
int frostrig_dl_cstr_to_buf(const char *src, char *dst, int cap) {
	if (src == NULL) {
		return 0;
	}
	int i = 0;
	while (src[i] != 0) {
		i++;
	}
	if (cap > i) {
		cap = i;
	}
	int n = 0;
	for (n = 0; n < cap; n++) {
		dst[n] = src[n];
	}
	if (cap < i) {
		dst[cap] = 0;
	} else {
		dst[i] = 0;
	}
	return i;
}

/*
 * frostrig_dl_read_ptr reads the 8-byte pointer value stored at (base +
 * offset) and returns it.  Used by the plugin loader to extract the
 * function-pointer fields out of a C frostrig_algo_vtable without the
 * Odin side indexing into C memory (which the Odin compiler rejects).
 */
void *frostrig_dl_read_ptr(const void *base, size_t offset) {
	const unsigned char *p = (const unsigned char *)base + offset;
	unsigned char buf[8];
	for (int i = 0; i < 8; i++) {
		buf[i] = p[i];
	}
	void *result;
	memcpy(&result, buf, sizeof(result));
	return result;
}

#endif

