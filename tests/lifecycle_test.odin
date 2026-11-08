package frostrig_tests

import testing "core:testing"
import core "../core"

@(test)
lifecycle_created_is_zero :: proc(t: ^testing.T) {
	testing.expect(t, u8(core.Lifecycle.Created) == 0, "Lifecycle.Created must be 0")
}

@(test)
lifecycle_enum_values_are_distinct :: proc(t: ^testing.T) {
	values := [5]u8{
		u8(core.Lifecycle.Created),
		u8(core.Lifecycle.Initialized),
		u8(core.Lifecycle.Running),
		u8(core.Lifecycle.Stopping),
		u8(core.Lifecycle.Stopped),
	}
	for i in 0 ..< len(values) {
		for j in i+1 ..< len(values) {
			testing.expect(t, values[i] != values[j], "distinct Lifecycle values must not collide")
		}
	}
}
