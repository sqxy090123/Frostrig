package frostrig_tests

import testing "core:testing"

import core "../core"
import algo "../algo"
import randomx_odin "../algo/randomx_odin"

// The pure-Odin interpreter core is cross-checked against the official C
// library instruction by instruction (see build-fix.sh's gold harness).  This
// file keeps that regression at the package boundary now that the rx/odin
// entry routes to the official JIT instead of the interpreter.
//
// The dataset is filled deterministically instead of being Argon2-expanded, so
// the oracle runs in seconds rather than the ~34 minutes a real expansion
// takes.  The gold vectors are the outputs of the official library's own
// randomx_calculate_hash on that identical dataset, with RANDOMX_FLAG_FULL_MEM:
// the interpreter port always allocates base + extra, so the address wrapping
// must match the full-memory configuration.
golden_input_vector :: struct {
	input: string,
	nonce: core.Nonce,
	gold:  string,
}

// load_deterministic_dataset points the context at a dataset whose contents are
// reproducible, so a gold vector computed once stays valid forever.  The
// returned slice is the caller's to delete before destroying the handle.
load_deterministic_dataset :: proc(ctx: ^randomx_odin.Odin_RandomX_Context) -> []u8 {
	dataset := make([]u8, randomx_odin.DATASET_SIZE)
	p := ([^]u64)(uintptr(raw_data(dataset)))
	for i in 0 ..< len(dataset) / 8 {
		p[i] = u64(i) * 0x9E3779B97F4A7C15 ~ 0xD1B54A32D192ED03
	}
	ctx.vm.dataset = dataset
	ctx.ready = true
	return dataset
}

// NOTE: a C gold harness that appends the nonce must keep the nonce in a
// 64-bit register.  Shifting a 32-bit value by 32 or more is undefined
// behaviour and silently corrupts nonce bytes 4-7, which made vectors 1 and 2
// below look like port bugs for a long while.
@(test)
rx_odin_interpreter_hash_matches_official_library :: proc(t: ^testing.T) {
	ctx := randomx_odin.create_odin_randomx()
	testing.expect(t, ctx != nil, "create must succeed")
	defer randomx_odin.destroy_odin_randomx(ctx)
	dataset := load_deterministic_dataset(ctx)
	defer delete(dataset)

	vectors: [3]golden_input_vector
	vectors[0] = { "test input 000", 0, "565f33765f50b84f836be781c7b8c996ae56bbf9d61dcc7e008d4873295b087d" }
	vectors[1] = { "test input 000", 1, "f82f155dacca289fdf22f379f9359fc291f27a457da3bb19bddd2422425e585a" }
	vectors[2] = { "Lorem ipsum dolor sit amet", 42, "0f65aa84311779fa36eadf2995b8473cc9dd49a2716ff7c4118ae359f794b8e4" }

	buf: [64]byte
	out: [32]u8
	for v in vectors {
		copy(buf[:], v.input)
		for i in 0 ..< 8 {
			buf[len(v.input) + i] = u8(v.nonce >> (u32(i) * 8))
		}
		randomx_odin.hash_odin_randomx(ctx, buf[:len(v.input) + 8], out[:])
		check_u8_slice(t, out[:], v.gold)
	}
}

// The rx/odin entry now wraps the official C JIT, so a full hash would need
// the ~34 min Argon2 expansion in prepare.  This only round-trips the handle to
// validate the entry seam (create/destroy) without that cost.
@(test)
rx_odin_entry_create_destroy_roundtrip :: proc(t: ^testing.T) {
	entry := algo.randomx_odin_entry
	handle, err := entry.create(core.Algo_Config{})
	testing.expect(t, err == core.Error.None, "create must succeed")
	testing.expect(t, handle.id == entry.id, "handle must carry the rx/odin id")
	entry.destroy(handle)
}
