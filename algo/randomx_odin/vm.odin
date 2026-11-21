package frostrig_randomx_odin

import "core:mem"
import "lib/aes"

// ===== Constants (from configuration.h / common.hpp) =====
PROGRAM_SIZE :: 256
PROGRAM_ITERATIONS :: 2048
PROGRAM_COUNT :: 8
SCRATCHPAD_L1 :: 16384
SCRATCHPAD_L2 :: 262144
SCRATCHPAD_L3 :: 2097152
SCRATCHPAD_SIZE :: SCRATCHPAD_L3

L1_U64 :: SCRATCHPAD_L1 / 8
L2_U64 :: SCRATCHPAD_L2 / 8
L3_U64 :: SCRATCHPAD_L3 / 8
L1_MASK :: (L1_U64 - 1) * 8
L2_MASK :: (L2_U64 - 1) * 8
L3_MASK :: (L3_U64 - 1) * 8
L3_MASK64 :: (L3_U64 / 8 - 1) * 64

CACHE_LINE_SIZE :: 64
CACHE_LINE_ALIGN_MASK :: u64(2147483648 - 1) & ~u64(CACHE_LINE_SIZE - 1)
DATASET_EXTRA_ITEMS :: 33554368 / 64

CONDITION_MASK :: 0xFF
CONDITION_OFFSET :: 8
STORE_L3_CONDITION :: 14

MANTISSA_MASK :: (1 << 52) - 1
DYNAMIC_MANTISSA_MASK :: (1 << 56) - 1
CONST_EXPONENT_BITS :: 0x300

// ceil thresholds for opcode -> InstructionType mapping
ceil_IADD_RS :: 16
ceil_IADD_M :: 23
ceil_ISUB_R :: 39
ceil_ISUB_M :: 46
ceil_IMUL_R :: 62
ceil_IMUL_M :: 66
ceil_IMULH_R :: 70
ceil_IMULH_M :: 71
ceil_ISMULH_R :: 75
ceil_ISMULH_M :: 76
ceil_IMUL_RCP :: 84
ceil_INEG_R :: 86
ceil_IXOR_R :: 101
ceil_IXOR_M :: 106
ceil_IROR_R :: 114
ceil_IROL_R :: 116
ceil_ISWAP_R :: 120
ceil_FSWAP_R :: 124
ceil_FADD_R :: 140
ceil_FADD_M :: 145
ceil_FSUB_R :: 161
ceil_FSUB_M :: 166
ceil_FSCAL_R :: 172
ceil_FMUL_R :: 204
ceil_FDIV_M :: 208
ceil_FSQRT_R :: 214
ceil_CBRANCH :: 239
ceil_CFROUND :: 240
ceil_ISTORE :: 256

// ===== Types =====
Vec :: #simd[2]f64

InstrType :: enum u8 {
	IADD_RS, IADD_M, ISUB_R, ISUB_M, IMUL_R, IMUL_M, IMULH_R, IMULH_M,
	ISMULH_R, ISMULH_M, IMUL_RCP, INEG_R, IXOR_R, IXOR_M, IROR_R, IROL_R,
	ISWAP_R, FSWAP_R, FADD_R, FADD_M, FSUB_R, FSUB_M, FSCAL_R, FMUL_R,
	FDIV_M, FSQRT_R, CBRANCH, CFROUND, ISTORE, NOP,
}

InstructionByteCode :: struct {
	idst: rawptr,
	isrc: rawptr,
	imm: u64,
	op: InstrType,
	target: i16,
	shift: u16,
	mem_mask: u32,
}

Program :: struct {
	entropy: [16]u64,
	program_buffer: [384]Instruction,
}

NRegFile :: struct {
	r: [8]u64,
	f: [4]Vec,
	e: [4]Vec,
	a: [4]Vec,
}

RegisterFile :: struct {
	r: [8]u64,
	f: [4]Vec,
	e: [4]Vec,
	a: [4]Vec,
}

ProgramConfiguration :: struct {
	e_mask: [2]u64,
	read_reg0, read_reg1, read_reg2, read_reg3: u32,
}

MemoryRegisters :: struct {
	mx, ma: u32,
	memory: []u8,
}

// ===== FP shim (foreign) =====
foreign import fpshim "fpshim.o"

@(default_calling_convention = "c")
foreign fpshim {
	odin_set_mxcsr :: proc(v: u32) ---
	odin_cvt :: proc(lo, hi: i32) -> Vec ---
	odin_add :: proc(a, b: Vec) -> Vec ---
	odin_sub :: proc(a, b: Vec) -> Vec ---
	odin_mul :: proc(a, b: Vec) -> Vec ---
	odin_div :: proc(a, b: Vec) -> Vec ---
	odin_sqrt :: proc(a: Vec) -> Vec ---
	odin_swap :: proc(a: Vec) -> Vec ---
	odin_set_vec :: proc(x1, x0: u64) -> Vec ---
	odin_set1 :: proc(x: u64) -> Vec ---
	odin_xor :: proc(a, b: Vec) -> Vec ---
	odin_and :: proc(a, b: Vec) -> Vec ---
	odin_or :: proc(a, b: Vec) -> Vec ---
}

zero_reg: u64 = 0

// ===== Utility =====
sign_extend_2s :: proc(x: u32) -> u64 {
	return u64(cast(i64)cast(i32)x)
}

rotl64 :: proc(x: u64, c: u32) -> u64 {
	cc := c & 63
	return (x << cc) | (x >> (64 - cc))
}

get_small_positive_float_bits :: proc(entropy: u64) -> u64 {
	exponent := (entropy >> 59) + 1023
	exponent &= 0x7FF
	exponent <<= 52
	mantissa := entropy & MANTISSA_MASK
	return exponent | mantissa
}

get_static_exponent :: proc(entropy: u64) -> u64 {
	exponent := u64(CONST_EXPONENT_BITS)
	exponent |= (entropy >> (64 - 4)) << 4
	exponent <<= 52
	return exponent
}

get_float_mask :: proc(entropy: u64) -> u64 {
	mask22 := (1 << 22) - 1
	return (entropy & u64(mask22)) | get_static_exponent(entropy)
}

// ===== Bytecode compiler =====
compile_program :: proc(program: ^Program, bytecode: []InstructionByteCode, nreg: ^NRegFile) {
	register_usage: [8]i32
	for i in 0 ..< 8 do register_usage[i] = -1

	for i in 0 ..< PROGRAM_SIZE {
		instr := &program.program_buffer[i]
		ibc := &bytecode[i]
		opcode := instr.opcode

		if opcode < ceil_IADD_RS {
			dst := u32(instr.dst) % 8
			src := u32(instr.src) % 8
			ibc.op = .IADD_RS
			ibc.idst = cast(rawptr)&nreg.r[dst]
			ibc.isrc = cast(rawptr)&nreg.r[src]
			ibc.shift = u16((instr.mod >> 2) % 4)
			if dst != 5 {
				ibc.imm = 0
			} else {
				ibc.imm = sign_extend_2s(instr.imm32)
			}
			register_usage[dst] = i32(i)
			continue
		}

		if opcode < ceil_IADD_M {
			dst := u32(instr.dst) % 8
			src := u32(instr.src) % 8
			ibc.op = .IADD_M
			ibc.idst = cast(rawptr)&nreg.r[dst]
			ibc.imm = sign_extend_2s(instr.imm32)
			if src != dst {
				ibc.isrc = cast(rawptr)&nreg.r[src]
				ibc.mem_mask = u32(instr.mod % 4 != 0 ? L1_MASK : L2_MASK)
			} else {
				ibc.isrc = cast(rawptr)&zero_reg
				ibc.mem_mask = L3_MASK
			}
			register_usage[dst] = i32(i)
			continue
		}

		if opcode < ceil_ISUB_R {
			dst := u32(instr.dst) % 8
			src := u32(instr.src) % 8
			ibc.op = .ISUB_R
			ibc.idst = cast(rawptr)&nreg.r[dst]
			if src != dst {
				ibc.isrc = cast(rawptr)&nreg.r[src]
			} else {
				ibc.imm = sign_extend_2s(instr.imm32)
				ibc.isrc = cast(rawptr)&ibc.imm
			}
			register_usage[dst] = i32(i)
			continue
		}

		if opcode < ceil_ISUB_M {
			dst := u32(instr.dst) % 8
			src := u32(instr.src) % 8
			ibc.op = .ISUB_M
			ibc.idst = cast(rawptr)&nreg.r[dst]
			ibc.imm = sign_extend_2s(instr.imm32)
			if src != dst {
				ibc.isrc = cast(rawptr)&nreg.r[src]
				ibc.mem_mask = u32(instr.mod % 4 != 0 ? L1_MASK : L2_MASK)
			} else {
				ibc.isrc = cast(rawptr)&zero_reg
				ibc.mem_mask = L3_MASK
			}
			register_usage[dst] = i32(i)
			continue
		}

		if opcode < ceil_IMUL_R {
			dst := u32(instr.dst) % 8
			src := u32(instr.src) % 8
			ibc.op = .IMUL_R
			ibc.idst = cast(rawptr)&nreg.r[dst]
			if src != dst {
				ibc.isrc = cast(rawptr)&nreg.r[src]
			} else {
				ibc.imm = sign_extend_2s(instr.imm32)
				ibc.isrc = cast(rawptr)&ibc.imm
			}
			register_usage[dst] = i32(i)
			continue
		}

		if opcode < ceil_IMUL_M {
			dst := u32(instr.dst) % 8
			src := u32(instr.src) % 8
			ibc.op = .IMUL_M
			ibc.idst = cast(rawptr)&nreg.r[dst]
			ibc.imm = sign_extend_2s(instr.imm32)
			if src != dst {
				ibc.isrc = cast(rawptr)&nreg.r[src]
				ibc.mem_mask = u32(instr.mod % 4 != 0 ? L1_MASK : L2_MASK)
			} else {
				ibc.isrc = cast(rawptr)&zero_reg
				ibc.mem_mask = L3_MASK
			}
			register_usage[dst] = i32(i)
			continue
		}

		if opcode < ceil_IMULH_R {
			dst := u32(instr.dst) % 8
			src := u32(instr.src) % 8
			ibc.op = .IMULH_R
			ibc.idst = cast(rawptr)&nreg.r[dst]
			ibc.isrc = cast(rawptr)&nreg.r[src]
			register_usage[dst] = i32(i)
			continue
		}

		if opcode < ceil_IMULH_M {
			dst := u32(instr.dst) % 8
			src := u32(instr.src) % 8
			ibc.op = .IMULH_M
			ibc.idst = cast(rawptr)&nreg.r[dst]
			ibc.imm = sign_extend_2s(instr.imm32)
			if src != dst {
				ibc.isrc = cast(rawptr)&nreg.r[src]
				ibc.mem_mask = u32(instr.mod % 4 != 0 ? L1_MASK : L2_MASK)
			} else {
				ibc.isrc = cast(rawptr)&zero_reg
				ibc.mem_mask = L3_MASK
			}
			register_usage[dst] = i32(i)
			continue
		}

		if opcode < ceil_ISMULH_R {
			dst := u32(instr.dst) % 8
			src := u32(instr.src) % 8
			ibc.op = .ISMULH_R
			ibc.idst = cast(rawptr)&nreg.r[dst]
			ibc.isrc = cast(rawptr)&nreg.r[src]
			register_usage[dst] = i32(i)
			continue
		}

		if opcode < ceil_ISMULH_M {
			dst := u32(instr.dst) % 8
			src := u32(instr.src) % 8
			ibc.op = .ISMULH_M
			ibc.idst = cast(rawptr)&nreg.r[dst]
			ibc.imm = sign_extend_2s(instr.imm32)
			if src != dst {
				ibc.isrc = cast(rawptr)&nreg.r[src]
				ibc.mem_mask = u32(instr.mod % 4 != 0 ? L1_MASK : L2_MASK)
			} else {
				ibc.isrc = cast(rawptr)&zero_reg
				ibc.mem_mask = L3_MASK
			}
			register_usage[dst] = i32(i)
			continue
		}

		if opcode < ceil_IMUL_RCP {
			divisor := instr.imm32
			if divisor != 0 && (divisor & (divisor - 1)) != 0 {
				dst := u32(instr.dst) % 8
				ibc.op = .IMUL_R
				ibc.idst = cast(rawptr)&nreg.r[dst]
				ibc.imm = randomx_reciprocal(divisor)
				ibc.isrc = cast(rawptr)&ibc.imm
				register_usage[dst] = i32(i)
			} else {
				ibc.op = .NOP
			}
			continue
		}

		if opcode < ceil_INEG_R {
			dst := u32(instr.dst) % 8
			ibc.op = .INEG_R
			ibc.idst = cast(rawptr)&nreg.r[dst]
			register_usage[dst] = i32(i)
			continue
		}

		if opcode < ceil_IXOR_R {
			dst := u32(instr.dst) % 8
			src := u32(instr.src) % 8
			ibc.op = .IXOR_R
			ibc.idst = cast(rawptr)&nreg.r[dst]
			if src != dst {
				ibc.isrc = cast(rawptr)&nreg.r[src]
			} else {
				ibc.imm = sign_extend_2s(instr.imm32)
				ibc.isrc = cast(rawptr)&ibc.imm
			}
			register_usage[dst] = i32(i)
			continue
		}

		if opcode < ceil_IXOR_M {
			dst := u32(instr.dst) % 8
			src := u32(instr.src) % 8
			ibc.op = .IXOR_M
			ibc.idst = cast(rawptr)&nreg.r[dst]
			ibc.imm = sign_extend_2s(instr.imm32)
			if src != dst {
				ibc.isrc = cast(rawptr)&nreg.r[src]
				ibc.mem_mask = u32(instr.mod % 4 != 0 ? L1_MASK : L2_MASK)
			} else {
				ibc.isrc = cast(rawptr)&zero_reg
				ibc.mem_mask = L3_MASK
			}
			register_usage[dst] = i32(i)
			continue
		}

		if opcode < ceil_IROR_R {
			dst := u32(instr.dst) % 8
			src := u32(instr.src) % 8
			ibc.op = .IROR_R
			ibc.idst = cast(rawptr)&nreg.r[dst]
			if src != dst {
				ibc.isrc = cast(rawptr)&nreg.r[src]
			} else {
				ibc.imm = u64(instr.imm32)
				ibc.isrc = cast(rawptr)&ibc.imm
			}
			register_usage[dst] = i32(i)
			continue
		}

		if opcode < ceil_IROL_R {
			dst := u32(instr.dst) % 8
			src := u32(instr.src) % 8
			ibc.op = .IROL_R
			ibc.idst = cast(rawptr)&nreg.r[dst]
			if src != dst {
				ibc.isrc = cast(rawptr)&nreg.r[src]
			} else {
				ibc.imm = u64(instr.imm32)
				ibc.isrc = cast(rawptr)&ibc.imm
			}
			register_usage[dst] = i32(i)
			continue
		}

		if opcode < ceil_ISWAP_R {
			dst := u32(instr.dst) % 8
			src := u32(instr.src) % 8
			if src != dst {
				ibc.op = .ISWAP_R
				ibc.idst = cast(rawptr)&nreg.r[dst]
				ibc.isrc = cast(rawptr)&nreg.r[src]
				register_usage[dst] = i32(i)
				register_usage[src] = i32(i)
			} else {
				ibc.op = .NOP
			}
			continue
		}

		if opcode < ceil_FSWAP_R {
			dst := u32(instr.dst) % 8
			ibc.op = .FSWAP_R
			if dst < 4 {
				ibc.idst = cast(rawptr)&nreg.f[dst]
			} else {
				ibc.idst = cast(rawptr)&nreg.e[dst - 4]
			}
			continue
		}

		if opcode < ceil_FADD_R {
			dst := u32(instr.dst) % 4
			src := u32(instr.src) % 4
			ibc.op = .FADD_R
			ibc.idst = cast(rawptr)&nreg.f[dst]
			ibc.isrc = cast(rawptr)&nreg.a[src]
			continue
		}

		if opcode < ceil_FADD_M {
			dst := u32(instr.dst) % 4
			src := u32(instr.src) % 8
			ibc.op = .FADD_M
			ibc.idst = cast(rawptr)&nreg.f[dst]
			ibc.isrc = cast(rawptr)&nreg.r[src]
			ibc.mem_mask = u32(instr.mod % 4 != 0 ? L1_MASK : L2_MASK)
			ibc.imm = sign_extend_2s(instr.imm32)
			continue
		}

		if opcode < ceil_FSUB_R {
			dst := u32(instr.dst) % 4
			src := u32(instr.src) % 4
			ibc.op = .FSUB_R
			ibc.idst = cast(rawptr)&nreg.f[dst]
			ibc.isrc = cast(rawptr)&nreg.a[src]
			continue
		}

		if opcode < ceil_FSUB_M {
			dst := u32(instr.dst) % 4
			src := u32(instr.src) % 8
			ibc.op = .FSUB_M
			ibc.idst = cast(rawptr)&nreg.f[dst]
			ibc.isrc = cast(rawptr)&nreg.r[src]
			ibc.mem_mask = u32(instr.mod % 4 != 0 ? L1_MASK : L2_MASK)
			ibc.imm = sign_extend_2s(instr.imm32)
			continue
		}

		if opcode < ceil_FSCAL_R {
			dst := u32(instr.dst) % 4
			ibc.op = .FSCAL_R
			ibc.idst = cast(rawptr)&nreg.f[dst]
			continue
		}

		if opcode < ceil_FMUL_R {
			dst := u32(instr.dst) % 4
			src := u32(instr.src) % 4
			ibc.op = .FMUL_R
			ibc.idst = cast(rawptr)&nreg.e[dst]
			ibc.isrc = cast(rawptr)&nreg.a[src]
			continue
		}

		if opcode < ceil_FDIV_M {
			dst := u32(instr.dst) % 4
			src := u32(instr.src) % 8
			ibc.op = .FDIV_M
			ibc.idst = cast(rawptr)&nreg.e[dst]
			ibc.isrc = cast(rawptr)&nreg.r[src]
			ibc.mem_mask = u32(instr.mod % 4 != 0 ? L1_MASK : L2_MASK)
			ibc.imm = sign_extend_2s(instr.imm32)
			continue
		}

		if opcode < ceil_FSQRT_R {
			dst := u32(instr.dst) % 4
			ibc.op = .FSQRT_R
			ibc.idst = cast(rawptr)&nreg.e[dst]
			continue
		}

		if opcode < ceil_CBRANCH {
			ibc.op = .CBRANCH
			creg := u32(instr.dst) % 8
			ibc.idst = cast(rawptr)&nreg.r[creg]
			ibc.target = i16(register_usage[creg])
			shift := u32(instr.mod >> 4) + CONDITION_OFFSET
			ibc.imm = sign_extend_2s(instr.imm32) | (u64(1) << shift)
			if shift > 0 {
				ibc.imm &= ~(u64(1) << (shift - 1))
			}
			ibc.mem_mask = u32(CONDITION_MASK) << shift
			for j in 0 ..< 8 {
				register_usage[j] = i32(i)
			}
			continue
		}

		if opcode < ceil_CFROUND {
			src := u32(instr.src) % 8
			ibc.isrc = cast(rawptr)&nreg.r[src]
			ibc.op = .CFROUND
			ibc.imm = u64(instr.imm32 & 63)
			continue
		}

		if u16(opcode) < ceil_ISTORE {
			dst := u32(instr.dst) % 8
			src := u32(instr.src) % 8
			ibc.op = .ISTORE
			ibc.idst = cast(rawptr)&nreg.r[dst]
			ibc.isrc = cast(rawptr)&nreg.r[src]
			ibc.imm = sign_extend_2s(instr.imm32)
			if u32(instr.mod >> 4) < STORE_L3_CONDITION {
				ibc.mem_mask = u32(instr.mod % 4 != 0 ? L1_MASK : L2_MASK)
			} else {
				ibc.mem_mask = L3_MASK
			}
			continue
		}

		ibc.op = .NOP
	}
}

// ===== Memory helpers =====
load32 :: proc(buf: []u8, off: int) -> u32 {
	return (^u32)(uintptr(raw_data(buf)) + uintptr(off))^
}

load64 :: proc(buf: []u8, off: int) -> u64 {
	return (^u64)(uintptr(raw_data(buf)) + uintptr(off))^
}

store64 :: proc(buf: []u8, off: int, v: u64) {
	(^u64)(uintptr(raw_data(buf)) + uintptr(off))^ = v
}

load_vec_bytes :: proc(buf: []u8, off: int) -> Vec {
	return (^Vec)(uintptr(raw_data(buf)) + uintptr(off))^
}

store_vec_bytes :: proc(buf: []u8, off: int, v: Vec) {
	(^Vec)(uintptr(raw_data(buf)) + uintptr(off))^ = v
}

// ===== VM state =====
VM :: struct {
	reg:           RegisterFile,
	program:       Program,
	mem:           MemoryRegisters,
	config:        ProgramConfiguration,
	dataset_offset: u64,
	scratchpad:    []u8,
	dataset:       []u8,
}

// ===== FP helpers =====
cvt_load :: proc(buf: []u8, off: int) -> Vec {
	lo := cast(i32)load32(buf, off)
	hi := cast(i32)load32(buf, off + 4)
	return odin_cvt(lo, hi)
}

mask_register_exponent_mantissa :: proc(config: ProgramConfiguration, x0: Vec) -> Vec {
	m := odin_set_vec(DYNAMIC_MANTISSA_MASK, DYNAMIC_MANTISSA_MASK)
	x := odin_and(x0, m)
	e := odin_set_vec(config.e_mask[1], config.e_mask[0])
	return odin_or(x, e)
}

vm_rotr :: proc(x: u64, n: u32) -> u64 {
	c := n & 63
	if c == 0 do return x
	return (x >> c) | (x << (64 - c))
}

// ===== Bytecode execution =====
get_mem_addr :: proc(ibc: ^InstructionByteCode) -> int {
	src := (^u64)(ibc.isrc)^
	return int(u32((src + ibc.imm) & u64(ibc.mem_mask)))
}

execute_bytecode :: proc(bytecode: []InstructionByteCode, scratchpad: []u8, config: ProgramConfiguration) {
	pc := 0
	n := len(bytecode)
	for pc < n {
		ibc := &bytecode[pc]
		switch ibc.op {
		case .IADD_RS:
			src := (^u64)(ibc.isrc)^
			(^u64)(ibc.idst)^ = (^u64)(ibc.idst)^ + (src << ibc.shift) + ibc.imm
		case .IADD_M:
			addr := get_mem_addr(ibc)
			(^u64)(ibc.idst)^ = (^u64)(ibc.idst)^ + load64(scratchpad, addr)
		case .ISUB_R:
			(^u64)(ibc.idst)^ = (^u64)(ibc.idst)^ - (^u64)(ibc.isrc)^
		case .ISUB_M:
			addr := get_mem_addr(ibc)
			(^u64)(ibc.idst)^ = (^u64)(ibc.idst)^ - load64(scratchpad, addr)
		case .IMUL_R:
			(^u64)(ibc.idst)^ = (^u64)(ibc.idst)^ * (^u64)(ibc.isrc)^
		case .IMUL_M:
			addr := get_mem_addr(ibc)
			(^u64)(ibc.idst)^ = (^u64)(ibc.idst)^ * load64(scratchpad, addr)
		case .IMULH_R:
			(^u64)(ibc.idst)^ = mulh((^u64)(ibc.idst)^, (^u64)(ibc.isrc)^)
		case .IMULH_M:
			addr := get_mem_addr(ibc)
			(^u64)(ibc.idst)^ = mulh((^u64)(ibc.idst)^, load64(scratchpad, addr))
		case .ISMULH_R:
			(^u64)(ibc.idst)^ = smulh((^u64)(ibc.idst)^, (^u64)(ibc.isrc)^)
		case .ISMULH_M:
			addr := get_mem_addr(ibc)
			(^u64)(ibc.idst)^ = smulh((^u64)(ibc.idst)^, load64(scratchpad, addr))
		case .INEG_R:
			(^u64)(ibc.idst)^ = ~((^u64)(ibc.idst)^) + 1
		case .IXOR_R:
			(^u64)(ibc.idst)^ = (^u64)(ibc.idst)^ ~ (^u64)(ibc.isrc)^
		case .IXOR_M:
			addr := get_mem_addr(ibc)
			(^u64)(ibc.idst)^ = (^u64)(ibc.idst)^ ~ load64(scratchpad, addr)
		case .IROR_R:
			(^u64)(ibc.idst)^ = vm_rotr((^u64)(ibc.idst)^, u32((^u64)(ibc.isrc)^ & 63))
		case .IROL_R:
			(^u64)(ibc.idst)^ = rotl64((^u64)(ibc.idst)^, u32((^u64)(ibc.isrc)^ & 63))
		case .ISWAP_R:
			tmp := (^u64)(ibc.isrc)^
			(^u64)(ibc.isrc)^ = (^u64)(ibc.idst)^
			(^u64)(ibc.idst)^ = tmp
		case .FSWAP_R:
			(^Vec)(ibc.idst)^ = odin_swap((^Vec)(ibc.idst)^)
		case .FADD_R:
			(^Vec)(ibc.idst)^ = odin_add((^Vec)(ibc.idst)^, (^Vec)(ibc.isrc)^)
		case .FADD_M:
			addr := get_mem_addr(ibc)
			fsrc := cvt_load(scratchpad, addr)
			(^Vec)(ibc.idst)^ = odin_add((^Vec)(ibc.idst)^, fsrc)
		case .FSUB_R:
			(^Vec)(ibc.idst)^ = odin_sub((^Vec)(ibc.idst)^, (^Vec)(ibc.isrc)^)
		case .FSUB_M:
			addr := get_mem_addr(ibc)
			fsrc := cvt_load(scratchpad, addr)
			(^Vec)(ibc.idst)^ = odin_sub((^Vec)(ibc.idst)^, fsrc)
		case .FSCAL_R:
			(^Vec)(ibc.idst)^ = odin_xor((^Vec)(ibc.idst)^, odin_set1(0x80F0000000000000))
		case .FMUL_R:
			(^Vec)(ibc.idst)^ = odin_mul((^Vec)(ibc.idst)^, (^Vec)(ibc.isrc)^)
		case .FDIV_M:
			addr := get_mem_addr(ibc)
			fsrc := mask_register_exponent_mantissa(config, cvt_load(scratchpad, addr))
			(^Vec)(ibc.idst)^ = odin_div((^Vec)(ibc.idst)^, fsrc)
		case .FSQRT_R:
			(^Vec)(ibc.idst)^ = odin_sqrt((^Vec)(ibc.idst)^)
		case .CBRANCH:
			val := (^u64)(ibc.idst)^ + ibc.imm
			(^u64)(ibc.idst)^ = val
			if (val & u64(ibc.mem_mask)) == 0 {
				pc = int(ibc.target)
			}
		case .CFROUND:
			val := vm_rotr((^u64)(ibc.isrc)^, u32(ibc.imm))
			odin_set_mxcsr(0x9FC0 | u32(val % 4) << 13)
		case .ISTORE:
			dst := (^u64)(ibc.idst)^
			addr := int(u32((dst + ibc.imm) & u64(ibc.mem_mask)))
			store64(scratchpad, addr, (^u64)(ibc.isrc)^)
		case .IMUL_RCP: // never emitted by compile_program (converted to IMUL_R or NOP)
			// unreachable
		case .NOP:
			// nothing
		case:
			// unreachable
		}
		pc += 1
	}
}

// ===== execute =====
execute :: proc(vm: ^VM) {
	nreg: NRegFile
	for i in 0 ..< 4 do nreg.a[i] = vm.reg.a[i]

	bytecode: [256]InstructionByteCode
	compile_program(&vm.program, bytecode[:], &nreg)

	sp_addr0 := vm.mem.mx
	sp_addr1 := vm.mem.ma

	for ic in 0 ..< PROGRAM_ITERATIONS {
		sp_mix := nreg.r[vm.config.read_reg0] ~ nreg.r[vm.config.read_reg1]
		sp_addr0 = u32(u64(sp_addr0) ~ sp_mix)
		sp_addr0 &= u32(L3_MASK64)
		sp_addr1 = u32(u64(sp_addr1) ~ (sp_mix >> 32))
		sp_addr1 &= u32(L3_MASK64)

		for i in 0 ..< 8 {
			nreg.r[i] ~= load64(vm.scratchpad, int(sp_addr0) + 8 * i)
		}
		for i in 0 ..< 4 {
			nreg.f[i] = cvt_load(vm.scratchpad, int(sp_addr1) + 8 * i)
		}
		for i in 0 ..< 4 {
			nreg.e[i] = mask_register_exponent_mantissa(vm.config, cvt_load(vm.scratchpad, int(sp_addr1) + 8 * (4 + i)))
		}

		execute_bytecode(bytecode[:], vm.scratchpad, vm.config)

		read_ptr := vm.dataset_offset + u64(vm.mem.ma & u32(CACHE_LINE_ALIGN_MASK))
		vm.mem.mx ~= u32(nreg.r[vm.config.read_reg2] ~ nreg.r[vm.config.read_reg3])
		// datasetPrefetch (no-op)

		dline := ([^]u64)(uintptr(raw_data(vm.dataset)) + uintptr(read_ptr))
		for i in 0 ..< 8 {
			nreg.r[i] ~= dline[i]
		}

		tmp := vm.mem.mx
		vm.mem.mx = vm.mem.ma
		vm.mem.ma = tmp

		for i in 0 ..< 8 {
			store64(vm.scratchpad, int(sp_addr1) + 8 * i, nreg.r[i])
		}
		// V1: f ^= e
		for i in 0 ..< 4 {
			nreg.f[i] = odin_xor(nreg.f[i], nreg.e[i])
		}
		for i in 0 ..< 4 {
			store_vec_bytes(vm.scratchpad, int(sp_addr0) + 16 * i, nreg.f[i])
		}

		sp_addr0 = 0
		sp_addr1 = 0
	}

	for i in 0 ..< 8 do vm.reg.r[i] = nreg.r[i]
	for i in 0 ..< 4 do vm.reg.f[i] = nreg.f[i]
	for i in 0 ..< 4 do vm.reg.e[i] = nreg.e[i]
}

// ===== initialize =====
initialize :: proc(vm: ^VM) {
	for i in 0 ..< 4 {
		lo := get_small_positive_float_bits(vm.program.entropy[2 * i])
		hi := get_small_positive_float_bits(vm.program.entropy[2 * i + 1])
		vm.reg.a[i] = odin_set_vec(hi, lo)
	}
	vm.mem.ma = u32(vm.program.entropy[8] & u64(CACHE_LINE_ALIGN_MASK))
	vm.mem.mx = u32(vm.program.entropy[10])
	addr_reg := vm.program.entropy[12]
	vm.config.read_reg0 = u32(0 + (addr_reg & 1))
	addr_reg >>= 1
	vm.config.read_reg1 = u32(2 + (addr_reg & 1))
	addr_reg >>= 1
	vm.config.read_reg2 = u32(4 + (addr_reg & 1))
	addr_reg >>= 1
	vm.config.read_reg3 = u32(6 + (addr_reg & 1))
	vm.dataset_offset = (vm.program.entropy[13] % (u64(DATASET_EXTRA_ITEMS) + 1)) * u64(CACHE_LINE_SIZE)
	vm.config.e_mask[0] = get_float_mask(vm.program.entropy[14])
	vm.config.e_mask[1] = get_float_mask(vm.program.entropy[15])
}

// ===== generate_program =====
generate_program :: proc(vm: ^VM, seed: []u8) {
	program_bytes := ([^]u8)(uintptr(cast(rawptr)&vm.program))[:size_of(Program)]
	aes.fillAes4Rx4(seed, size_of(Program), program_bytes)
}

// ===== run =====
run :: proc(vm: ^VM, seed: []u8) {
	generate_program(vm, seed)
	initialize(vm)
	execute(vm)
}

// ===== get_final_result =====
get_final_result :: proc(vm: ^VM, out: []u8) {
	reg_a_bytes := ([^]u8)(uintptr(cast(rawptr)&vm.reg.a))[:64]
	aes.hashAes1Rx4(vm.scratchpad, SCRATCHPAD_SIZE, reg_a_bytes)
	reg_bytes := ([^]u8)(uintptr(cast(rawptr)&vm.reg))[:size_of(RegisterFile)]
	blake2b(out, 32, reg_bytes, nil)
}

// ===== hash main =====
hash_main :: proc(vm: ^VM, input: []u8, output: []u8) {
	temp_hash: [8]u64
	temp_bytes := ([^]u8)(uintptr(cast(rawptr)&temp_hash))[:64]
	blake2b(temp_bytes, 64, input, nil)
	aes.fillAes1Rx4(temp_bytes, SCRATCHPAD_SIZE, vm.scratchpad)
	odin_set_mxcsr(0x9FC0)
	reg_bytes := ([^]u8)(uintptr(cast(rawptr)&vm.reg))[:size_of(RegisterFile)]
	for chain in 0 ..< PROGRAM_COUNT - 1 {
		run(vm, temp_bytes)
		blake2b(temp_bytes, 64, reg_bytes, nil)
	}
	run(vm, temp_bytes)
	get_final_result(vm, output)
}
