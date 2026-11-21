package frostrig_tests

import testing "core:testing"
import "core:net"
import "core:strings"
import "core:fmt"
import os "core:os"
import core "../core"
import algo "../algo"
import gui "../gui"
import worker "../worker"

// ---------------------------------------------------------------------------
// Worm/2 walk trace
// ---------------------------------------------------------------------------

// gui_register_row puts one built-in entry into the registry.  The test package
// links only the algorithm package, so it registers rows the way main.odin does
// for the real binary.  Later tests see the row already present.
gui_register_row :: proc(t: ^testing.T, row: algo.Algo_Entry) {
	err := algo.register(row)
	testing.expect(t, err == core.Error.None || err == core.Error.Already_Initialized,
		fmt.tprintf("registering %s failed: %v", row.name, err))
}

// gui_lookup returns one registered entry, failing the test when absent.
gui_lookup :: proc(t: ^testing.T, name: string) -> algo.Algo_Entry {
	entry, ok := algo.lookup_by_name(name)
	testing.expect(t, ok, fmt.tprintf("%s must be registered", name))
	return entry
}

// gui_trace_ring walks one shrunk Worm/2 matrix and checks the trace keeps
// exactly its tail length, newest last, and reports the shrunken grid rather
// than the whitepaper's full matrix.
@(test)
gui_trace_ring :: proc(t: ^testing.T) {
	_ = os.set_env("FROSTRIG_WORM2_ROWS", "4")
	defer os.unset_env("FROSTRIG_WORM2_ROWS")

	gui_register_row(t, algo.worm2_entry)
	entry := gui_lookup(t, "worm/2")
	h, err := entry.create(core.Algo_Config{id = entry.id, thread_index = 0})
	testing.expect(t, err == core.Error.None, fmt.tprintf("handle create: %v", err))
	defer entry.destroy(h)

	state := new(algo.Gui_State)
	defer free(state)
	testing.expect(t, algo.Attach_Worm2_Gui(h, state), "attach to a Worm/2 handle")

	view := algo.Gui_Snapshot(state)
	testing.expect(t, view.rows == 4 && view.cols == 1024 && view.layers == 2,
		fmt.tprintf("grid shape %d x %d x %d, want 4 x 1024 x 2",
			view.rows, view.cols, view.layers))
	testing.expect(t, view.cell == 1024, "cell size")
	testing.expect(t, view.stride == algo.GUI_STRIDE,
		fmt.tprintf("stride %d, want %d", view.stride, algo.GUI_STRIDE))
	testing.expect(t, view.count == 0, "no cells before the first hash")

	blob := make([]u8, 96)
	defer delete(blob)
	for i in 0 ..< len(blob) {
		blob[i] = u8(i)
	}
	out := core.Hash{}
	testing.expect(t, entry.hash(h, blob[:], core.Nonce(0), &out) == core.Error.None, "hash")

	view = algo.Gui_Snapshot(state)
	testing.expect(t, view.count == algo.GUI_TRAIL_LEN,
		fmt.tprintf("trail count %d, want %d", view.count, algo.GUI_TRAIL_LEN))
	testing.expect(t, view.hashes == 1, "one finished hash")
	testing.expect(t, u64(view.steps) >= u64(algo.GUI_TRAIL_LEN),
		fmt.tprintf("steps %d, want >= %d", view.steps, algo.GUI_TRAIL_LEN))

	// Every remembered position sits inside the torus; a wrapped coordinate
	// would mean the walk overflowed its own grid.
	for i in 0 ..< int(view.count) {
		c := view.trail[i]
		testing.expect(t, c.x < view.rows && c.y < view.cols && c.z < view.layers,
			fmt.tprintf("trail[%d] (%d, %d, %d) escapes a %d x %d x %d torus",
				i, c.x, c.y, c.z, view.rows, view.cols, view.layers))
	}

	// A second hash must roll the ring instead of growing it.
	_ = entry.hash(h, blob[:], core.Nonce(1), &out)
	view = algo.Gui_Snapshot(state)
	testing.expect(t, view.count == algo.GUI_TRAIL_LEN, "ring does not grow")
	testing.expect(t, view.hashes == 2, "second hash counted")
}

// gui_trace_config covers the sampling knobs: a shorter trail caps the ring,
// a custom stride is reflected in the view, and a zero value keeps the default.
@(test)
gui_trace_config :: proc(t: ^testing.T) {
	gui_register_row(t, algo.worm2_entry)
	entry := gui_lookup(t, "worm/2")
	h, err := entry.create(core.Algo_Config{id = entry.id, thread_index = 0})
	testing.expect(t, err == core.Error.None, fmt.tprintf("handle create: %v", err))
	defer entry.destroy(h)

	state := new(algo.Gui_State)
	defer free(state)
	testing.expect(t, algo.Attach_Worm2_Gui(h, state), "attach to a Worm/2 handle")

	testing.expect(t, algo.Set_Worm2_Gui_Config(state, 0, 0), "unset keeps defaults")
	testing.expect(t, algo.Gui_Snapshot(state).stride == algo.GUI_STRIDE, "default stride")
	testing.expect(t, algo.Gui_Snapshot(state).trail_len == algo.GUI_TRAIL_LEN, "default trail")

	testing.expect(t, algo.Set_Worm2_Gui_Config(state, 1024, 5), "custom stride and trail")
	testing.expect(t, algo.Gui_Snapshot(state).stride == 1024, "custom stride applied")
	testing.expect(t, algo.Gui_Snapshot(state).trail_len == 5, "custom trail applied")

	// trail is clamped to the ring storage, stride never sinks to zero
	testing.expect(t, algo.Set_Worm2_Gui_Config(state, 4096, 999), "oversized trail clamps")
	testing.expect(t, algo.Gui_Snapshot(state).trail_len == algo.GUI_TRAIL_LEN, "trail clamped")

	// a full hash fills only the requested 5-slot ring, not the whole buffer
	testing.expect(t, algo.Set_Worm2_Gui_Config(state, 1024, 5), "back to a 5-slot ring")
	blob := make([]u8, 96)
	defer delete(blob)
	for i in 0 ..< len(blob) {
		blob[i] = u8(i)
	}
	out: core.Hash
	_ = entry.hash(h, blob[:], core.Nonce(0), &out)
	view := algo.Gui_Snapshot(state)
	testing.expect(t, view.count == 5, "ring respects the configured length")
	testing.expect(t, view.trail_len == 5, "view carries the configured length")
}

// gui_trace_attach_refuses covers the guard that keeps a viewer from being
// pointed at an algorithm with no matrix to draw.
@(test)
gui_trace_attach_refuses :: proc(t: ^testing.T) {
	gui_register_row(t, algo.randomx_odin_entry)
	other := gui_lookup(t, "randomx-odin")
	h, err := other.create(core.Algo_Config{id = other.id, thread_index = 0})
	testing.expect(t, err == core.Error.None, fmt.tprintf("handle create: %v", err))
	defer other.destroy(h)

	state := new(algo.Gui_State)
	defer free(state)
	testing.expect(t, !algo.Attach_Worm2_Gui(h, state), "non Worm/2 handle refused")
	testing.expect(t, !algo.Attach_Worm2_Gui(algo.Algo_Handle{}, state),
		"empty handle refused")
}

// gui_trace_json exercises the JSON the page polls on a trace that has not seen
// a hash yet, so a viewer that loads first still renders something sane.
@(test)
gui_trace_json :: proc(t: ^testing.T) {
	state := new(algo.Gui_State)
	defer free(state)
	scratch := make([dynamic]u8, 0, 512)
	defer delete(scratch)
	body := gui.Trace_Json(state, &scratch)
	wants := []string{`"rows":0`, `"cols":0`, `"trail":[]`}
	for i in 0 ..< len(wants) {
		want := wants[i]
		testing.expect(t, strings.index(body, want) >= 0,
			fmt.tprintf("trace json lacks %s: %s", want, body))
	}
}

// gui_page_served spins a real listener on loopback and checks the viewer
// document, the trace endpoint and the 404 path.
@(test)
gui_page_served :: proc(t: ^testing.T) {
	state := new(algo.Gui_State)
	defer free(state)
	server := new(gui.Gui_Server)
	defer free(server)
	port := u16(18121)
	for attempt in 0 ..< 8 {
		if err := gui.start(server, state, net.Address(net.IP4_Loopback), port); err == nil {
			break
		}
		port += 1
	}
	testing.expect(t, server.running, "gui listener must start")
	if !server.running {
		return
	}
	defer gui.stop(server)

	resp := http_request(int(port), "GET", "/", "", nil)
	testing.expect(t, strings.has_prefix(resp, "HTTP/1.1 200"),
		fmt.tprintf("GET / -> %s", first_line(resp)))
	testing.expect(t, strings.index(resp, `<canvas id="c">`) >= 0, "page has no canvas")
	testing.expect(t, strings.index(resp, "requestAnimationFrame") >= 0, "no render loop")
	testing.expect(t, strings.index(resp, "/gui/trace") >= 0, "page does not poll the trace")
	testing.expect(t, strings.index(resp, "X-Trace-Token") >= 0, "page does not carry the trace token")
	// the page must draw the dims the server reports, not a hardcoded 1024x1024:
	// poll() copies rows/cols/layers out of the trace JSON into dims
	testing.expect(t, strings.index(resp, "dims = { rows: t.rows") >= 0,
		"page hardcodes the grid instead of reading it from the trace")

	// /gui/trace is gated: no token -> 403, wrong token -> 403, right token -> 200
	resp = http_request(int(port), "GET", "/gui/trace", "", nil)
	testing.expect(t, strings.has_prefix(resp, "HTTP/1.1 403"),
		fmt.tprintf("GET /gui/trace without token -> %s", first_line(resp)))

	resp = http_request(int(port), "GET", "/gui/trace", "", []string{"X-Trace-Token: wrong"})
	testing.expect(t, strings.has_prefix(resp, "HTTP/1.1 403"),
		fmt.tprintf("GET /gui/trace with wrong token -> %s", first_line(resp)))

	tok := []string{fmt.tprintf("X-Trace-Token: %s", server.token)}
	resp = http_request(int(port), "GET", "/gui/trace", "", tok)
	testing.expect(t, strings.has_prefix(resp, "HTTP/1.1 200"),
		fmt.tprintf("GET /gui/trace with token -> %s", first_line(resp)))
	testing.expect(t, strings.index(resp, `"trail":`) >= 0, "trace body has no trail")

	resp = http_request(int(port), "GET", "/nope", "", nil)
	testing.expect(t, strings.has_prefix(resp, "HTTP/1.1 404"),
		fmt.tprintf("GET /nope -> %s", first_line(resp)))
}

// gui_worker_attach covers the pool half of the wiring: the viewer reaches the
// algorithm through the worker instead of poking at its handles.
@(test)
gui_worker_attach :: proc(t: ^testing.T) {
	_ = os.set_env("FROSTRIG_WORM2_ROWS", "4")
	defer os.unset_env("FROSTRIG_WORM2_ROWS")

	gui_register_row(t, algo.worm2_entry)
	entry := gui_lookup(t, "worm/2")
	pool, err := worker.create(core.Miner_Config{
		thread_count = 1,
		algo         = entry.id,
	})
	testing.expect(t, err == core.Error.None, fmt.tprintf("pool create: %v", err))
	testing.expect(t, worker.start(&pool) == core.Error.None, "pool start")
	defer worker.stop(&pool)

	state := new(algo.Gui_State)
	defer free(state)
	testing.expect(t, worker.gui_trace_attach(&pool, state), "worker attaches the trace")
	testing.expect(t, algo.Gui_Snapshot(state).rows == 4, "trace carries the shrunken grid")
}

// first_line trims a raw HTTP response down to its status line for messages.
first_line :: proc(resp: string) -> string {
	i := strings.index(resp, "\n")
	if i < 0 {
		return resp
	}
	return strings.trim_space(resp[:i])
}
