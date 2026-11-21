package frostrig_randomx_odin

// SuperscalarInstructionType — from randomx/src/superscalar.hpp
SuperscalarInstructionType :: enum int {
	ISUB_R   = 0,
	IXOR_R   = 1,
	IADD_RS  = 2,
	IMUL_R   = 3,
	IROR_C   = 4,
	IADD_C7  = 5,
	IXOR_C7  = 6,
	IADD_C8  = 7,
	IXOR_C8  = 8,
	IADD_C9  = 9,
	IXOR_C9  = 10,
	IMULH_R  = 11,
	ISMULH_R = 12,
	IMUL_RCP = 13,
	NOP      = 14,
	INVALID  = 15,
}

// Instruction — from randomx/src/instruction.hpp
// NOTE: field order must match C++ exactly (opcode,dst,src,mod,imm32 = 8 bytes)
// because the VM Program is filled by fillAes4Rx4 and interpreted as raw bytes.
Instruction :: struct {
	opcode: u8,
	dst:    u8,
	src:    u8,
	mod:    u8,
	imm32:  u32,
}

get_mod_mem :: proc(i: Instruction) -> u8 {
	return i.mod % 4
}

get_mod_shift :: proc(i: Instruction) -> u8 {
	return (i.mod >> 2) % 4
}

get_mod_cond :: proc(i: Instruction) -> u8 {
	return i.mod >> 4
}

get_imm32 :: proc(i: Instruction) -> u32 {
	return i.imm32
}

// constants
RANDOMX_SUPERSCALAR_LATENCY :: 170
SuperscalarMaxSize :: 3 * RANDOMX_SUPERSCALAR_LATENCY + 2
RegisterNeedsDisplacement :: 5
CYCLE_MAP_SIZE :: RANDOMX_SUPERSCALAR_LATENCY + 4
LOOK_FORWARD_CYCLES :: 4
MAX_THROWAWAY_COUNT :: 256

ExecutionPort :: enum int {
	Null = 0,
	P0   = 1,
	P1   = 2,
	P5   = 4,
	P01  = 3,
	P05  = 5,
	P015 = 7,
}

MacroOp :: struct {
	name:      string,
	size:      int,
	latency:   int,
	uop1:      ExecutionPort,
	uop2:      ExecutionPort,
	dependent: bool,
}

macro_op_is_simple :: proc(m: MacroOp) -> bool {
	return m.uop2 == .Null
}

macro_op_is_eliminated :: proc(m: MacroOp) -> bool {
	return m.uop1 == .Null
}

@(init)
_macro_ops_init :: proc "contextless" () {
	macro_op_add_rr = MacroOp{name = "add r,r", size = 3, latency = 1, uop1 = .P015, uop2 = .Null}
	macro_op_sub_rr = MacroOp{name = "sub r,r", size = 3, latency = 1, uop1 = .P015, uop2 = .Null}
	macro_op_xor_rr = MacroOp{name = "xor r,r", size = 3, latency = 1, uop1 = .P015, uop2 = .Null}
	macro_op_imul_r = MacroOp{name = "imul r", size = 3, latency = 4, uop1 = .P1, uop2 = .P5}
	macro_op_mul_r  = MacroOp{name = "mul r", size = 3, latency = 4, uop1 = .P1, uop2 = .P5}
	macro_op_mov_rr = MacroOp{name = "mov r,r", size = 3, latency = 0, uop1 = .Null, uop2 = .Null}
	macro_op_lea_sib = MacroOp{name = "lea r,r+r*s", size = 4, latency = 1, uop1 = .P01, uop2 = .Null}
	macro_op_imul_rr = MacroOp{name = "imul r,r", size = 4, latency = 3, uop1 = .P1, uop2 = .Null}
	macro_op_ror_ri = MacroOp{name = "ror r,i", size = 4, latency = 1, uop1 = .P05, uop2 = .Null}
	macro_op_add_ri = MacroOp{name = "add r,i", size = 7, latency = 1, uop1 = .P015, uop2 = .Null}
	macro_op_xor_ri = MacroOp{name = "xor r,i", size = 7, latency = 1, uop1 = .P015, uop2 = .Null}
	macro_op_mov_ri64 = MacroOp{name = "mov rax,i64", size = 10, latency = 1, uop1 = .P015, uop2 = .Null}

	macro_op_imulh_ops[0] = macro_op_mov_rr
	macro_op_imulh_ops[1] = macro_op_mul_r
	macro_op_imulh_ops[2] = macro_op_mov_rr

	macro_op_ismulh_ops[0] = macro_op_mov_rr
	macro_op_ismulh_ops[1] = macro_op_imul_r
	macro_op_ismulh_ops[2] = macro_op_mov_rr

	macro_op_imulrcp_ops[0] = macro_op_mov_ri64
	macro_op_imulrcp_ops[1] = MacroOp{name = "imul r,r", size = 4, latency = 3, uop1 = .P1, uop2 = .Null, dependent = true}
}

macro_op_add_rr:    MacroOp
macro_op_sub_rr:    MacroOp
macro_op_xor_rr:    MacroOp
macro_op_imul_r:    MacroOp
macro_op_mul_r:     MacroOp
macro_op_mov_rr:    MacroOp
macro_op_lea_sib:   MacroOp
macro_op_imul_rr:   MacroOp
macro_op_ror_ri:    MacroOp
macro_op_add_ri:    MacroOp
macro_op_xor_ri:    MacroOp
macro_op_mov_ri64:  MacroOp
macro_op_imulh_ops:  [3]MacroOp
macro_op_ismulh_ops: [3]MacroOp
macro_op_imulrcp_ops: [2]MacroOp

SIInfo :: struct {
	name:      string,
	type:      SuperscalarInstructionType,
	ops:       [3]MacroOp,
	op_count:  int,
	latency:   int,
	result_op: int,
	dst_op:    int,
	src_op:    int,
}

si_info_is_simple :: proc(inf: ^SIInfo) -> bool {
	return inf.op_count == 1
}

@(init)
_si_info_init :: proc "contextless" () {
	si_isub_r = SIInfo{name = "ISUB_R", type = .ISUB_R, ops = {macro_op_sub_rr, {}, {}}, op_count = 1, latency = 1, result_op = 0, dst_op = 0, src_op = 0}
	si_ixor_r = SIInfo{name = "IXOR_R", type = .IXOR_R, ops = {macro_op_xor_rr, {}, {}}, op_count = 1, latency = 1, result_op = 0, dst_op = 0, src_op = 0}
	si_iadd_rs = SIInfo{name = "IADD_RS", type = .IADD_RS, ops = {macro_op_lea_sib, {}, {}}, op_count = 1, latency = 1, result_op = 0, dst_op = 0, src_op = 0}
	si_imul_r = SIInfo{name = "IMUL_R", type = .IMUL_R, ops = {macro_op_imul_rr, {}, {}}, op_count = 1, latency = 3, result_op = 0, dst_op = 0, src_op = 0}
	si_iror_c = SIInfo{name = "IROR_C", type = .IROR_C, ops = {macro_op_ror_ri, {}, {}}, op_count = 1, latency = 1, result_op = 0, dst_op = 0, src_op = -1}
	si_iadd_c7 = SIInfo{name = "IADD_C7", type = .IADD_C7, ops = {macro_op_add_ri, {}, {}}, op_count = 1, latency = 1, result_op = 0, dst_op = 0, src_op = -1}
	si_ixor_c7 = SIInfo{name = "IXOR_C7", type = .IXOR_C7, ops = {macro_op_xor_ri, {}, {}}, op_count = 1, latency = 1, result_op = 0, dst_op = 0, src_op = -1}
	si_iadd_c8 = SIInfo{name = "IADD_C8", type = .IADD_C8, ops = {macro_op_add_ri, {}, {}}, op_count = 1, latency = 1, result_op = 0, dst_op = 0, src_op = -1}
	si_ixor_c8 = SIInfo{name = "IXOR_C8", type = .IXOR_C8, ops = {macro_op_xor_ri, {}, {}}, op_count = 1, latency = 1, result_op = 0, dst_op = 0, src_op = -1}
	si_iadd_c9 = SIInfo{name = "IADD_C9", type = .IADD_C9, ops = {macro_op_add_ri, {}, {}}, op_count = 1, latency = 1, result_op = 0, dst_op = 0, src_op = -1}
	si_ixor_c9 = SIInfo{name = "IXOR_C9", type = .IXOR_C9, ops = {macro_op_xor_ri, {}, {}}, op_count = 1, latency = 1, result_op = 0, dst_op = 0, src_op = -1}

	lat := 0
	for i in 0 ..< 3 do lat += macro_op_imulh_ops[i].latency
	si_imulh_r = SIInfo{name = "IMULH_R", type = .IMULH_R, ops = macro_op_imulh_ops, op_count = 3, latency = lat, result_op = 1, dst_op = 0, src_op = 1}

	lat = 0
	for i in 0 ..< 3 do lat += macro_op_ismulh_ops[i].latency
	si_ismulh_r = SIInfo{name = "ISMULH_R", type = .ISMULH_R, ops = macro_op_ismulh_ops, op_count = 3, latency = lat, result_op = 1, dst_op = 0, src_op = 1}

	lat = 0
	for i in 0 ..< 2 do lat += macro_op_imulrcp_ops[i].latency
	si_imul_rcp = SIInfo{name = "IMUL_RCP", type = .IMUL_RCP, ops = {macro_op_imulrcp_ops[0], macro_op_imulrcp_ops[1], {}}, op_count = 2, latency = lat, result_op = 1, dst_op = 1, src_op = -1}

	si_nop = SIInfo{name = "NOP", type = .NOP, op_count = 0, latency = 0, result_op = 0, dst_op = 0, src_op = -1}
}

si_isub_r:   SIInfo
si_ixor_r:   SIInfo
si_iadd_rs:  SIInfo
si_imul_r:   SIInfo
si_iror_c:   SIInfo
si_iadd_c7:  SIInfo
si_ixor_c7:  SIInfo
si_iadd_c8:  SIInfo
si_ixor_c8:  SIInfo
si_iadd_c9:  SIInfo
si_ixor_c9:  SIInfo
si_imulh_r:  SIInfo
si_ismulh_r: SIInfo
si_imul_rcp: SIInfo
si_nop:      SIInfo

@(init)
_slots_init :: proc "contextless" () {
	slot_3[0] = &si_isub_r
	slot_3[1] = &si_ixor_r
	slot_3l[0] = &si_isub_r
	slot_3l[1] = &si_ixor_r
	slot_3l[2] = &si_imulh_r
	slot_3l[3] = &si_ismulh_r
	slot_4[0] = &si_iror_c
	slot_4[1] = &si_iadd_rs
	slot_7[0] = &si_ixor_c7
	slot_7[1] = &si_iadd_c7
	slot_8[0] = &si_ixor_c8
	slot_8[1] = &si_iadd_c8
	slot_9[0] = &si_ixor_c9
	slot_9[1] = &si_iadd_c9
	slot_10 = &si_imul_rcp
}

slot_3:  [2]^SIInfo
slot_3l: [4]^SIInfo
slot_4:  [2]^SIInfo
slot_7:  [2]^SIInfo
slot_8:  [2]^SIInfo
slot_9:  [2]^SIInfo
slot_10: ^SIInfo

DecoderBuffer :: struct {
	name:   string,
	index:  int,
	counts: [4]int,
	size:   int,
}

@(init)
_decode_buffers_init :: proc "contextless" () {
	decode_buffer_484 = DecoderBuffer{name = "4,8,4", index = 0, counts = {4, 8, 4, 0}, size = 3}
	decode_buffer_7333 = DecoderBuffer{name = "7,3,3,3", index = 1, counts = {7, 3, 3, 3}, size = 4}
	decode_buffer_3733 = DecoderBuffer{name = "3,7,3,3", index = 2, counts = {3, 7, 3, 3}, size = 4}
	decode_buffer_493 = DecoderBuffer{name = "4,9,3", index = 3, counts = {4, 9, 3, 0}, size = 3}
	decode_buffer_4444 = DecoderBuffer{name = "4,4,4,4", index = 4, counts = {4, 4, 4, 4}, size = 4}
	decode_buffer_3310 = DecoderBuffer{name = "3,3,10", index = 5, counts = {3, 3, 10, 0}, size = 3}
	decode_buffer_default = DecoderBuffer{name = "default", index = -1, counts = {0, 0, 0, 0}, size = 0}

	decode_buffers[0] = &decode_buffer_484
	decode_buffers[1] = &decode_buffer_7333
	decode_buffers[2] = &decode_buffer_3733
	decode_buffers[3] = &decode_buffer_493
}

decode_buffer_484:     DecoderBuffer
decode_buffer_7333:    DecoderBuffer
decode_buffer_3733:    DecoderBuffer
decode_buffer_493:     DecoderBuffer
decode_buffer_4444:    DecoderBuffer
decode_buffer_3310:    DecoderBuffer
decode_buffer_default: DecoderBuffer
decode_buffers:        [4]^DecoderBuffer

fetch_next :: proc(db: ^DecoderBuffer, gen: ^Blake2Generator, instr_type: SuperscalarInstructionType, cycle: int, mul_count: int) -> ^DecoderBuffer {
	if instr_type == .IMULH_R || instr_type == .ISMULH_R {
		return &decode_buffer_3310
	}
	if mul_count < cycle + 1 {
		return &decode_buffer_4444
	}
	if instr_type == .IMUL_RCP {
		if (get_byte(gen) & 1) != 0 {
			return &decode_buffer_484
		}
		return &decode_buffer_493
	}
	return decode_buffers[get_byte(gen) & 3]
}

select_register :: proc(available: []int, gen: ^Blake2Generator, reg: ^int) -> bool {
	if len(available) == 0 {
		return false
	}
	index: int
	if len(available) > 1 {
		index = int(get_u32(gen) % u32(len(available)))
	} else {
		index = 0
	}
	reg^ = available[index]
	return true
}

RegisterInfo :: struct {
	latency:       int,
	last_op_group: SuperscalarInstructionType,
	last_op_par:   int,
	value:         int,
}

SSInstruction :: struct {
	info:                 ^SIInfo,
	src_:                 int,
	dst_:                 int,
	mod_:                 int,
	imm32_:               u32,
	op_group_:            SuperscalarInstructionType,
	op_group_par_:        int,
	can_reuse_:           bool,
	group_par_is_source_: bool,
}

ss_null_instruction :: proc() -> SSInstruction {
	return SSInstruction{info = &si_nop, src_ = -1, dst_ = -1, mod_ = 0, imm32_ = 0, op_group_ = .INVALID, op_group_par_ = -1, can_reuse_ = false, group_par_is_source_ = false}
}

ss_get_info :: proc(ss: ^SSInstruction) -> ^SIInfo {
	return ss.info
}

ss_get_type :: proc(ss: ^SSInstruction) -> SuperscalarInstructionType {
	return ss.info.type
}

ss_get_source :: proc(ss: ^SSInstruction) -> int {
	return ss.src_
}

ss_get_destination :: proc(ss: ^SSInstruction) -> int {
	return ss.dst_
}

ss_get_group :: proc(ss: ^SSInstruction) -> SuperscalarInstructionType {
	return ss.op_group_
}

ss_get_group_par :: proc(ss: ^SSInstruction) -> int {
	return ss.op_group_par_
}

ss_reset :: proc(ss: ^SSInstruction) {
	ss.src_ = -1
	ss.dst_ = -1
	ss.can_reuse_ = false
	ss.group_par_is_source_ = false
}

ss_to_instr :: proc(ss: ^SSInstruction, instr: ^Instruction) {
	instr.opcode = u8(int(ss_get_type(ss)))
	instr.dst = u8(ss.dst_)
	if ss.src_ >= 0 {
		instr.src = u8(ss.src_)
	} else {
		instr.src = u8(ss.dst_)
	}
	instr.mod = u8(ss.mod_)
	instr.imm32 = ss.imm32_
}

ss_create_for_slot :: proc(ss: ^SSInstruction, gen: ^Blake2Generator, slot_size: int, fetch_type: int, is_last: bool, is_first: bool) {
	switch slot_size {
	case 3:
		if is_last {
			ss_create(ss, gen, slot_3l[get_byte(gen) & 3])
		} else {
			ss_create(ss, gen, slot_3[get_byte(gen) & 1])
		}
	case 4:
		if fetch_type == 4 && !is_last {
			ss_create(ss, gen, &si_imul_r)
		} else {
			ss_create(ss, gen, slot_4[get_byte(gen) & 1])
		}
	case 7:
		ss_create(ss, gen, slot_7[get_byte(gen) & 1])
	case 8:
		ss_create(ss, gen, slot_8[get_byte(gen) & 1])
	case 9:
		ss_create(ss, gen, slot_9[get_byte(gen) & 1])
	case 10:
		ss_create(ss, gen, slot_10)
	case:
		panic("unreachable slot size")
	}
}

ss_create :: proc(ss: ^SSInstruction, gen: ^Blake2Generator, info: ^SIInfo) {
	ss.info = info
	ss_reset(ss)
	switch info.type {
	case .ISUB_R:
		ss.mod_ = 0
		ss.imm32_ = 0
		ss.op_group_ = .IADD_RS
		ss.group_par_is_source_ = true
	case .IXOR_R:
		ss.mod_ = 0
		ss.imm32_ = 0
		ss.op_group_ = .IXOR_R
		ss.group_par_is_source_ = true
	case .IADD_RS:
		ss.mod_ = int(get_byte(gen))
		ss.imm32_ = 0
		ss.op_group_ = .IADD_RS
		ss.group_par_is_source_ = true
	case .IMUL_R:
		ss.mod_ = 0
		ss.imm32_ = 0
		ss.op_group_ = .IMUL_R
		ss.group_par_is_source_ = true
	case .IROR_C:
		ss.mod_ = 0
		for {
			ss.imm32_ = u32(get_byte(gen) & 63)
			if ss.imm32_ != 0 {
				break
			}
		}
		ss.op_group_ = .IROR_C
		ss.op_group_par_ = -1
	case .IADD_C7, .IADD_C8, .IADD_C9:
		ss.mod_ = 0
		ss.imm32_ = get_u32(gen)
		ss.op_group_ = .IADD_C7
		ss.op_group_par_ = -1
	case .IXOR_C7, .IXOR_C8, .IXOR_C9:
		ss.mod_ = 0
		ss.imm32_ = get_u32(gen)
		ss.op_group_ = .IXOR_C7
		ss.op_group_par_ = -1
	case .IMULH_R:
		ss.can_reuse_ = true
		ss.mod_ = 0
		ss.imm32_ = 0
		ss.op_group_ = .IMULH_R
		ss.op_group_par_ = int(get_u32(gen))
	case .ISMULH_R:
		ss.can_reuse_ = true
		ss.mod_ = 0
		ss.imm32_ = 0
		ss.op_group_ = .ISMULH_R
		ss.op_group_par_ = int(get_u32(gen))
	case .IMUL_RCP:
		ss.mod_ = 0
		for {
			ss.imm32_ = get_u32(gen)
			if !is_zero_or_power_of_2(u64(ss.imm32_)) {
				break
			}
		}
		ss.op_group_ = .IMUL_RCP
		ss.op_group_par_ = -1
	case .NOP, .INVALID:
		panic("unreachable instruction type")
	}
}

ss_select_destination :: proc(ss: ^SSInstruction, cycle: int, allow_chained_mul: bool, registers: ^[8]RegisterInfo, gen: ^Blake2Generator) -> bool {
	available: [8]int
	n := 0
	for i in 0 ..< 8 {
		r := &registers[i]
		if r.latency <= cycle &&
			(ss.can_reuse_ || i != ss.src_) &&
			(allow_chained_mul || ss.op_group_ != .IMUL_R || r.last_op_group != .IMUL_R) &&
			(r.last_op_group != ss.op_group_ || r.last_op_par != ss.op_group_par_) &&
			(ss.info.type != .IADD_RS || i != RegisterNeedsDisplacement) {
			available[n] = i
			n += 1
		}
	}
	return select_register(available[:n], gen, &ss.dst_)
}

ss_select_source :: proc(ss: ^SSInstruction, cycle: int, registers: ^[8]RegisterInfo, gen: ^Blake2Generator) -> bool {
	available: [8]int
	n := 0
	for i in 0 ..< 8 {
		if registers[i].latency <= cycle {
			available[n] = i
			n += 1
		}
	}
	if n == 2 && ss.info.type == .IADD_RS {
		if available[0] == RegisterNeedsDisplacement || available[1] == RegisterNeedsDisplacement {
			ss.op_group_par_ = RegisterNeedsDisplacement
			ss.src_ = RegisterNeedsDisplacement
			return true
		}
	}
	if select_register(available[:n], gen, &ss.src_) {
		if ss.group_par_is_source_ {
			ss.op_group_par_ = ss.src_
		}
		return true
	}
	return false
}

is_zero_or_power_of_2 :: proc(x: u64) -> bool {
	return (x & (x - 1)) == 0
}

schedule_uop :: proc(uop: ExecutionPort, port_busy: ^[CYCLE_MAP_SIZE][3]int, cycle: int, commit: bool) -> int {
	for c := cycle; c < CYCLE_MAP_SIZE; c += 1 {
		if (int(uop) & int(ExecutionPort.P5)) != 0 && port_busy[c][2] == 0 {
			if commit {
				port_busy[c][2] = int(uop)
			}
			return c
		}
		if (int(uop) & int(ExecutionPort.P0)) != 0 && port_busy[c][0] == 0 {
			if commit {
				port_busy[c][0] = int(uop)
			}
			return c
		}
		if (int(uop) & int(ExecutionPort.P1)) != 0 && port_busy[c][1] == 0 {
			if commit {
				port_busy[c][1] = int(uop)
			}
			return c
		}
	}
	return -1
}

schedule_mop :: proc(mop: MacroOp, port_busy: ^[CYCLE_MAP_SIZE][3]int, cycle: int, dep_cycle: int, commit: bool) -> int {
	cyc := cycle
	if mop.dependent {
		if cyc < dep_cycle {
			cyc = dep_cycle
		}
	}
	if macro_op_is_eliminated(mop) {
		return cyc
	}
	if macro_op_is_simple(mop) {
		return schedule_uop(mop.uop1, port_busy, cyc, commit)
	}
	for c := cyc; c < CYCLE_MAP_SIZE; c += 1 {
		c1 := schedule_uop(mop.uop1, port_busy, c, false)
		c2 := schedule_uop(mop.uop2, port_busy, c, false)
		if c1 >= 0 && c1 == c2 {
			if commit {
				schedule_uop(mop.uop1, port_busy, c1, true)
				schedule_uop(mop.uop2, port_busy, c2, true)
			}
			return c1
		}
	}
	return -1
}

SuperscalarProgram :: struct {
	program_buffer: [SuperscalarMaxSize]Instruction,
	size:           u32,
	addr_reg:       int,
	ipc:            f64,
	code_size:      int,
	macro_ops:      int,
	decode_cycles:  int,
	asic_latencies: [8]int,
	cpu_latencies:  [8]int,
	cpu_latency:    int,
	asic_latency:   int,
	mul_count:      int,
}

is_multiplication :: proc(t: SuperscalarInstructionType) -> bool {
	return t == .IMUL_R || t == .IMULH_R || t == .ISMULH_R || t == .IMUL_RCP
}

generate_superscalar :: proc(prog: ^SuperscalarProgram, gen: ^Blake2Generator) {
	port_busy: [CYCLE_MAP_SIZE][3]int
	registers: [8]RegisterInfo
	for i in 0 ..< 8 {
		registers[i] = RegisterInfo{latency = 0, last_op_group = .INVALID, last_op_par = -1, value = 0}
	}

	decode_buffer: ^DecoderBuffer = &decode_buffer_default
	current_instruction := ss_null_instruction()
	macro_op_index := 0
	code_size := 0
	macro_op_count := 0
	cycle := 0
	dep_cycle := 0
	retire_cycle := 0
	ports_saturated := false
	program_size := 0
	mul_count := 0
	throw_away_count := 0

	last_decode_cycle := 0
	for decode_cycle in 0 ..< RANDOMX_SUPERSCALAR_LATENCY {
		last_decode_cycle = decode_cycle
		if ports_saturated || program_size >= SuperscalarMaxSize {
			break
		}
		decode_buffer = fetch_next(decode_buffer, gen, ss_get_type(&current_instruction), decode_cycle, mul_count)
		buffer_index := 0
		for buffer_index < decode_buffer.size {
			top_cycle := cycle
			if macro_op_index >= ss_get_info(&current_instruction).op_count {
				if ports_saturated || program_size >= SuperscalarMaxSize {
					break
				}
				ss_create_for_slot(&current_instruction, gen, decode_buffer.counts[buffer_index], decode_buffer.index, decode_buffer.size == buffer_index + 1, buffer_index == 0)
				macro_op_index = 0
			}
			mop := ss_get_info(&current_instruction).ops[macro_op_index]
			schedule_cycle := schedule_mop(mop, &port_busy, cycle, dep_cycle, false)
			if schedule_cycle < 0 {
				ports_saturated = true
				break
			}
			if macro_op_index == ss_get_info(&current_instruction).src_op {
				forward := 0
				for forward < LOOK_FORWARD_CYCLES && !ss_select_source(&current_instruction, schedule_cycle, &registers, gen) {
					forward += 1
					schedule_cycle += 1
					cycle += 1
				}
				if forward == LOOK_FORWARD_CYCLES {
					if throw_away_count < MAX_THROWAWAY_COUNT {
						throw_away_count += 1
						macro_op_index = ss_get_info(&current_instruction).op_count
						continue
					}
					current_instruction = ss_null_instruction()
					break
				}
			}
			if macro_op_index == ss_get_info(&current_instruction).dst_op {
				forward := 0
				for forward < LOOK_FORWARD_CYCLES && !ss_select_destination(&current_instruction, schedule_cycle, throw_away_count > 0, &registers, gen) {
					forward += 1
					schedule_cycle += 1
					cycle += 1
				}
				if forward == LOOK_FORWARD_CYCLES {
					if throw_away_count < MAX_THROWAWAY_COUNT {
						throw_away_count += 1
						macro_op_index = ss_get_info(&current_instruction).op_count
						continue
					}
					current_instruction = ss_null_instruction()
					break
				}
			}
			throw_away_count = 0
			schedule_cycle = schedule_mop(mop, &port_busy, schedule_cycle, schedule_cycle, true)
			if schedule_cycle < 0 {
				ports_saturated = true
				break
			}
			dep_cycle = schedule_cycle + mop.latency
			if macro_op_index == ss_get_info(&current_instruction).result_op {
				dst := ss_get_destination(&current_instruction)
				ri := &registers[dst]
				retire_cycle = dep_cycle
				ri.latency = retire_cycle
				ri.last_op_group = ss_get_group(&current_instruction)
				ri.last_op_par = ss_get_group_par(&current_instruction)
			}
			code_size += mop.size
			buffer_index += 1
			macro_op_index += 1
			macro_op_count += 1
			if schedule_cycle >= RANDOMX_SUPERSCALAR_LATENCY {
				ports_saturated = true
			}
			cycle = top_cycle
			if macro_op_index >= ss_get_info(&current_instruction).op_count {
				ss_to_instr(&current_instruction, &prog.program_buffer[program_size])
				program_size += 1
				if is_multiplication(ss_get_type(&current_instruction)) {
					mul_count += 1
				}
			}
		}
		cycle += 1
	}
	ipc := f64(macro_op_count) / f64(retire_cycle)
	for i in 0 ..< 8 {
		prog.asic_latencies[i] = 0
	}
	for i in 0 ..< program_size {
		instr := prog.program_buffer[i]
		d := int(instr.dst)
		s := int(instr.src)
		lat_dst := prog.asic_latencies[d] + 1
		lat_src: int
		if d != s {
			lat_src = prog.asic_latencies[s] + 1
		} else {
			lat_src = 0
		}
		prog.asic_latencies[d] = max(lat_dst, lat_src)
	}
	asic_latency_max := 0
	address_reg := 0
	for i in 0 ..< 8 {
		if prog.asic_latencies[i] > asic_latency_max {
			asic_latency_max = prog.asic_latencies[i]
			address_reg = i
		}
		prog.cpu_latencies[i] = registers[i].latency
	}
	prog.size = u32(program_size)
	prog.addr_reg = address_reg
	prog.cpu_latency = retire_cycle
	prog.asic_latency = asic_latency_max
	prog.code_size = code_size
	prog.macro_ops = macro_op_count
	prog.ipc = ipc
	prog.mul_count = mul_count
	prog.decode_cycles = last_decode_cycle
}
clz64 :: proc(x: u64) -> u32 {
	n: u32 = 0
	mask: u64 = 1 << 63
	for mask != 0 {
		if (x & mask) != 0 {
			break
		}
		n += 1
		mask >>= 1
	}
	return n
}
randomx_reciprocal :: proc(divisor: u32) -> u64 {
	// divisor must not be 0 or a power of 2
	p2 := u64(1) << 63
	q := p2 / u64(divisor)
	r := p2 % u64(divisor)
	shift := u32(64) - clz64(u64(divisor))
	return (q << shift) + ((r << shift) / u64(divisor))
}
rotr :: proc(x: u64, n: u32) -> u64 {
	if n == 0 {
		return x
	}
	return (x >> n) | (x << (64 - n))
}
mulh :: proc(a: u64, b: u64) -> u64 {
	p := u128(a) * u128(b)
	return u64(p >> 64)
}
smulh :: proc(a: u64, b: u64) -> u64 {
	p := i128(cast(i64)a) * i128(cast(i64)b)
	return u64(p >> 64)
}
sign_extend2s :: proc(x: u32) -> u64 {
	return u64(cast(i64)cast(i32)x)
}
execute_superscalar :: proc(r: ^[8]u64, prog: ^SuperscalarProgram, reciprocals: []u64) {
	for j in 0 ..< int(prog.size) {
		instr := prog.program_buffer[j]
		d := int(instr.dst)
		s := int(instr.src)
		switch SuperscalarInstructionType(instr.opcode) {
		case .ISUB_R:
			r[d] -= r[s]
		case .IXOR_R:
			r[d] ~= r[s]
		case .IADD_RS:
			r[d] += r[s] << uint(get_mod_shift(instr))
		case .IMUL_R:
			r[d] *= r[s]
		case .IROR_C:
			r[d] = rotr(r[d], instr.imm32)
		case .IADD_C7, .IADD_C8, .IADD_C9:
			r[d] += sign_extend2s(instr.imm32)
		case .IXOR_C7, .IXOR_C8, .IXOR_C9:
			r[d] ~= sign_extend2s(instr.imm32)
		case .IMULH_R:
			r[d] = mulh(r[d], r[s])
		case .ISMULH_R:
			r[d] = smulh(r[d], r[s])
		case .IMUL_RCP:
			if len(reciprocals) > 0 {
				r[d] *= reciprocals[instr.imm32]
			} else {
				r[d] *= randomx_reciprocal(instr.imm32)
			}
		case .NOP, .INVALID:
			panic("unreachable superscalar op")
		}
	}
}
