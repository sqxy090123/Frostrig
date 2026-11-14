package frostrig_algo

import core "../core"
import platform "../platform"
import c "core:c"

// Plugin_Entry is the host-side wrapper around a loaded algorithm
// plugin shared library.  It captures the library handle plus the
// resolved C function pointers so the hot path never re-dlsym.
Plugin_Entry :: struct {
	handle:      platform.Dl_Handle,
	vtable:      rawptr, // points at the C frostrig_algo_vtable
	vtable_id:   core.Algo_Id, // the algorithm id from the vtable info block
	create_fn:   rawptr,
	destroy_fn:  rawptr,
	prepare_fn:  rawptr,
	hash_fn:     rawptr,
	pipeline_fn: rawptr, // nil if the plugin does not provide one
}

// c_info_size mirrors the C frostrig_algo_info struct size on 64-bit.
// Layout: uint32 id(4) + 4 pad + const char *name(8) + const char *alias(8)
// + uint64 memory(8) = 32 bytes, 8-aligned.  The five vtable function
// pointers follow at offset 32 with 8-byte stride (verified with
// offsetof(frostrig_algo_vtable, create) == 32).
c_info_size: c.size_t = 32

// C function-pointer types (from algo/plugin.h).
c_create_fn :: proc(
	flags: c.uint32_t, huge: c.int, thread: c.uint32_t,
	key: rawptr, key_size: c.size_t,
) -> rawptr
c_destroy_fn :: proc(h: rawptr)
c_prepare_fn :: proc(h: rawptr, key: rawptr, key_size: c.size_t) -> c.int
c_hash_fn :: proc(h: rawptr, input: rawptr, input_size: c.size_t, out: rawptr) -> c.int
c_pipeline_fn :: proc(h: rawptr, input: rawptr, input_size: c.size_t,
	start: c.uint64_t, count: c.size_t, outputs: rawptr) -> c.int
c_register_fn :: proc() -> rawptr

// c_algo_info_view mirrors the C frostrig_algo_info layout for reading
// id/name/alias/memory back through a rawptr cast.
c_algo_info_view :: struct {
	id:     c.uint32_t,
	_pad:   c.uint32_t,
	name:   rawptr,
	alias:  rawptr,
	memory: c.uint64_t,
}

// load_plugin opens a shared library at path and resolves the
// frostrig_algo_register symbol.  On success it returns a Plugin_Entry
// with all function pointers resolved; the caller owns the handle and
// must call unload_plugin to release the library.
load_plugin :: proc(path: string) -> (entry: Plugin_Entry, err: core.Error) {
	h := platform.dl_load(path)
	if platform.dl_is_nil(h) {
		return Plugin_Entry{}, .Invalid_Argument
	}
	reg := platform.dl_sym(h, "frostrig_algo_register")
	if reg == nil {
		platform.dl_close(h)
		return Plugin_Entry{}, .Invalid_Argument
	}
	register_call := cast(c_register_fn) reg
	vt := register_call()
	if vt == nil {
		platform.dl_close(h)
		return Plugin_Entry{}, .Invalid_Argument
	}
 	// Read the five function-pointer fields from offset c_info_size.
 	// Use platform.frostrig_dl_read_ptr to dereference the pointers (avoid indexing
 	// C memory, which the Odin compiler rejects).
 	create_fn := platform.frostrig_dl_read_ptr(vt, c_info_size)
 	destroy_fn := platform.frostrig_dl_read_ptr(vt, c_info_size + 8)
 	prepare_fn := platform.frostrig_dl_read_ptr(vt, c_info_size + 16)
 	hash_fn := platform.frostrig_dl_read_ptr(vt, c_info_size + 24)
 	pipeline_fn := platform.frostrig_dl_read_ptr(vt, c_info_size + 32)

 	if create_fn == nil || destroy_fn == nil || prepare_fn == nil || hash_fn == nil {
		platform.dl_close(h)
		return Plugin_Entry{}, .Invalid_Argument
	}
	// Read the algorithm id from the vtable info block (offset 0).
	info := cast(^c_algo_info_view) vt
	return Plugin_Entry{
		handle      = h,
		vtable      = vt,
		vtable_id   = core.Algo_Id(u32(info.id)),
		create_fn   = create_fn,
		destroy_fn  = destroy_fn,
		prepare_fn  = prepare_fn,
		hash_fn     = hash_fn,
		pipeline_fn = pipeline_fn,
	}, .None
}

// unload_plugin releases the shared library.  The caller must have
// already destroyed every per-thread handle produced by this plugin
// (every Algo_Handle.ctx that came from entry.create_fn),
// otherwise RandomX's 2 GB dataset will be touched after the pages
// are unmapped.  Safe to call multiple times.
unload_plugin :: proc(entry: ^Plugin_Entry) {
	if entry == nil {
		return
	}
	if !platform.dl_is_nil(entry.handle) {
		platform.dl_close(entry.handle)
		entry.handle = platform.Dl_Handle{}
	}
}

// plugin_key derives the 32-byte cache key from config, mirroring
// config_key in randomx.odin so built-in and plugin algorithms stay
// deterministic within a run.
plugin_key :: proc(config: core.Algo_Config) -> [32]u8 {
	key: [32]u8
	key[0] = u8(config.thread_index & 0xff)
	key[1] = u8((config.flags >> 8) & 0xff)
	return key
}

// plugin_suffix returns the host shared-library extension (".so",
// ".dylib", ".dll") via the platform loader.
plugin_suffix :: proc() -> string {
	return platform.dl_suffix()
}

// load_plugin_paths registers each shared library in paths (a list of
// full file paths to .so/.dylib/.dll).  Files that fail to load or have
// no valid frostrig_algo_register symbol are skipped (not fatal) so a
// single bad plugin does not block the others.  Returns the number of
// successfully registered plugins.  The caller owns the resulting
// ^Plugin_Entry list; keep it alive until worker.stop.
load_plugin_paths :: proc(paths: []string) -> (count: int, err: core.Error) {
	n := 0
	for path in paths {
		_, perr := register_plugin_entry(path)
		if perr != .None {
			// Skip plugins that fail to load; keep going.
			continue
		}
		n += 1
	}
	return n, .None
}

// plugin_loaded is the host-owned list of every loaded ^Plugin_Entry.  It
// keeps each library's handle and function pointers alive for the
// process lifetime.  The platform layer drains and destroys every handle
// in this list before dlclose during worker.stop.
plugin_loaded: [dynamic]^Plugin_Entry

// plugin_handle_count reports how many plugin libraries are currently loaded.
plugin_handle_count :: proc() -> int {
	return len(plugin_loaded)
}

// unload_all_plugins destroys and unloads every loaded plugin.  Called by
// the platform layer after the worker pool has stopped and all per-thread
// handles have been destroyed.
unload_all_plugins :: proc() {
	for p in plugin_loaded {
		unload_plugin(p)
	}
	plugin_loaded = [dynamic]^Plugin_Entry{}
}

// plugin_forward resolves the loaded Plugin_Entry whose algorithm id
// matches, by scanning the loaded-plugin list.  The plugin count is small
// (single digits in practice) so a linear scan is cheap.  Returns nil if
// the id is not a loaded plugin.
plugin_forward :: proc(id: core.Algo_Id) -> ^Plugin_Entry {
	for p in plugin_loaded {
		if p != nil && int(p^.vtable_id) == int(id) {
			return p
		}
	}
	return nil
}

register_plugin_entry :: proc(path: string) -> (entry: Algo_Entry, err: core.Error) {
	pe, lerr := load_plugin(path)
	if lerr != .None {
		return Algo_Entry{}, lerr
	}
	pe_ptr := new(Plugin_Entry)
	if pe_ptr == nil {
		platform.dl_close(pe.handle)
		return Algo_Entry{}, .Internal
	}
	pe_ptr^ = pe

	// Read the info block from the vtable.
	info := cast(^c_algo_info_view) rawptr(pe.vtable)

	plugin_entry := Algo_Entry{
		id     = core.Algo_Id(u32(info.id)),
		name   = platform.dl_c_from_ptr(info.name),
		alias  = platform.dl_c_from_ptr(info.alias),
		memory = u64(info.memory),
	}
	// Forwarder procs resolve the C pointers via the global plugin table
	// at call time.  Odin closures do not capture locals, so the C
	// function pointers live in the ^Plugin_Entry stored in plugin_table.
	plugin_entry.create = plugin_create_forward
	plugin_entry.destroy = plugin_destroy_forward
	plugin_entry.prepare = plugin_prepare_forward
	plugin_entry.hash = plugin_hash_forward
	if pe.pipeline_fn != nil {
		plugin_entry.pipeline = plugin_pipeline_forward
	}

	reg_err := register(plugin_entry)
	if reg_err != .None {
		platform.dl_close(pe.handle)
		free(pe_ptr)
		return Algo_Entry{}, reg_err
	}

	// Stash the ^Plugin_Entry so the forwarders can find the C pointers.
	// The id (e.g. 1000 for plugin-reserved) is stored in pe.vtable_id
	// and matched by plugin_forward's linear scan.
	_, _ = append(&plugin_loaded, pe_ptr)
	return plugin_entry, .None
}

//
// Forwarder procs.  Each is a package-level proc assigned to an
// Algo_Entry field; it resolves the loaded ^Plugin_Entry from the global
// plugin_table (keyed by algorithm id) and calls the corresponding C
// function pointer.  The id comes from the Algo_Handle / Algo_Config
// that the worker passes in.
//

plugin_create_forward :: proc(config: core.Algo_Config) -> (Algo_Handle, core.Error) {
	pe := plugin_forward(config.id)
	if pe == nil {
		return Algo_Handle{}, .Not_Initialized
	}
	key := plugin_key(config)
	huge := c.int(0)
	if config.huge_pages {
		huge = c.int(1)
	}
	c_create := cast(c_create_fn) pe.create_fn
	ctx := c_create(c.uint32_t(config.flags), huge,
		c.uint32_t(config.thread_index), &key[0], c.size_t(32))
	if ctx == nil {
		return Algo_Handle{}, .Ffi_Init_Failed
	}
	return Algo_Handle{id = config.id, ctx = ctx}, .None
}

// mark writes a short host-side marker to stderr via the platform C
plugin_destroy_forward :: proc(h: Algo_Handle) {
	pe := plugin_forward(h.id)
	if pe == nil {
		return
	}
	if h.ctx != nil {
		c_destroy := cast(c_destroy_fn) pe.destroy_fn
		c_destroy(h.ctx)
	}
}

plugin_prepare_forward :: proc(h: Algo_Handle, key: []u8) -> core.Error {
	pe := plugin_forward(h.id)
	if pe == nil {
		return .Not_Initialized
	}
	if h.ctx == nil {
		return .Ffi_Handle_Invalid
	}
	key_ptr := rawptr(nil)
	key_size := c.size_t(0)
	if len(key) > 0 {
		key_ptr = &key[0]
		key_size = c.size_t(len(key))
	}
	c_prepare := cast(c_prepare_fn) pe.prepare_fn
	r := c_prepare(h.ctx, key_ptr, key_size)
	if r != 0 {
		return .Ffi_Call_Failed
	}
	return .None
}

plugin_hash_forward :: proc(h: Algo_Handle, input: []u8, nonce: core.Nonce, out: ^core.Hash) -> core.Error {
	pe := plugin_forward(h.id)
	if pe == nil {
		return .Not_Initialized
	}
	if h.ctx == nil {
		return .Ffi_Handle_Invalid
	}
	if len(input) == 0 {
		return .Invalid_Argument
	}
	combined := make([dynamic]u8, len(input)+8)
	copy(combined[:len(input)], input[:])
	n := u64(nonce)
	for i in 0 ..< 8 {
		combined[len(input)+i] = u8((n >> (u32(i)*8)) & 0xff)
	}
		c_hash := cast(c_hash_fn) pe.hash_fn
	r := c_hash(h.ctx, &combined[0], c.size_t(len(combined)), rawptr(out))
	if r != 0 {
		return .Ffi_Call_Failed
	}
	out.len = u32(core.MAX_HASH_SIZE)
	return .None
}

plugin_pipeline_forward :: proc(h: Algo_Handle, input: []u8, start: core.Nonce, count: u64) -> core.Error {
	pe := plugin_forward(h.id)
	if pe == nil {
		return .Not_Initialized
	}
	if h.ctx == nil {
		return .Ffi_Handle_Invalid
	}
	if len(input) == 0 || count == 0 {
		return .Invalid_Argument
	}
	outs := make([dynamic]u8, count*32)
	c_pipe := cast(c_pipeline_fn) pe.pipeline_fn
	r := c_pipe(h.ctx, rawptr(&input[0]), c.size_t(len(input)),
		c.uint64_t(start), c.size_t(count), rawptr(&outs[0]))
	if r != 0 {
		return .Ffi_Call_Failed
	}
	return .None
}
