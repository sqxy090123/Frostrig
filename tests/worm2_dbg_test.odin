package frostrig_tests

import testing "core:testing"
import fmt "core:fmt"
import algo "../algo"

// worm2_dbg_check pins a diagnostic helper against a reference vector.  Every
// vector below comes from a platform hashlib reference run, so the suite
// stays anchored to an independent implementation rather than to this port.
worm2_dbg_check :: proc(t: ^testing.T, name: string, buf: []u8, size: int, want: string) {
	got := string(buf[:size])
	if got != want {
		fmt.printfln("worm2 %s\n  got  %v\n  want %v", name, got, want)
		testing.fail(t)
	}
}

// worm2_case pairs a block-boundary length with the reference digest of that
// many 'a' bytes.
worm2_case :: struct {
	size: int,
	want: string,
}

worm2_boundary_cases: [6]worm2_case = {
	worm2_case{112, "210a30a289a75571644523c15eb64acebad1ff2594c64c6148ca57cbbbc45fee"},
	worm2_case{127, "59e2f1aba240f20aa591016f5ef429990bc9c2131dcd0d30f0ffd75ed18f317d"},
	worm2_case{128, "ae2aa48507885c4c950fb809b2076f959cde9f8ea6da260d9a3587df33dac450"},
	worm2_case{129, "2f64744a6de0d2c0b56e64cf6e29a5aaa255010d415d51c75ccc82f73dccd865"},
	worm2_case{255, "177ec7b22a982dd81ec80e0f8fd488bb347952a0876fed488191b6dede62df81"},
	worm2_case{256, "eae4d3a7627549b383179dc18049964f91a6fed14c9f3fb26705eda3eeda5558"},
}

@(test)
test_worm2_dbg_vectors :: proc(t: ^testing.T) {
	hex: [64]u8
	empty: []u8
	algo.Worm2_Dbg_B2B256_Hex(empty, hex[:])
	worm2_dbg_check(t, "empty", hex[:], 64,
		"0e5751c026e543b2e8ab2eb06099daa1d1e5df47778f7787faab45cdf12fe3a8")

	ones: [128]u8
	for i in 0 ..< 128 {
		ones[i] = 1
	}
	algo.Worm2_Dbg_B2B256_Hex(ones[:], hex[:])
	worm2_dbg_check(t, "ones128", hex[:], 64,
		"fd75cfa278f05e5c6ffd7965c740b68ba58266cdb7a274cd02202c4cdaac1796")

	// Block-boundary lengths are the interesting cases: 112 stays short of the
	// buffer, 127 stops one byte short, 128 exactly fills it, 129 spills into
	// the final block, and 255/256 straddle one full intermediate block.
	for i in 0 ..< len(worm2_boundary_cases) {
		c := worm2_boundary_cases[i]
		buf: [256]u8
		for j in 0 ..< c.size {
			buf[j] = 'a'
		}
		algo.Worm2_Dbg_B2B256_Hex(buf[:c.size], hex[:])
		worm2_dbg_check(t, fmt.tprintf("a x %v", c.size), hex[:], 64, c.want)
	}

	algo.Worm2_Dbg_Compress_Zero(hex[:])
	worm2_dbg_check(t, "compress 0", hex[:], 64,
		"369d91153659e04f72062e5ab0c810e79b87b02eba995e2c98665a3dc17c7152")

	pat: [8]u8
	pat[0] = 0x01
	pat[1] = 0x02
	pat[2] = 0x03
	pat[3] = 0x04
	pat[4] = 0x05
	pat[5] = 0x06
	pat[6] = 0x07
	pat[7] = 0x08
	l: [16]u8
	algo.Worm2_Dbg_Le64Hex(pat[:], l[:])
	worm2_dbg_check(t, "le64", l[:], 16, "0807060504030201")
}