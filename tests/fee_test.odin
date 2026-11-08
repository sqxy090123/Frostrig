package frostrig_tests

import testing "core:testing"
import core "../core"
import worker "../worker"

@(test)
apply_fee_reserves_one_percent :: proc(t: ^testing.T) {
	// 1000 nonces -> dev gets 10 (1%), user gets 990
	r := worker.Nonce_Range{start = 0, count = 1000}
	user, dev := worker.apply_developer_fee(r)
	testing.expect(t, dev.count == 10, "dev should get 1% (10 of 1000)")
	testing.expect(t, user.count == 990, "user should get 99% (990 of 1000)")
	testing.expect(t, user.count + dev.count == 1000, "user + dev must cover full range")
	testing.expect(t, dev.start == 0, "dev slice starts at range start")
	testing.expect(t, user.start == core.Nonce(10), "user slice starts after dev slice")
}

@(test)
apply_fee_zero_bps_returns_full_range_to_user :: proc(t: ^testing.T) {
	r := worker.Nonce_Range{start = 5, count = 200}
	user, dev := worker.apply_developer_fee(r, 0)
	testing.expect(t, user == r, "zero fee must leave range untouched")
	testing.expect(t, dev.count == 0, "dev range must be empty")
}

@(test)
apply_fee_small_range_skips_dev_slice :: proc(t: ^testing.T) {
	// count < 10000/bps means dev_count rounds to 0; fee is skipped
	r := worker.Nonce_Range{start = 0, count = 5}
	user, dev := worker.apply_developer_fee(r)
	testing.expect(t, dev.count == 0, "tiny range must not be split")
	testing.expect(t, user == r, "user keeps the full tiny range")
}

@(test)
split_with_fee_user_plus_dev_covers_range :: proc(t: ^testing.T) {
	users, devs, err := worker.split_nonce_range_with_fee(0, 10000, 4)
	testing.expect(t, err == core.Error.None, "valid split must succeed")
	testing.expect(t, len(users) == 4, "one user range per thread")
	testing.expect(t, len(devs) == 4, "one dev range per thread")

	user_total, dev_total: u64
	for r in users {
		user_total += r.count
	}
	for r in devs {
		dev_total += r.count
	}
	testing.expect(t, user_total + dev_total == 10000, "user + dev must cover full nonce_count")
	// 4 threads * 2500 each = 10000; 1% of each 2500 = 25, so dev_total = 100
	testing.expect(t, dev_total == 100, "total dev fee across 4 threads of 10000 should be 100")
	_ = users
	_ = devs
}

@(test)
rest_window_triggers_after_work_cycles :: proc(t: ^testing.T) {
	w := worker.Rest_Window{}
	triggered := false
	for i in 0 ..< 64 {
		triggered = worker.tick_rest_window(&w)
	}
	testing.expect(t, triggered, "rest must trigger after 64 slices")
	worker.reset_rest_window(&w)
	testing.expect(t, !worker.tick_rest_window(&w), "counter must reset after rest")
}
