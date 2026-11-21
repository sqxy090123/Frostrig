package frostrig_algo

import core "../core"

MAX_ALGOS :: 32

// Worm2_Id is the registry id of the Worm/2 torus walk, exported so the
// command line can tell the viewer-capable algorithm apart from the rest
// without hardcoding a number.
Worm2_Id: core.Algo_Id = algo_id_worm2

@(private)
entries: [MAX_ALGOS]Algo_Entry

@(private)
entry_count: int

register :: proc(entry: Algo_Entry) -> core.Error {
	if len(entry.name) == 0 {
		return .Invalid_Argument
	}
	for i in 0 ..< entry_count {
		if entries[i].id == entry.id {
			return .Already_Initialized
		}
	}
	if entry_count >= MAX_ALGOS {
		return .Internal
	}
	entries[entry_count] = entry
	entry_count += 1
	return .None
}

lookup :: proc(id: core.Algo_Id) -> (entry: Algo_Entry, ok: bool) {
	for i in 0 ..< entry_count {
		if entries[i].id == id {
			return entries[i], true
		}
	}
	return {}, false
}

lookup_by_name :: proc(name: string) -> (entry: Algo_Entry, ok: bool) {
	if len(name) == 0 {
		return {}, false
	}
	for i in 0 ..< entry_count {
		if entries[i].name == name {
			return entries[i], true
		}
		if len(entries[i].alias) > 0 && entries[i].alias == name {
			return entries[i], true
		}
	}
	return {}, false
}

lookup_by_index :: proc(index: int) -> (entry: Algo_Entry, ok: bool) {
	if index < 0 || index >= entry_count {
		return {}, false
	}
	return entries[index], true
}

count :: proc() -> int {
	return entry_count
}
