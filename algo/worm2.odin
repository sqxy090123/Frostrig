package frostrig_algo

import core "../core"
import os "core:os"
import sync "core:sync"
import strconv "core:strconv"

// ============================================================================
// Worm/2 -- 3D torus, full-history-cumulative, memory-hard PoW.
//
// Whitepaper: "Worm v2" (see docs/algos/worm2.md for the parameter table and
// the design review).  Spec:
//
//   * 1024 x 1024 x 2 cells, one cell = 1 KiB  ->  2 GiB matrix per thread.
//   * Matrix expanded from Seed = Hash(blob || "3dUpdateWorm2") with a
//     ChaCha20 counter-mode keystream, so the expansion is a fast KDF.
//   * Every step reads one cell and folds it into the state:
//         State = Hash(State || LE32(x) || LE32(y) || LE32(z) || Cell)
//     then dx = State[0] % rows, dy = State[1] % cols, dz = State[2] % layers,
//     with toroidal wrap on every axis.
//   * Because the state absorbs every previously visited cell, revisiting a
//     coordinate still produces a different offset, so there is no short cycle
//     to latch onto and step N cannot start before step N-1's state is final.
//
// Deviations from the whitepaper, all deliberate:
//   1. The spec names Blake3.  This build has no Blake3, so the mixing hash is
//      the b2b-256 construction function (RFC 7693, digest_length = 32),
//      cross-validated in the test suite against a platform hashlib reference.
//   2. The spec writes Seed = Hash(tx_root + height + salt).  Here the whole
//      stratum blob is hashed with the salt; the blob carries tx_root and
//      height, so per-job matrix identity is preserved without assuming a byte
//      offset inside the pool header.
//   3. The spec leaves the step count open.  WORM2_STEPS = 65536 visits about
//      3% of the matrix per hash, which keeps each hash memory-bandwidth bound.
//
// `matrix` is a reserved word in this toolchain, so the field is `grid`.
// ============================================================================

algo_id_worm2: core.Algo_Id = core.Algo_Id(18)
algo_name_worm2: string = "worm/2"
algo_alias_worm2: string = "worm2"

WORM2_SALT :: "3dUpdateWorm2"

WORM2_ROWS :: u32(1024)
WORM2_COLS :: u32(1024)
WORM2_LAYERS :: u32(2)
WORM2_CELL :: u32(1024)
WORM2_STEPS :: u32(65536)

WORM2_KEY_SIZE :: u32(32)
WORM2_NONCE_SIZE :: u32(12)
WORM2_HASH_SIZE :: u32(32)
WORM2_COORD_BYTES :: u32(12)

// ---------------------------------------------------------------------------
// Little-endian helpers
// ---------------------------------------------------------------------------

worm2_rotr64 :: #force_inline proc(w: u64, c: u32) -> u64 {
	return (w >> c) | (w << (64 - c))
}

worm2_rotl32 :: #force_inline proc(w: u32, c: u32) -> u32 {
	return (w << c) | (w >> (32 - c))
}

worm2_le64 :: proc(p: []u8) -> u64 {
	return u64(p[0]) | u64(p[1]) << 8 | u64(p[2]) << 16 | u64(p[3]) << 24 |
	       u64(p[4]) << 32 | u64(p[5]) << 40 | u64(p[6]) << 48 | u64(p[7]) << 56
}

worm2_le32 :: proc(p: []u8) -> u32 {
	return u32(p[0]) | u32(p[1]) << 8 | u32(p[2]) << 16 | u32(p[3]) << 24
}

worm2_store64le :: proc(p: []u8, v: u64) {
	p[0] = u8(v)
	p[1] = u8(v >> 8)
	p[2] = u8(v >> 16)
	p[3] = u8(v >> 24)
	p[4] = u8(v >> 32)
	p[5] = u8(v >> 40)
	p[6] = u8(v >> 48)
	p[7] = u8(v >> 56)
}

worm2_store32le :: proc(p: []u8, v: u32) {
	p[0] = u8(v)
	p[1] = u8(v >> 8)
	p[2] = u8(v >> 16)
	p[3] = u8(v >> 24)
}

// ---------------------------------------------------------------------------
// b2b-256 construction function (RFC 7693, unkeyed, digest_length = 32)
// ---------------------------------------------------------------------------

worm2_b2b_iv: [8]u64 = {
	0x6a09e667f3bcc908, 0xbb67ae8584caa73b,
	0x3c6ef372fe94f82b, 0xa54ff53a5f1d36f1,
	0x510e527fade682d1, 0x9b05688c2b3e6c1f,
	0x1f83d9abfb41bd6b, 0x5be0cd19137e2179,
}

worm2_b2b_sigma: [12][16]u32 = {
	{0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15},
	{14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3},
	{11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4},
	{7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8},
	{9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13},
	{2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9},
	{12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11},
	{13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10},
	{6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5},
	{10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0},
	{0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15},
	{14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3},
}

b2b3_state :: struct {
	h:   [8]u64,
	n:   u64,  // counter low half: total bytes consumed
	nhi: u64,  // counter high half
	blen: int, // bytes currently held in b
	b:   [128]u8,
}

// The parameter block word 0 carries digest_length | key_length<<8 |
// fanout<<16 | depth<<24, which for digest_length = 32, key_length = 0,
// fanout = depth = 1 is 0x01010020. It is XORed into h[0]; the remaining
// parameter words are all zero so the rest of the state stays at the IV.
worm2_b2b3_init :: proc(s: ^b2b3_state) {
	for i in 0 ..< 8 {
		s.h[i] = worm2_b2b_iv[i]
	}
	s.h[0] = s.h[0] ~ 0x01010020
	s.n = 0
	s.nhi = 0
	s.blen = 0
	for i in 0 ..< 128 {
		s.b[i] = 0
	}
}

// worm2_b2b3_inc adds k bytes to the 128-bit offset counter.
worm2_b2b3_inc :: proc(s: ^b2b3_state, k: u64) {
	s.n += k
	if s.n < k {
		s.nhi += 1
	}
}

// one RFC 7693 G macro, section 2.1
worm2_b2b_g :: #force_inline proc(v: ^[16]u64, m: []u64, s0: u32, s1: u32,
	a: int, b: int, c: int, d: int) {
	v[a] = v[a] + v[b] + m[s0]
	v[d] = worm2_rotr64(v[d] ~ v[a], 32)
	v[c] = v[c] + v[d]
	v[b] = worm2_rotr64(v[b] ~ v[c], 24)
	v[a] = v[a] + v[b] + m[s1]
	v[d] = worm2_rotr64(v[d] ~ v[a], 16)
	v[c] = v[c] + v[d]
	v[b] = worm2_rotr64(v[b] ~ v[c], 63)
}

// worm2_b2b3_compress is the RFC 7693 compress function, tracking
// Appendix C: the offset counter rides in v[12]/v[13], the final-block flag
// negates v[14], and the IV row occupies v[8..15].
worm2_b2b3_compress :: proc(s: ^b2b3_state, block: []u8, last: bool) {
	v: [16]u64
	for i in 0 ..< 8 {
		v[i] = s.h[i]
	}
	v[8] = worm2_b2b_iv[0]
	v[9] = worm2_b2b_iv[1]
	v[10] = worm2_b2b_iv[2]
	v[11] = worm2_b2b_iv[3]
	v[12] = worm2_b2b_iv[4]
	v[13] = worm2_b2b_iv[5]
	v[14] = worm2_b2b_iv[6]
	v[15] = worm2_b2b_iv[7]

	v[12] = v[12] ~ s.n
	v[13] = v[13] ~ s.nhi
	if last {
		v[14] = v[14] ~ 0xFFFFFFFFFFFFFFFF
	}

	m: [16]u64
	for i in 0 ..< 16 {
		m[i] = worm2_le64(block[i*8:])
	}

	for r in 0 ..< 12 {
		sigma := &worm2_b2b_sigma[r]
		worm2_b2b_g(&v, m[:], sigma[0], sigma[1], 0, 4, 8, 12)
		worm2_b2b_g(&v, m[:], sigma[2], sigma[3], 1, 5, 9, 13)
		worm2_b2b_g(&v, m[:], sigma[4], sigma[5], 2, 6, 10, 14)
		worm2_b2b_g(&v, m[:], sigma[6], sigma[7], 3, 7, 11, 15)
		worm2_b2b_g(&v, m[:], sigma[8], sigma[9], 0, 5, 10, 15)
		worm2_b2b_g(&v, m[:], sigma[10], sigma[11], 1, 6, 11, 12)
		worm2_b2b_g(&v, m[:], sigma[12], sigma[13], 2, 7, 8, 13)
		worm2_b2b_g(&v, m[:], sigma[14], sigma[15], 3, 4, 9, 14)
	}

	for i in 0 ..< 8 {
		s.h[i] = s.h[i] ~ (v[i] ~ v[8+i])
	}
}

worm2_b2b3_update :: proc(s: ^b2b3_state, data: []u8) {
	if len(data) == 0 {
		return
	}
	// A buffer that is already full is flushed as soon as more data arrives, so
	// a trailing multiple-of-128 tail is never double-compressed by final.
	if s.blen == 128 {
		worm2_b2b3_compress(s, s.b[:], false)
		s.blen = 0
	}

	n := 0
	for n < len(data) {
		rem := 128 - s.blen
		k := len(data) - n
		if k > rem {
			k = rem
		}
		copy(s.b[s.blen:], data[n:n+k])
		s.blen += k
		worm2_b2b3_inc(s, u64(k))
		n += k
		if s.blen == 128 && n < len(data) {
			worm2_b2b3_compress(s, s.b[:], false)
			s.blen = 0
		}
	}
}

worm2_b2b3_final :: proc(s: ^b2b3_state, out: []u8) {
	for i in s.blen ..< 128 {
		s.b[i] = 0
	}
	worm2_b2b3_compress(s, s.b[:], true)

	n := int(len(out))
	if n > 32 {
		n = 32
	}
	for i in 0 ..< n {
		out[i] = u8(s.h[i/8] >> u32((i % 8) * 8))
	}
}

// All scratch lives on the caller's stack so the hash stays safe under multiple
// worker threads.
worm2_b2b3_hash :: proc(data: []u8) -> [WORM2_HASH_SIZE]u8 {
	s: b2b3_state
	worm2_b2b3_init(&s)
	worm2_b2b3_update(&s, data)
	out: [WORM2_HASH_SIZE]u8
	worm2_b2b3_final(&s, out[:])
	return out
}

// ---------------------------------------------------------------------------
// ChaCha20 counter-mode keystream (matrix expansion)
// ---------------------------------------------------------------------------

worm2_chacha_qr :: #force_inline proc(v: ^[16]u32, a: int, b: int, c: int, d: int) {
	v[a] += v[b]
	v[d] = v[d] ~ v[a]
	v[d] = worm2_rotl32(v[d], 16)
	v[c] += v[d]
	v[b] = v[b] ~ v[c]
	v[b] = worm2_rotl32(v[b], 12)
	v[a] += v[b]
	v[d] = v[d] ~ v[a]
	v[d] = worm2_rotl32(v[d], 8)
	v[c] += v[d]
	v[b] = v[b] ~ v[c]
	v[b] = worm2_rotl32(v[b], 7)
}

worm2_chacha_block :: proc(key: []u8, counter: u32, nonce: []u8, out: []u8) {
	v: [16]u32
	v[0] = 0x61707865
	v[1] = 0x646e6979
	v[2] = 0x79622d32
	v[3] = 0x6b206574
	v[4] = worm2_le32(key[0:])
	v[5] = worm2_le32(key[4:])
	v[6] = worm2_le32(key[8:])
	v[7] = worm2_le32(key[12:])
	v[8] = worm2_le32(key[16:])
	v[9] = worm2_le32(key[20:])
	v[10] = worm2_le32(key[24:])
	v[11] = worm2_le32(key[28:])
	v[12] = counter
	v[13] = worm2_le32(nonce[0:])
	v[14] = worm2_le32(nonce[4:])
	v[15] = worm2_le32(nonce[8:])
	orig := v
	for i in 0 ..< 10 {
		worm2_chacha_qr(&v, 0, 4, 8, 12)
		worm2_chacha_qr(&v, 1, 5, 9, 13)
		worm2_chacha_qr(&v, 2, 6, 10, 14)
		worm2_chacha_qr(&v, 3, 7, 11, 15)
		worm2_chacha_qr(&v, 0, 5, 10, 15)
		worm2_chacha_qr(&v, 1, 6, 11, 12)
		worm2_chacha_qr(&v, 2, 7, 8, 13)
		worm2_chacha_qr(&v, 3, 4, 9, 14)
	}
	for i in 0 ..< 16 {
		worm2_store32le(out[i*4:], v[i] + orig[i])
	}
}

// ---------------------------------------------------------------------------
// Walk trace (visualisation)
// ---------------------------------------------------------------------------

// GUI_TRAIL_LEN is the number of walk positions a trace keeps: the cell the
// worm is in right now plus the ten it has just left, so a renderer can draw
// a fading tail behind the head.
GUI_TRAIL_LEN :: u32(11)

// GUI_STRIDE is how many walk steps separate two recorded positions.
// One hash is WORM2_STEPS long, so this keeps a dozen or so marks per hash
// without parking a worker thread on the trace mutex.
GUI_STRIDE :: u32(4096)

// Worm2_Cell is one visited position in the torus, in (row, column, layer)
// order.  z is the outermost axis, matching the offset maths in the walk.
Worm2_Cell :: struct {
	x: u32,
	y: u32,
	z: u32,
}

// Gui_State is the shared recording the visualisation reads.  Exactly one
// worker thread writes to an attached state (the handle it was attached to),
// so the only contention is the reader taking the mutex between polls.
Gui_State :: struct {
	mu:     sync.Mutex,
	trail:  [GUI_TRAIL_LEN]Worm2_Cell,
	head:   u32,
	filled: u32,
	steps:  u64,
	hashes: u64,
	rows:   u32,
	cols:   u32,
	layers: u32,
	cell:   u32,
	// `stride` is the sampling interval in walk steps.  Recording all 65536
	// steps of one hash would make the mutex the bottleneck, so the walk
	// marks one position every `stride` steps and the counter below tells a
	// viewer how many real steps lie between two drawn cells.
	stride: u32,
	// `trail_len` is how many of the [GUI_TRAIL_LEN] slots the ring actually
	// uses.  It is configurable (1 ..= GUI_TRAIL_LEN) so the viewer can trade
	// a longer fading tail against a heavier draw; GUI_TRAIL_LEN stays the
	// capacity of the fixed arrays below.
	trail_len: u32,
}

// Gui_View is a lock-free copy of a Gui_State handed to a
// consumer.  trail[0] is the oldest remembered step and trail[count-1] is the
// cell the worm is in at the moment of the snapshot.
Gui_View :: struct {
	trail:  [GUI_TRAIL_LEN]Worm2_Cell,
	count:  u32,
	steps:  u64,
	hashes: u64,
	rows:   u32,
	cols:   u32,
	layers: u32,
	cell:   u32,
	stride: u32,
	trail_len: u32,
}

// Attach_Worm2_Gui links a trace to one algorithm handle and stamps the trace
// with the shape of that handle's matrix, so a viewer knows which grid to draw.
// It returns false when the handle is not Worm/2, in which case the caller can
// fall back silently instead of pretending to have a viewer.
Attach_Worm2_Gui :: proc(h: Algo_Handle, s: ^Gui_State) -> bool {
	if h.ctx == nil || s == nil {
		return false
	}
	if h.id != algo_id_worm2 {
		return false
	}
	ctx := cast(^Worm2_Context) h.ctx
	s.rows = ctx.params.rows
	s.cols = ctx.params.cols
	s.layers = ctx.params.layers
	s.cell = ctx.params.cell
	s.stride = GUI_STRIDE
	s.trail_len = GUI_TRAIL_LEN
	ctx.trace = s
	return true
}

// Set_Worm2_Gui_Config tunes the sampling of an already-attached trace.  A
// zero stride or trail_len means "keep the library default", so the flag can
// be left unset without shrinking the trail to one cell.  Returns false when
// the state pointer is unusable.
Set_Worm2_Gui_Config :: proc(s: ^Gui_State, stride, trail_len: u32) -> bool {
	if s == nil {
		return false
	}
	if stride > 0 {
		s.stride = stride
	}
	if trail_len > 0 {
		s.trail_len = clamp(trail_len, 1, GUI_TRAIL_LEN)
	}
	return true
}

// worm2_gui_mark_hash counts one finished hash on the trace.
worm2_gui_mark_hash :: proc(s: ^Gui_State) {
	sync.lock(&s.mu)
	s.hashes += 1
	sync.unlock(&s.mu)
}

// worm2_gui_mark_step records one visited cell at the tail of the ring.
// The ring capacity is the configured trail_len (1 ..= GUI_TRAIL_LEN), which
// keeps a short tail cheap while still bounding the fixed storage below it.
worm2_gui_mark_step :: proc(s: ^Gui_State, x, y, z: u32) {
	sync.lock(&s.mu)
	n := s.trail_len
	if n == 0 {
		n = GUI_TRAIL_LEN
	}
	idx := (s.head + s.filled) % n
	s.trail[idx].x = x
	s.trail[idx].y = y
	s.trail[idx].z = z
	if s.filled < n {
		s.filled += 1
	} else {
		s.head = (s.head + 1) % n
	}
	s.steps += 1
	sync.unlock(&s.mu)
}

// Gui_Snapshot copies the current trace state for a viewer.
Gui_Snapshot :: proc(s: ^Gui_State) -> Gui_View {
	v := Gui_View{}
	sync.lock(&s.mu)
	n := s.trail_len
	if n == 0 {
		n = GUI_TRAIL_LEN
	}
	for i in 0 ..< int(s.filled) {
		v.trail[i] = s.trail[(s.head + u32(i)) % n]
	}
	v.count = s.filled
	v.steps = s.steps
	v.hashes = s.hashes
	v.rows = s.rows
	v.cols = s.cols
	v.layers = s.layers
	v.cell = s.cell
	v.stride = s.stride
	v.trail_len = n
	sync.unlock(&s.mu)
	return v
}

// ---------------------------------------------------------------------------
// Context
// ---------------------------------------------------------------------------

Worm2_Params :: struct {
	rows:   u32,
	cols:   u32,
	layers: u32,
	cell:   u32,
	steps:  u32,
}

Worm2_Context :: struct {
	// `grid` holds the matrix; `matrix` is a reserved word in this toolchain.
	grid:       []u8,
	matrix_key: [WORM2_KEY_SIZE]u8,
	matrix_ok:  bool,
	params:     Worm2_Params,
	ks_key:     [WORM2_KEY_SIZE]u8,
	ks_nonce:   [WORM2_NONCE_SIZE]u8,
	salt:       [len(WORM2_SALT)]u8,
	rebuild_mu: sync.Mutex,
	// `trace` is nil unless a visualisation consumer attached one; keeping it
	// off the hot path entirely when nobody is watching.
	trace: ^Gui_State,
}

worm2_matrix_bytes :: proc(p: Worm2_Params) -> u64 {
	return u64(p.rows) * u64(p.cols) * u64(p.layers) * u64(p.cell)
}

worm2_spec_params :: proc() -> Worm2_Params {
	p := Worm2_Params{}
	p.rows = WORM2_ROWS
	p.cols = WORM2_COLS
	p.layers = WORM2_LAYERS
	p.cell = WORM2_CELL
	p.steps = WORM2_STEPS
	return p
}

// FROSTRIG_WORM2_ROWS shrinks the first axis for smoke testing on machines
// that cannot spare the 2 GiB the whitepaper specifies.  The walk, offsets and
// state mixing stay byte-identical to the full build.
worm2_env_rows :: proc() -> u32 {
	buf: [64]u8
	s := os.get_env_buf(buf[:], "FROSTRIG_WORM2_ROWS")
	if len(s) == 0 {
		return WORM2_ROWS
	}
	n, ok := strconv.parse_int(s, 10)
	if ok == false || n <= 0 || n > int(WORM2_ROWS) {
		return WORM2_ROWS
	}
	return u32(n)
}

worm2_keys_equal :: proc(a: []u8, b: []u8) -> bool {
	if len(a) != len(b) {
		return false
	}
	for i in 0 ..< len(a) {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}

// worm2_derive_key computes Seed = Hash(blob || salt), the identity of the
// matrix for one job.
worm2_derive_key :: proc(blob: []u8, salt: []u8) -> [WORM2_KEY_SIZE]u8 {
	s: b2b3_state
	worm2_b2b3_init(&s)
	worm2_b2b3_update(&s, blob)
	worm2_b2b3_update(&s, salt)
	out: [WORM2_KEY_SIZE]u8
	worm2_b2b3_final(&s, out[:])
	return out
}

worm2_fill_matrix :: proc(grid: []u8, key: []u8, nonce: []u8) {
	blk: [64]u8
	counter := u32(0)
	off := 0
	total := len(grid)
	for off < total {
		worm2_chacha_block(key, counter, nonce, blk[:])
		n := 64
		if total - off < 64 {
			n = total - off
		}
		copy(grid[off:off+n], blk[:n])
		off += n
		counter += 1
	}
}

// worm2_rebuild_matrix resets the working grid to the keystream expansion of
// key.  It runs at most once per matrix identity: the seed changes once per
// pool job, exactly like the RandomX dataset.
worm2_rebuild_matrix :: proc(ctx: ^Worm2_Context, key: []u8) {
	sync.lock(&ctx.rebuild_mu)
	if ctx.matrix_ok && worm2_keys_equal(ctx.matrix_key[:], key) {
		sync.unlock(&ctx.rebuild_mu)
		return
	}
	need := worm2_matrix_bytes(ctx.params)
	if u64(len(ctx.grid)) != need {
		if len(ctx.grid) > 0 {
			delete(ctx.grid)
		}
		ctx.grid = make([]u8, int(need))
	}
	copy(ctx.ks_key[:], key[:WORM2_KEY_SIZE])
	// the nonce folds in the matrix shape, so a resized smoke-test build can
	// never share a keystream with the full build
	worm2_store32le(ctx.ks_nonce[0:], ctx.params.rows)
	worm2_store32le(ctx.ks_nonce[4:], ctx.params.cols)
	worm2_store32le(ctx.ks_nonce[8:], ctx.params.layers)
	worm2_fill_matrix(ctx.grid, ctx.ks_key[:], ctx.ks_nonce[:])
	copy(ctx.matrix_key[:], key[:WORM2_KEY_SIZE])
	ctx.matrix_ok = true
	sync.unlock(&ctx.rebuild_mu)
}

// ---------------------------------------------------------------------------
// The walk
// ---------------------------------------------------------------------------

// worm2_walk runs the full-history state machine and writes the final state
// into out.  z is the outermost axis, so a layer hop always crosses roughly
// half the matrix, which is what the whitepaper wants for TLB pressure.
worm2_walk :: proc(ctx: ^Worm2_Context, state: ^[WORM2_HASH_SIZE]u8, x0: u32,
	y0: u32, z0: u32, out: []u8) -> core.Error {
	p := ctx.params
	x: u32 = x0
	y: u32 = y0
	z: u32 = z0
	buf: [WORM2_HASH_SIZE + WORM2_COORD_BYTES + WORM2_CELL]u8
	cell_bytes := u64(p.cell)
	half := u64(p.rows) * u64(p.cols)
	gui := ctx.trace
	stride := int(GUI_STRIDE)
	if gui != nil && gui.stride > 0 {
		stride = int(gui.stride)
	}

	// Land the viewer on the starting cell so the very first poll of a hash
	// already has a position instead of an empty grid.
	if gui != nil {
		worm2_gui_mark_step(gui, x0, y0, z0)
	}

	for step in 0 ..< int(p.steps) {
		cell_off := (u64(z) * half + u64(y) * u64(p.rows) + u64(x)) * cell_bytes
		cell_start := int(cell_off)
		cell_len := int(cell_bytes)
		if cell_start + cell_len > len(ctx.grid) {
			return core.Error.Internal
		}
		cell := ctx.grid[cell_start:cell_start+cell_len]

		for i in 0 ..< int(WORM2_HASH_SIZE) {
			buf[i] = state[i]
		}
		worm2_store32le(buf[WORM2_HASH_SIZE:], x)
		worm2_store32le(buf[WORM2_HASH_SIZE+4:], y)
		worm2_store32le(buf[WORM2_HASH_SIZE+8:], z)
		copy(buf[WORM2_HASH_SIZE+WORM2_COORD_BYTES:], cell)
		h := worm2_b2b3_hash(buf[:WORM2_HASH_SIZE+WORM2_COORD_BYTES+u32(cell_len)])
		for i in 0 ..< int(WORM2_HASH_SIZE) {
			state[i] = h[i]
		}

	dx := u32(state[0]) % p.rows
		dy := u32(state[1]) % p.cols
		dz := u32(state[2]) % p.layers
		x = (x + dx) % p.rows
		y = (y + dy) % p.cols
		z = (z + dz) % p.layers

		// A viewer samples every GUI_STRIDE-th landing so the mutex
		// never becomes the slow part of the hash.
		if gui != nil && step % stride == 0 {
			worm2_gui_mark_step(gui, x, y, z)
		}
	}

	for i in 0 ..< int(WORM2_HASH_SIZE) {
		out[i] = state[i]
	}
	return .None
}

// ---------------------------------------------------------------------------
// Algo_Entry glue
// ---------------------------------------------------------------------------

worm2_create :: proc(config: core.Algo_Config) -> (Algo_Handle, core.Error) {
	params := worm2_spec_params()
	params.rows = worm2_env_rows()

	ctx := new(Worm2_Context)
	ctx.params = params
	ctx.grid = make([]u8, int(worm2_matrix_bytes(params)))
	if u64(len(ctx.grid)) != worm2_matrix_bytes(params) {
		free(ctx)
		return {}, .Out_Of_Memory
	}
	salt := WORM2_SALT
	for i in 0 ..< len(salt) {
		ctx.salt[i] = salt[i]
	}
	h := Algo_Handle{}
	h.id = config.id
	h.ctx = rawptr(ctx)
	return h, .None
}

worm2_destroy :: proc(handle: Algo_Handle) {
	if handle.ctx == nil {
		return
	}
	ctx := cast(^Worm2_Context) handle.ctx
	if len(ctx.grid) > 0 {
		delete(ctx.grid)
	}
	free(ctx)
}

worm2_prepare :: proc(handle: Algo_Handle, seed: []u8) -> core.Error {
	if handle.ctx == nil {
		return core.Error.Not_Initialized
	}
	ctx := cast(^Worm2_Context) handle.ctx
	key := worm2_derive_key(seed, ctx.salt[:])
	worm2_rebuild_matrix(ctx, key[:])
	return .None
}

worm2_hash_inner :: proc(ctx: ^Worm2_Context, input: []u8, nonce: u64, output: ^core.Hash) -> core.Error {
	state: [WORM2_HASH_SIZE]u8
	nonce_le: [8]u8
	s: b2b3_state

	// State_0 = Hash(blob || LE64(nonce) || salt).  The starting coordinates
	// come out of the same state, so the walk is pinned to this nonce.
	worm2_b2b3_init(&s)
	worm2_b2b3_update(&s, input)
	worm2_store64le(nonce_le[:], nonce)
	worm2_b2b3_update(&s, nonce_le[:])
	worm2_b2b3_update(&s, ctx.salt[:])
	tmp: [WORM2_HASH_SIZE]u8
	worm2_b2b3_final(&s, tmp[:])
	for i in 0 ..< int(WORM2_HASH_SIZE) {
		state[i] = tmp[i]
	}

	x0 := worm2_le32(state[0:]) % ctx.params.rows
	y0 := worm2_le32(state[4:]) % ctx.params.cols
	z0 := worm2_le32(state[8:]) % ctx.params.layers

	err := worm2_walk(ctx, &state, x0, y0, z0, output.bytes[:])
	if err != .None {
		return err
	}
	output.len = WORM2_HASH_SIZE
	if ctx.trace != nil {
		worm2_gui_mark_hash(ctx.trace)
	}
	return .None
}

worm2_hash :: proc(handle: Algo_Handle, input: []u8, nonce: core.Nonce, output: ^core.Hash) -> core.Error {
	if handle.ctx == nil || output == nil {
		return core.Error.Not_Initialized
	}
	if len(input) == 0 {
		return core.Error.Invalid_Argument
	}
	ctx := cast(^Worm2_Context) handle.ctx

	key := worm2_derive_key(input, ctx.salt[:])
	worm2_rebuild_matrix(ctx, key[:])
	return worm2_hash_inner(ctx, input, u64(nonce), output)
}

// Worm2_Dbg_B2B256_Hex renders the digest of data as 64 lowercase hex chars
// into out, which must hold at least 64 bytes.  The caller supplies the
// buffer so the helper performs no allocation at all.
Worm2_Dbg_B2B256_Hex :: proc(data: []u8, out: []u8) {
	d: [16]u8
	copy(d[:], []u8{0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37,
		0x38, 0x39, 0x61, 0x62, 0x63, 0x64, 0x65, 0x66})
	digest := worm2_b2b3_hash(data)
	for i in 0 ..< int(WORM2_HASH_SIZE) {
		out[2*i] = d[digest[i] >> 4]
		out[2*i+1] = d[digest[i] & 0xf]
	}
}

// Worm2_Dbg_Le64Hex renders the first 8 bytes of b as a little-endian u64
// written as 16 lowercase hex chars into out (16 bytes).
Worm2_Dbg_Le64Hex :: proc(b: []u8, out: []u8) {
	v := worm2_le64(b[:8])
	d: [16]u8
	copy(d[:], []u8{0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37,
		0x38, 0x39, 0x61, 0x62, 0x63, 0x64, 0x65, 0x66})
	for i in 0 ..< 8 {
		// most significant nibble first, so the rendered text reads as the
		// little-endian word's numeric value
		w := u64(v >> u32(56 - 8*i))
		out[2*i] = d[int(w / 16) % 16]
		out[2*i+1] = d[int(w % 16)]
	}
}

// Worm2_Dbg_Compress_Zero runs a single non-final compress over 128 zero
// bytes and renders the resulting chaining value as 64 lowercase hex chars
// into out (64 bytes).  It exercises the round function directly, which the
// hash vectors only reach indirectly.
Worm2_Dbg_Compress_Zero :: proc(out: []u8) {
	s: b2b3_state
	worm2_b2b3_init(&s)
	z: [128]u8
	worm2_b2b3_compress(&s, z[:], false)
	d: [16]u8
	copy(d[:], []u8{0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37,
		0x38, 0x39, 0x61, 0x62, 0x63, 0x64, 0x65, 0x66})
	for i in 0 ..< int(WORM2_HASH_SIZE) {
		w := u64(s.h[i/8] >> u32((i % 8) * 8))
		out[2*i] = d[int(w >> 4) % 16]
		out[2*i+1] = d[int(w % 16)]
	}
}

worm2_entry: Algo_Entry = Algo_Entry{
	id       = algo_id_worm2,
	name     = algo_name_worm2,
	alias    = algo_alias_worm2,
	memory   = u64(1024) * u64(1024) * u64(2) * u64(1024),
	create   = worm2_create,
	destroy  = worm2_destroy,
	prepare  = worm2_prepare,
	hash     = worm2_hash,
}
