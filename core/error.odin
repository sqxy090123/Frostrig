package frostrig_core

Error :: enum u32 {
	None = 0,
	Invalid_Argument,
	Not_Initialized,
	Already_Initialized,
	Unsupported_Algo,
	Out_Of_Memory,
	Huge_Pages_Unavailable,
	Thread_Spawn_Failed,
	Affinity_Failed,
	Ffi_Init_Failed,
	Ffi_Handle_Invalid,
	Ffi_Call_Failed,
	Queue_Full,
	Queue_Empty,
	Not_Implemented,
	Internal,

	// stratum connection phases, so the CLI can report *which* step failed
	// (dial vs. send-login vs. wait-for-ack) instead of one opaque error.
	Stratum_Dial_Failed,
	Stratum_Login_Failed,
	Stratum_Ack_Timeout,
}
