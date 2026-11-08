package frostrig_core

Lifecycle :: enum u8 {
	Created,
	Initialized,
	Running,
	Stopping,
	Stopped,
}

Lifecycle_Hooks :: struct {
	init:    proc(ctx: rawptr) -> Error,
	start:   proc(ctx: rawptr) -> Error,
	stop:    proc(ctx: rawptr) -> Error,
	destroy: proc(ctx: rawptr),
}
