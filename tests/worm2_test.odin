package frostrig_tests

import testing "core:testing"
import os "core:os"
import fmt "core:fmt"
import strconv "core:strconv"
import core "../core"
import algo "../algo"

// worm2_to_hex renders bytes as lowercase hex for failure diagnostics.
worm2_to_hex :: proc(b: []u8) -> string {
	d := make([]u8, 16)
	copy(d, []u8{0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37,
		0x38, 0x39, 0x61, 0x62, 0x63, 0x64, 0x65, 0x66})
	hex := make([]u8, 2*len(b))
	for i in 0 ..< len(b) {
		hex[2*i] = d[int(b[i]) >> 4]
		hex[2*i+1] = d[int(b[i]) & 15]
	}
	return string(hex)
}

// worm2_hex_equal compares a byte slice against a hex reference vector.
worm2_hex_equal :: proc(b: []u8, hex: string) -> bool {
	if len(b) != len(hex) / 2 {
		return false
	}
	for i in 0 ..< len(b) {
		v, ok := strconv.parse_int(hex[2*i:2*i+2], 16)
		if ok == false || b[i] != u8(v) {
			return false
		}
	}
	return true
}

worm2_blob_a :: proc() -> [96]u8 {
	b: [96]u8
	for i in 0 ..< 96 {
		b[i] = u8(i)
	}
	return b
}

worm2_blob_b :: proc() -> [160]u8 {
	b: [160]u8
	for i in 0 ..< 80 {
		b[i] = 0xAB
	}
	for i in 80 ..< 160 {
		b[i] = u8(i - 80)
	}
	return b
}

worm2_entry_lookup :: proc(t: ^testing.T) -> algo.Algo_Entry {
	// main.odin registers the built-in rows; the test package links only the
	// algo package, so the suite registers Worm/2 on its own.
	err := algo.register(algo.worm2_entry)
	// later tests in the suite see the row again
	testing.expect(t, err == core.Error.None || err == core.Error.Already_Initialized,
		"worm/2 registration failed")
	entry, ok := algo.lookup_by_name("worm/2")
	testing.expect(t, ok, "worm/2 must be registered")
	return entry
}

// worm2_open_handle shrinks the first axis to 4 rows so the suite runs on a
// machine that cannot address a 2 GiB matrix; docs/algos/worm2.md lists the
// scale switch as the only non-whitepaper knob.
worm2_open_handle :: proc(t: ^testing.T, entry: algo.Algo_Entry) -> algo.Algo_Handle {
	_ = os.set_env("FROSTRIG_WORM2_ROWS", "4")
	cfg := core.Algo_Config{
		id           = entry.id,
		huge_pages   = false,
		full_memory  = false,
		flags        = 0,
		thread_index = 0,
	}
	handle, err := entry.create(cfg)
	if err != core.Error.None {
		fmt.printfln("worm2 create failed: %v", err)
		testing.fail(t)
	}
	return handle
}

// test_worm2_hash_matches_reference pins the implementation to reference
// vectors produced by an independent Python port of the whitepaper: ChaCha20
// counter-mode matrix expansion plus the b2b-256 state walk on a
// 4 x 1024 x 2 torus of 1 KiB cells.
@(test)
test_worm2_hash_matches_reference :: proc(t: ^testing.T) {
	entry := worm2_entry_lookup(t)
	handle := worm2_open_handle(t, entry)
	defer entry.destroy(handle)

	blob_a := worm2_blob_a()
	out := core.Hash{}
	err := entry.hash(handle, blob_a[:], 0, &out)
	if err != core.Error.None || out.len != 32 {
		fmt.printfln("worm2 hash nonce=0 failed: %v len=%v", err, out.len)
		testing.fail(t)
	}
	want_a := "ac0d4f2f0f69eb6fb84566844156a6e909a57c51e853cd85bd71e35b2e14c2fd"
	if worm2_hex_equal(out.bytes[:32], want_a) == false {
		fmt.printfln("worm2 A/nonce0 got  %v", worm2_to_hex(out.bytes[:32]))
		fmt.printfln("worm2 A/nonce0 want %v", want_a)
		testing.fail(t)
	}

	err = entry.hash(handle, blob_a[:], 1, &out)
	if err != core.Error.None {
		fmt.printfln("worm2 hash nonce=1 failed: %v", err)
		testing.fail(t)
	}
	want_a1 := "fa7fe2013153a003c4f89f8067aa5aef5a4b9ca22f85b462d25c5ddd1e8831f1"
	if worm2_hex_equal(out.bytes[:32], want_a1) == false {
		fmt.printfln("worm2 A/nonce1 got  %v", worm2_to_hex(out.bytes[:32]))
		fmt.printfln("worm2 A/nonce1 want %v", want_a1)
		testing.fail(t)
	}

	blob_b := worm2_blob_b()
	err = entry.hash(handle, blob_b[:], 0, &out)
	if err != core.Error.None {
		fmt.printfln("worm2 hash blob B failed: %v", err)
		testing.fail(t)
	}
	want_b := "ef21c20e9eb4bfb99ac0908459cb034ee0bb2d7861b7548fd585eb0a1009f477"
	if worm2_hex_equal(out.bytes[:32], want_b) == false {
		fmt.printfln("worm2 B/nonce0 got  %v", worm2_to_hex(out.bytes[:32]))
		fmt.printfln("worm2 B/nonce0 want %v", want_b)
		testing.fail(t)
	}
}

// test_worm2_determinism_and_guards checks idempotence per (blob, nonce),
// divergence across nonces and blobs, the matrix rebuild path, and the
// argument guards.
@(test)
test_worm2_determinism_and_guards :: proc(t: ^testing.T) {
	entry := worm2_entry_lookup(t)
	handle := worm2_open_handle(t, entry)
	defer entry.destroy(handle)

	blob := worm2_blob_a()
	h1 := core.Hash{}
	h2 := core.Hash{}
	h3 := core.Hash{}
	if entry.hash(handle, blob[:], 7, &h1) != core.Error.None {
		testing.fail(t)
	}
	if entry.hash(handle, blob[:], 7, &h2) != core.Error.None {
		testing.fail(t)
	}
	for i in 0 ..< 32 {
		if h1.bytes[i] != h2.bytes[i] {
			fmt.printfln("worm2 is not deterministic for the same nonce")
			testing.fail(t)
		}
	}
	if entry.hash(handle, blob[:], 8, &h3) != core.Error.None {
		testing.fail(t)
	}
	identical := true
	for i in 0 ..< 32 {
		if h1.bytes[i] != h3.bytes[i] {
			identical = false
		}
	}
	testing.expect(t, identical == false, "worm2 nonce does not affect the output")

	other := worm2_blob_b()
	h4 := core.Hash{}
	if entry.hash(handle, other[:], 7, &h4) != core.Error.None {
		testing.fail(t)
	}
	// a different blob rebuilds the matrix, so the output must move
	different := false
	for i in 0 ..< 32 {
		if h1.bytes[i] != h4.bytes[i] {
			different = true
		}
	}
	testing.expect(t, different, "worm2 ignores the blob when deriving the matrix")

	if entry.hash(handle, make([]u8, 0), 0, &h1) != core.Error.Invalid_Argument {
		fmt.printfln("worm2 accepts an empty blob")
		testing.fail(t)
	}
	if entry.hash(handle, blob[:], 0, nil) != core.Error.Not_Initialized {
		fmt.printfln("worm2 accepts a nil output")
		testing.fail(t)
	}
}

// test_worm2_entry_metadata pins the registry row: name, alias and the 2 GiB
// per-thread working set from the whitepaper.
@(test)
test_worm2_entry_metadata :: proc(t: ^testing.T) {
	entry := worm2_entry_lookup(t)
	if entry.id != core.Algo_Id(18) {
		fmt.printfln("worm2 registry id is %v", int(entry.id))
		testing.fail(t)
	}
	if entry.alias != "worm2" {
		fmt.printfln("worm2 alias is %v", entry.alias)
		testing.fail(t)
	}
	if entry.memory != 1024*1024*1024*2 {
		fmt.printfln("worm2 memory is %v bytes", entry.memory)
		testing.fail(t)
	}
	if entry.pipeline != nil {
		fmt.printfln("worm2 must not advertise a pipelined hash path")
		testing.fail(t)
	}
}