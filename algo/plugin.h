/*
 * frostrig algorithm plugin ABI
 *
 * A plugin is a shared library (Linux .so, macOS .dylib, Windows .dll)
 * that exports exactly one entry point:
 *
 *     const frostrig_algo_vtable *frostrig_algo_register(void);
 *
 * The host binary dlopens the library, dlsyms the symbol, and calls the
 * returned vtable.  Each vtable field is a plain C function pointer that
 * receives the same argument shapes the host's Odin FFI layer passes to
 * built-in algorithms, so plugins are loadable at runtime without relinking
 * the host binary.
 *
 * Plugins must:
 *   - be self-contained (link their own librandomx / argon2 etc. as
 *     required, or use dlopen-time resolution against the host's exports
 *     when the host already links those libraries)
 *   - not call back into the host at vtable-construction time
 *   - tolerate NULL handles in prepare/hash/pipeline when the caller has
 *     not yet created a handle
 */
#ifndef FROSTRIG_PLUGIN_H
#define FROSTRIG_PLUGIN_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Per-variant stable identifier.  Built-in variants use the values below;
 * plugins may pick any unused value.  The host deduplicates by `id` at
 * registration time, so a plugin whose id collides with a built-in
 * algorithm is rejected with .Already_Initialized.
 */
enum frostrig_algo_id {
	FROSTRIG_ALGO_RANDOMX       = 0,
	FROSTRIG_ALGO_RANDOMX_WOW   = 1,
	FROSTRIG_ALGO_RANDOMX_2     = 2,
	FROSTRIG_ALGO_RANDOMX_C64   = 3,
	FROSTRIG_ALGO_RANDOMX_V     = 4,
	FROSTRIG_ALGO_RANDOMX_XEQ   = 5,
	FROSTRIG_ALGO_RANDOMX_KEVA  = 6,
	FROSTRIG_ALGO_ARGON2ID      = 7,
	FROSTRIG_ALGO_ARGON2D_16000 = 8,
	FROSTRIG_ALGO_ARGON2D_1000  = 9,
	FROSTRIG_ALGO_VH22          = 10,
	FROSTRIG_ALGO_VH31          = 11,
	/* First plugin-reserved id.  Plugins should use >= this value. */
	FROSTRIG_ALGO_PLUGIN_BASE   = 1000
};

/*
 * 32-byte hash buffer.  Mirrors core.Hash on the Odin side: a fixed-size
 * byte array plus a length so callers can know how many bytes are valid.
 * Plugins that produce fewer than 32 bytes must set len accordingly.
 */
typedef struct {
	uint8_t bytes[32];
	uint32_t len;
} frostrig_hash;

/*
 * Per-thread working-set size in bytes.  The host's platform layer uses
 * this to pre-allocate huge pages before the worker pool starts.  Set to
 * 0 for non-memory-intensive algorithms.
 */
typedef struct {
	uint32_t id;
	const char *name;
	const char *alias;   /* optional; empty or NULL */
	uint64_t memory;
} frostrig_algo_info;

/*
 * Opaque per-thread algorithm handle.  The plugin owns the layout; the
 * host passes it back through the other vtable procs unchanged.
 */
typedef struct frostrig_algo_handle frostrig_algo_handle;

/*
 * frostrig_algo_vtable is the plugin contract.  All fields must be
 * non-NULL unless noted.  The host wraps each field in an Odin thunk so
 * the call path is identical to built-in algorithms.
 */
typedef struct {
	frostrig_algo_info info;

	/*
	 * create: allocate and initialise a per-thread context.
	 * config_flags / config_huge_pages / config_thread_index: host-supplied
	 * configuration (same meaning as Algo_Config on the Odin side).
	 * key: 32-byte seed buffer (host-derived from the block height, or a
	 *      stable placeholder so the VM stays deterministic within a run).
	 * Returns NULL on failure (host will surface .Ffi_Init_Failed).
	 */
	frostrig_algo_handle *(*create)(uint32_t config_flags, int config_huge_pages,
		uint32_t config_thread_index, const void *key, size_t key_size);

	/* destroy: release the context.  Safe to call with NULL. */
	void (*destroy)(frostrig_algo_handle *h);

	/*
	 * prepare: re-seed the cache before a new job.  `key` is a 32-byte
	 * seed; key_size is the byte count (typically 32, 0 if none).
	 * Returns 0 on success, -1 on error.
	 */
	int (*prepare)(frostrig_algo_handle *h, const void *key, size_t key_size);

	/*
	 * hash: compute one hash.  input is blob + 8-byte LE nonce appended
	 * by the host.  out must receive out_size bytes (host passes 32).
	 * Returns 0 on success, -1 on error.
	 */
	int (*hash)(frostrig_algo_handle *h, const void *input, size_t input_size,
		frostrig_hash *out);

	/*
	 * pipeline (optional, may be NULL): batch `count` sequential nonces
	 * starting at `start_nonce` against `input`, writing `count-1` hashes
	 * to `outputs` (the last is left pending for a follow-up drain call).
	 * When NULL the host falls back to looping `hash`.
	 */
	int (*pipeline)(frostrig_algo_handle *h, const void *input, size_t input_size,
		uint64_t start_nonce, size_t count, void *outputs);

} frostrig_algo_vtable;

/*
 * Plugin entry point.  The host dlsyms this symbol; it must return a
 * pointer to a static, process-lifetime frostrig_algo_vtable.  Returning
 * NULL means "no algorithms to register" (host skips the plugin).
 */
const frostrig_algo_vtable *frostrig_algo_register(void);

#ifdef __cplusplus
}
#endif

#endif /* FROSTRIG_PLUGIN_H */
