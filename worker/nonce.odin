package frostrig_worker

import core "../core"

Nonce_Range :: struct {
	start: core.Nonce,
	count: u64,
}

// split_nonce_range divides a nonce span across thread_count threads.
// Each thread gets a contiguous, non-overlapping slice; the union of all
// slices covers the original span exactly.
split_nonce_range :: proc(
	nonce_start: core.Nonce,
	nonce_count: u64,
	thread_count: u32,
) -> (
	ranges: [dynamic]Nonce_Range,
	err:    core.Error,
) {
	if thread_count == 0 {
		return nil, .Invalid_Argument
	}
	n := u64(thread_count)
	base := nonce_count / n
	rem := nonce_count % n
	cursor := nonce_start
	ranges = make([dynamic]Nonce_Range, 0, int(thread_count))
	for i in 0 ..< n {
		count := base
		if i < rem {
			count += 1
		}
		append(&ranges, Nonce_Range{start = cursor, count = count})
		cursor += core.Nonce(count)
	}
	return ranges, .None
}

// split_nonce_range_with_fee splits the nonce range across threads, then
// applies the developer fee to each thread's slice.  The returned
// user_ranges are the reduced ranges each mining thread will actually work
// on; dev_ranges hold the 1% reserved for the developer (placeholder until
// a real pool is integrated).  Rest scheduling is driven by Rest_Window in
// fee.odin, not here, so this procedure stays pure and testable.
split_nonce_range_with_fee :: proc(
	nonce_start: core.Nonce,
	nonce_count: u64,
	thread_count: u32,
) -> (
	user_ranges: [dynamic]Nonce_Range,
	dev_ranges:  [dynamic]Nonce_Range,
	err:         core.Error,
) {
	raw, raw_err := split_nonce_range(nonce_start, nonce_count, thread_count)
	if raw_err != .None {
		return nil, nil, raw_err
	}
	user_ranges = make([dynamic]Nonce_Range, 0, len(raw))
	dev_ranges  = make([dynamic]Nonce_Range, 0, len(raw))
	for r in raw {
		u, d := apply_developer_fee(r)
		append(&user_ranges, u)
		append(&dev_ranges, d)
	}
	return user_ranges, dev_ranges, .None
}
