package frostrig_tests

import testing "core:testing"
import core "../core"
import algo "../algo"

@(test)
register_empty_name_returns_invalid_argument :: proc(t: ^testing.T) {
	e := algo.Algo_Entry{id = 0, name = ""}
	err := algo.register(e)
	testing.expect(t, err == core.Error.Invalid_Argument, "empty name must return Invalid_Argument")
}

@(test)
duplicate_register_returns_already_initialized :: proc(t: ^testing.T) {
	e := algo.Algo_Entry{id = 42, name = "test_algo"}
	err1 := algo.register(e)
	testing.expect(t, err1 == core.Error.None, "first register must succeed")

	err2 := algo.register(e)
	testing.expect(t, err2 == core.Error.Already_Initialized, "duplicate register must return Already_Initialized")
}

@(test)
lookup_by_id_and_name_agree :: proc(t: ^testing.T) {
	e := algo.Algo_Entry{id = 7, name = "lookup_probe"}
	_ = algo.register(e)

	by_id, ok_id := algo.lookup(7)
	testing.expect(t, ok_id, "lookup by id must succeed")
	testing.expect(t, by_id.name == "lookup_probe", "lookup by id must return correct name")

	by_name, ok_name := algo.lookup_by_name("lookup_probe")
	testing.expect(t, ok_name, "lookup by name must succeed")
	testing.expect(t, by_name.id == 7, "lookup by name must return correct id")
}

@(test)
lookup_unknown_id_returns_false :: proc(t: ^testing.T) {
	_, ok := algo.lookup(999)
	testing.expect(t, !ok, "lookup of unregistered id must return ok=false")
}
