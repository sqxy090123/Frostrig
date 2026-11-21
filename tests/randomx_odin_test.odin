package frostrig_tests

import "core:fmt"
import testing "core:testing"

import randomx_odin "../algo/randomx_odin"
import aes "../algo/randomx_odin/lib/aes"

hex_val :: proc(c: byte) -> int {
	if '0' <= c && c <= '9' {
		return int(c) - int('0')
	}
	if 'a' <= c && c <= 'f' {
		return int(c) - int('a') + 10
	}
	return -1
}

check_u8_slice :: proc(t: ^testing.T, data: []u8, hexref: string) {
	n := len(hexref) / 2
	testing.expect(t, len(data) >= n, "buffer too small")
	for i in 0 ..< n {
		hi := hex_val(hexref[i * 2])
		lo := hex_val(hexref[i * 2 + 1])
		testing.expect(t, hi >= 0 && lo >= 0, "malformed hex reference")
		want := hi * 16 + lo
		if int(data[i]) != want {
			fmt.printfln("    byte %d: got %x want %x", i, data[i], want)
		}
		testing.expect(t, int(data[i]) == want, "hex bytes mismatch")
	}
}

@(test)
rx_odin_blake2b_empty_vector :: proc(t: ^testing.T) {
	out: [64]u8
	n := randomx_odin.blake2b(out[:], 64, ([]u8)(nil), nil)
	testing.expect(t, n == 0, "blake2b must return 0")
	check_u8_slice(t, out[:],
		"786a02f742015903c6c6fd852552d272912f4740e15847618a86e217f71f5419" +
		"d25e1031afee585313896444934eb04b903a685b1448b755d56f701afe9be2ce")
}

@(test)
rx_odin_blake2b_abc_vector :: proc(t: ^testing.T) {
	inp: [3]u8 = {'a', 'b', 'c'}
	out: [64]u8
	n := randomx_odin.blake2b(out[:], 64, inp[:], nil)
	testing.expect(t, n == 0, "blake2b must return 0")
	check_u8_slice(t, out[:],
		"ba80a53f981c4d0d6a2797b69f12f6e94c212f14685ac4b74b12bb6fdbffa2d17" +
		"d87c5392aab792dc252d5de4533cc9518d38aa8dbf1925ab92386edd4009923")
}

@(test)
rx_odin_blake2b_64_byte_vector :: proc(t: ^testing.T) {
	inp: [64]u8
	for i in 0 ..< 64 {
		inp[i] = u8(i)
	}
	out: [64]u8
	n := randomx_odin.blake2b(out[:], 32, inp[:], nil)
	testing.expect(t, n == 0, "blake2b must return 0")
	check_u8_slice(t, out[:],
		"10d8e6d534b00939843fe9dcc4dae48cdf008f6b8b2b82b156f5404d874887f5")
}

rx_b2b_vector :: struct {
	len:    int,
	digest: string,
}

@(test)
rx_odin_blake2b_length_vectors :: proc(t: ^testing.T) {
	vectors: [7]rx_b2b_vector
	vectors[0] = { 55, "b9256027ccf40c591b41687266d4885ee2a789a5f801b0e65845d4d4c6768942c0e0f5f7ac49c5ec2df102cf6a4061b8fd4b911fe5f664dd1ad276eb14ec2f9a" }
	vectors[1] = { 56, "071dea0e6025ffca915be0cb04e9e78cd4586668ed19ebef960b1066a4c741e34075f6c8b8f3e5310fa09a5b42bf0accf0ed24c3bf41fe2bcba02155662a4a1b" }
	vectors[2] = { 127, "930f453c4bb76e32b7f12a474d562055b31406fc5470efcc3cce21d75b2b44954b2d2fdab2b03c09b83a95a6d6dcf608564501cab69fffc2c505a0486cff1dc3" }
	vectors[3] = { 128, "cbd4ce342f3806d816b58fd5e5bba5e530083670bbac7d87b62c83819ddccaf41a5855fd4f5d77d215f413278d61c8365d1ec2aa617c0ebb3980b97833db36ab" }
	vectors[4] = { 129, "d3c0f4d636fdb51ba3ca2961a1d166f8f9f87052ae08e8f978d1c3cb2f244e7ba8b4a46f08727d5b5df98c10cf176d55833bcef00685596513f579ab3f9e879a" }
	vectors[5] = { 200, "fd63883518cd1a8ba86560f0d47df69c1d6c5c342e9cfd968c532e3f46a2656959271421968bcaa6643a16bdadef72f0fb76d4214331940bcdeb1fb0b229a2df" }
	vectors[6] = { 300, "10bc4aa8d8eac159113a712351675dae26832f89fe71f62a742b24613cef37637879d1c5fd900dda8e3af0beb0f580889a13d9c768116ecf7fa5d945511d2db6" }

	inp: [320]u8
	out: [64]u8
	for v in vectors {
		for j in 0 ..< v.len {
			inp[j] = u8(j * 13 + 5)
		}
		n := randomx_odin.blake2b(out[:], 64, inp[:v.len], nil)
		testing.expect(t, n == 0, "blake2b must return 0")
		check_u8_slice(t, out[:], v.digest)
	}
}

@(test)
rx_odin_aes_fill1 :: proc(t: ^testing.T) {
	seed: [64]u8
	for i in 0 ..< 64 {
		seed[i] = u8(i * 7 + 3)
	}
	buf: [3200]u8
	aes.fillAes1Rx4(seed[:], 256, buf[:])
	check_u8_slice(t, buf[:256],
		"77166af8dae5be458a15dc62a631bad179675e3675ad7fb67fe10fa448edd4b7" +
		"be84ca05996389663655e3152bf967393750525a7626234275d7cce42a502a37" +
		"4edc95e7637366e492a15897b87666e70b1b530672da90822e0dc0ebe5bb123e" +
		"232f9689ce4752fbc914ac1c7958a11ac9a9a14c459f8475705b8ba13fd157da" +
		"368db376e29ad8196cf5fc932cab9607a04da28249abc584c1120a658409377b" +
		"b7c19df04208385606a94a95a1e8245b88e16a5e99e92033c7aa86c8bd8a583e" +
		"c413b3a23b9166282afba49937de95753c035311b26582bceeb8c91a25e29d33" +
		"9423111506b5446450277f32167fba4c72077018667ac4ee5cb3d3a6ec2ac243")
}

@(test)
rx_odin_aes_fill4_and_hash :: proc(t: ^testing.T) {
	seed: [64]u8
	for i in 0 ..< 64 {
		seed[i] = u8(i * 7 + 3)
	}
	buf: [3200]u8
	aes.fillAes4Rx4(seed[:], 3200, buf[:])
	check_u8_slice(t, buf[:256],
		"91130ec301b376676efba75e9cdbd47779c4831b42cffbfb3e48dc50167ef6e6" +
		"9ed9a562e25ed7d096032e6baf045c5a7fec8b7143b412c2a5cf21c9205924f6" +
		"f69c1a3059c85e8a98e1153bb5ef43e27d1ff4e1fb5854e2002d4bc562c4fd12" +
		"4977b2e012bb59f4076caeb204e6ae4bfb29db54713861d25602858ee3f59355" +
		"1df4ba46fed1ff10bfde8da32e1fb92ac8d580ce3662a784fb300946f5fb1fa9" +
		"50df9bf5d436b3594c556390ada22b049789274fbbac212cc4e49170fcd7f08b" +
		"5126c56175abdcb654fab2631cdc74a8e1a9b4803a64affcb6b526f724db1e27" +
		"07e0c1dbb3c0f00b0d296384eacd59a7d09589ad2e02a4c6ba3e74c2ef294590")
	hashbuf: [64]u8
	aes.hashAes1Rx4(buf[:3200], 3200, hashbuf[:])
	check_u8_slice(t, hashbuf[:],
		"0679a475450b46c43d04cf0bd1794c0b386dd72d95f246f8a8b18d7ee0eb1d7c" +
		"48f012bded055634b2d1ecfab2b4a73d2e435cc6498a02f01d82d83c8da9904c")
}
