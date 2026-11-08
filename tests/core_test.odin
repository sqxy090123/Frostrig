package frostrig_tests

import testing "core:testing"
import core "../core"
import algo "../algo"

@(test)
error_none_is_zero :: proc(t: ^testing.T) {
	testing.expect(t, u32(core.Error.None) == 0, "Error.None must be 0")
}

@(test)
algo_initial_count_is_zero :: proc(t: ^testing.T) {
	testing.expect(t, algo.count() == 0, "initial algo registry must be empty")
}
