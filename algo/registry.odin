package frostrig_algo

import core "../core"

MAX_ALGOS :: 32

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
	}
	return {}, false
}

count :: proc() -> int {
	return entry_count
}
