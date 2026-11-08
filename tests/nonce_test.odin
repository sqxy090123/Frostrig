package frostrig_tests

import testing "core:testing"
import core "../core"
import worker "../worker"

@(test)
split_nonce_zero_threads_returns_invalid_argument :: proc(t: ^testing.T) {
	_, err := worker.split_nonce_range(0, 16, 0)
	testing.expect(t, err == core.Error.Invalid_Argument, "zero thread_count must return Invalid_Argument")
}

@(test)
split_nonce_covers_full_range :: proc(t: ^testing.T) {
	ranges, err := worker.split_nonce_range(100, 16, 3)
	testing.expect(t, err == core.Error.None, "valid split must succeed")
	testing.expect(t, len(ranges) == 3, "split must return one range per thread")

	total: u64
	for r in ranges {
		total += r.count
	}
	testing.expect(t, total == 16, "union of sub-ranges must cover full nonce_count")
	_ = ranges
}

@(test)
split_nonce_ranges_do_not_overlap :: proc(t: ^testing.T) {
	ranges, _ := worker.split_nonce_range(0, 10, 4)
	testing.expect(t, len(ranges) == 4, "split must return 4 ranges")
	for i in 0 ..< len(ranges) {
		for j in i+1 ..< len(ranges) {
			if ranges[i].start < ranges[j].start {
				hi_i := ranges[i].start + ranges[i].count
				testing.expect(t, ranges[j].start >= hi_i, "sub-ranges must not overlap")
			} else {
				hi_j := ranges[j].start + ranges[j].count
				testing.expect(t, ranges[i].start >= hi_j, "sub-ranges must not overlap")
			}
		}
	}
	_ = ranges
}
