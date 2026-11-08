package frostrig_worker

import core "../core"
import time "core:time"

// 1% expressed in basis points (1% = 100 bps).
// bps avoids floating point and makes the fee exactly divisible.
DEVELOPER_FEE_BPS: u32 = 100

// Developer_Fee_Bps is the live fee value read at runtime so that a
// future config or CLI override can change it without touching the constant.
Developer_Fee_Bps: u32 = DEVELOPER_FEE_BPS

// rest_work_cycles is how many nonce slices to process before the thread
// takes a rest break.  The constant is intentionally small so the break
// is observable during development; a production build should tune this.
rest_work_cycles: u32 = 64

// rest_duration is how long the thread sleeps during a break.
rest_duration: time.Duration = 50 * time.Second

// Rest_Window tracks the periodic "let the user's computer rest" schedule.
// The developer fee and the rest are both placeholders: the fee reserves
// 1% of the nonce space for the developer, and the rest pauses the mining
// thread for rest_duration every rest_work_cycles slices, reducing
// sustained CPU/GPU load and electricity cost for the user.
Rest_Window :: struct {
	slices_since_rest: u32,
	total_sliced:      u64,
}

// apply_developer_fee carves out 1% of the nonce range for the developer.
// Returns the reduced user-facing range.  The developer slice is reserved
// but not hashed here; when a real mining pool is integrated, that slice
// will be directed to the developer's reward address instead of the user's.
// This is the placeholder the user asked for: the developer takes 1% of
// the work, and the "rest" mechanism below is how the user's machine
// gets a break.
apply_developer_fee :: proc(
	rng: Nonce_Range,
	fee_bps: u32 = Developer_Fee_Bps,
) -> (user_range: Nonce_Range, dev_range: Nonce_Range) {
	if rng.count == 0 || fee_bps == 0 {
		return rng, Nonce_Range{}
	}
	dev_count := rng.count * u64(fee_bps) / 10_000
	if dev_count == 0 {
		// range too small to carve out a whole nonce; skip the fee this round
		return rng, Nonce_Range{}
	}
	dev_range = Nonce_Range{start = rng.start, count = dev_count}
	user_range = Nonce_Range{start = rng.start + core.Nonce(dev_count), count = rng.count - dev_count}
	return user_range, dev_range
}

// tick_rest_window advances the rest schedule and returns true when the
// caller should now sleep for rest_duration, giving the user's machine a
// break.  This is the placeholder "rest" the user requested: instead of
// the thread running hot forever, it periodically yields.
tick_rest_window :: proc(w: ^Rest_Window) -> bool {
	w.slices_since_rest += 1
	w.total_sliced += 1
	return w.slices_since_rest >= rest_work_cycles
}

// reset_rest_window clears the counter after a rest has been taken.
reset_rest_window :: proc(w: ^Rest_Window) {
	w.slices_since_rest = 0
}

// rest_for is the actual sleep that a mining thread calls when tick_rest_window
// returns true.  It pauses for rest_duration, letting the user's CPU/GPU
// cool down and saving power.
rest_for :: proc() {
	time.sleep(rest_duration)
}
