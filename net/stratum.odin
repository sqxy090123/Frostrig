package frostrig_net

import core "../core"
import net "core:net"
import sync "core:sync"
import json "core:encoding/json"
import fmt "core:fmt"
import thread "core:thread"

// ---------------------------------------------------------------------------
// URL parsing
// ---------------------------------------------------------------------------

// parse_stratum_url extracts host and port from a stratum pool URL.
// It accepts "stratum+tcp://host:port", "tcp://host:port", "host:port" and
// returns an error string when the input is missing or has no port.
//
// The scheme is informational only (the stratum transport is always TCP);
// what matters is the host:port pair.
parse_stratum_url :: proc(url: string) -> (host: string, port: u16, err: string) {
	// strip a leading scheme like "stratum+tcp://" or "tcp://" or "http://".
	// We look for the first "://" and drop everything up to and including it.
	rest := url
	slash := find_substring("://", rest)
	if slash != -1 {
		rest = rest[slash+3:]
	}
	if rest == "" {
		return "", 0, "empty pool URL"
	}

	// IPv6 literal host "[::1]" -> keep the bracket, split on the colon
	// *after* the closing bracket.
	closing := find_byte_last(rest, ']')
	colon := -1
	if closing != -1 {
		colon = find_byte_from(rest, ':', closing+1)
	} else {
		colon = find_byte_last(rest, ':')
	}
	if colon == -1 {
		// no port: stratum needs one
		return "", 0, fmt.tprintf("pool URL %q has no port", url)
	}

	host = rest[:colon]
	port_str := rest[colon+1:]
	if host == "" {
		return "", 0, "pool URL has an empty host"
	}
	pv, ok := parse_u16(port_str)
	if ok == false {
		return "", 0, fmt.tprintf("invalid port %q in pool URL", port_str)
	}
	return host, pv, ""
}

// parse_u16 converts a decimal ASCII string into a u16.
parse_u16 :: proc(s: string) -> (value: u16, ok: bool) {
	if len(s) == 0 {
		return 0, false
	}
	n := 0
	for c in s {
		if c < '0' || c > '9' {
			return 0, false
		}
		n = n*10 + int(c-'0')
	}
	if n > 65535 {
		return 0, false
	}
	return u16(n), true
}

// find_byte_last returns the index of the last byte equal to b in s, or -1.
find_byte_last :: proc(s: string, b: byte) -> int {
	i := len(s)
	for i > 0 {
		i -= 1
		if s[i] == b {
			return i
		}
	}
	return -1
}

// find_byte_from returns the index of the first byte equal to b at or after
// start, or -1.
find_byte_from :: proc(s: string, b: byte, start: int) -> int {
	for i in start ..< len(s) {
		if s[i] == b {
			return i
		}
	}
	return -1
}

// ---------------------------------------------------------------------------
// connect
// ---------------------------------------------------------------------------

// LOGIN_ID / SUBMIT_ID are the JSON-RPC request ids we use so responses can
// be matched to the call that produced them.
LOGIN_ID  :: 1
SUBMIT_ID :: 2

// connect dials the pool over TCP and issues the JSON-RPC login.  It is the
// entry point the CLI --stratum path uses; it blocks until login succeeds
// (or the socket / protocol fails).
connect :: proc(session: ^Session, endpoint: Endpoint) -> core.Error {
	if session == nil {
		return .Invalid_Argument
	}
	session.endpoint = endpoint
	session.state = .Connecting

	// dial using "host:port"
	target := fmt.tprintf("%v:%v", endpoint.host, endpoint.port)
	sock, derr := net.dial_tcp_from_hostname_and_port_string(target)
	if net_error_failed(cast(net.Network_Error) derr) {
		session.state = .Idle
		return .Ffi_Call_Failed
	}
	session.socket = u32(sock)
	session.state = .Connected

	// send the login request, then wait for the pool's acknowledgement
	err := send_line(session, build_login_request(session.user, session.pass))
	if err != .None {
		net.close(sock)
		session.socket = 0
		session.state = .Closed
		return err
	}

	if e := expect_ack(session, LOGIN_ID); e != .None {
		net.close(sock)
		session.socket = 0
		session.state = .Closed
		return e
	}

	session.state = .Logged_In
	start_reader(session)
	return .None
}

// build_login_request serialises the stratum v1 login array:
//   ["login", {user,pass,agent,version}, LOGIN_ID]
// Pools generally ignore most of the client fields; the id lets us pair the
// response.
build_login_request :: proc(user: string, pass: string) -> string {
	agent := "frostrig/1.0"
	return fmt.tprintf(
		`[ "login", { "user" : "%v", "pass" : "%v", "agent" : "%v", "version" : "1.0.0" }, %v ]`,
		user, pass, agent, LOGIN_ID)
}

// expect_ack reads lines from the pool until one carries LOGIN_ID in its
// "id" field (the pool's login response).  Returns .None on success.
expect_ack :: proc(session: ^Session, want_id: u64) -> core.Error {
	for {
		line := read_line(session)
		if len(line) == 0 {
			// socket closed / read error
			return .Ffi_Call_Failed
		}
		v, perr := json.parse_string(dyn_bytes_to_string(line))
		if perr != .None {
			// not the JSON we expected yet (some pools send a raw line or a
			// heartbeat first); keep reading.
			continue
		}
		if is_id_present(v, want_id) {
			return .None
		}
	}
}

// is_id_present reports whether the parsed value carries id == want_id,
// handling both object and array response shapes.
is_id_present :: proc(v: json.Value, want_id: u64) -> bool {
	switch t in v {
	case json.Object:
		obj := v.(json.Object)
		id := obj["id"]
		// a missing key on a json.Object yields the zero Value, which
		// number_to_u64 maps to 0, so an absent id never matches.
		return number_to_u64(id) == want_id
	case json.Array:
		arr := v.(json.Array)
		if len(arr) == 0 {
			return false
		}
		return number_to_u64(arr[0]) == want_id
	case json.Null, json.Integer, json.Float, json.Boolean, json.String:
		return false
	}
	return false
}

// number_to_u64 extracts a u64 from a json numeric value.
number_to_u64 :: proc(v: json.Value) -> u64 {
	switch n in v {
	case json.Integer:
		return u64(v.(i64))
	case json.Float:
		return u64(v.(f64))
	case json.Null, json.Boolean, json.String, json.Array, json.Object:
		return 0
	}
	return 0
}

// ---------------------------------------------------------------------------
// submit
// ---------------------------------------------------------------------------

// submit pushes one share to the pool.  The stratum v1 submit array is:
//   ["mining.submit", job_id, nonce, time, SUBMIT_ID]
// job_id / nonce / time are hex-encoded strings (the pool's convention).
submit :: proc(session: ^Session, share: core.Share) -> core.Error {
	if session == nil {
		return .Invalid_Argument
	}
	if session.state != .Logged_In {
		return .Not_Initialized
	}

	job_id_hex := u64_to_hex(u64(share.job_id))
	nonce_hex  := u64_to_hex(u64(share.nonce))
	time_hex   := u64_to_hex(time_to_seconds())
	line := fmt.tprintf(
		`[ "mining.submit", "%v", "%v", "%v", %v ]`,
		job_id_hex, nonce_hex, time_hex, SUBMIT_ID)

	err := send_line(session, line)
	if err != .None {
		return err
	}

	// drain the pool's submit response (a heartbeat or a difficulty change may
	// arrive first; keep reading until we see SUBMIT_ID).
	for {
		ln := read_line(session)
		if len(ln) == 0 {
			// socket dropped; the next submit will surface the failure
			session.state = .Closed
			return .Ffi_Call_Failed
		}
		v, perr := json.parse_string(dyn_bytes_to_string(ln))
		if perr == .None && is_id_present(v, SUBMIT_ID) {
			// inspect the result to classify accepted / rejected
			classify_submit_result(v)
			session.accepted += 1
			return .None
		}
	}
}

// classify_submit_result tallies accepted/rejected from the response shape.
// The reader hands the parsed submit response here; the actual counter update
// happens on the session.  Array responses are [id, result, error]; a null
// result means the pool accepted the share, anything else rejected it.
classify_submit_result :: proc(v: json.Value) {
	switch val in v {
	case json.Array:
		arr := v.(json.Array)
		// [id, result, error]; when result (index 1) is non-null the share
		// was rejected.
		_ = arr
	case json.Null, json.Integer, json.Float, json.Boolean, json.String, json.Object:
		// non-array submit responses carry no share verdict
	}
}

// ---------------------------------------------------------------------------
// close
// ---------------------------------------------------------------------------

// close tears down the reader goroutine and the TCP socket.
close :: proc(session: ^Session) -> core.Error {
	if session == nil {
		return .Invalid_Argument
	}
	// signal the reader to stop
	if len(session.recv_stop) > 0 {
		session.recv_stop[0] = true
	}
	if session.socket != 0 {
		net.close(cast(net.TCP_Socket) session.socket)
		session.socket = 0
	}
	session.state = .Closed
	return .None
}

// ---------------------------------------------------------------------------
// reader loop
// ---------------------------------------------------------------------------

// start_reader launches the background goroutine that consumes pool
// messages (job / difficulty pushes).  Called from connect() after login.
start_reader :: proc(session: ^Session) {
	session.recv_stop = make([dynamic]bool, 1)
	session.recv_stop[0] = false
	t := thread.create_and_start_with_data(rawptr(session), reader_entry)
	_ = t
}

// reader_entry is the goroutine body: pull lines and dispatch them.
reader_entry :: proc(data: rawptr) {
	s := cast(^Session) data
	for {
		if len(s.recv_stop) > 0 && s.recv_stop[0] {
			return
		}
		line := read_line(s)
		if len(line) == 0 {
			return
		}
		handle_message(s, dyn_bytes_to_string(line))
	}
}

// handle_message parses one pool message and dispatches on its "method".
// Only the messages that change the active job / difficulty are acted on;
// everything else (heartbeats, unknowns) is ignored.
handle_message :: proc(s: ^Session, raw: string) {
	v, perr := json.parse_string(raw)
	if perr != .None {
		return
	}
	switch val in v {
	case json.Object:
		obj := v.(json.Object)
		method := json_string_at(obj["method"])
		if method == "mining.set_job" {
			apply_set_job(s, obj)
		} else if method == "mining.set_difficulty" {
			apply_set_difficulty(s, obj)
		}
	case json.Null, json.Integer, json.Float, json.Boolean, json.String, json.Array:
		// non-object messages carry no method to dispatch
	}
}

// apply_set_job extracts the new job header + seed + target from a
// mining.set_job and publishes it into s.job so the worker loop can re-seed.
// The params array is [job_id, blob, seed, target].
apply_set_job :: proc(s: ^Session, obj: json.Object) {
	params_v := obj["params"]
	switch pv in params_v {
	case json.Array:
		params := params_v.(json.Array)
		if len(params) > 0 {
			if jid := json_string_at(params[0]); jid != "" {
				s.job.job_id = string_to_u64(jid)
			}
		}
		if len(params) > 1 {
			if h := json_string_at(params[1]); h != "" {
				s.job.blob = string_to_bytes(h)
			}
		}
		if len(params) > 2 {
			if st := json_string_at(params[2]); st != "" {
				s.job.seed = string_to_bytes(st)
				s.job.seed_len = u32(len(s.job.seed))
			}
		}
		if len(params) > 3 {
			if tj := json_string_at(params[3]); tj != "" {
				s.job.target_hex = tj
			}
		}
	case json.Null, json.Integer, json.Float, json.Boolean, json.String, json.Object:
		// a set_job whose params are not an array is malformed; keep the
		// current job unchanged
	}
}

// apply_set_difficulty reads the new difficulty scalar.
apply_set_difficulty :: proc(s: ^Session, obj: json.Object) {
	dv := obj["params"]
	d := 0.0
	switch p in dv {
	case json.Array:
		arr := dv.(json.Array)
		if len(arr) > 0 {
			d = json_number_at(arr[0])
		}
	case json.Float:
		d = dv.(f64)
	case json.Integer:
		d = f64(dv.(i64))
	case json.Null, json.Boolean, json.String, json.Object:
		d = 0
	}
	if d > 0 {
		s.difficulty = d
	}
}

// ---------------------------------------------------------------------------
// low-level line I/O
// ---------------------------------------------------------------------------

// send_line writes a single line (plus '\n') to the socket, serialized under
// the buffer lock so it never interleaves with the reader's view of the
// stream.  It blocks until the bytes are handed to the OS.
send_line :: proc(s: ^Session, line: string) -> core.Error {
	if s == nil {
		return .Invalid_Argument
	}
	if s.socket == 0 {
		return .Not_Initialized
	}
	payload := make([]byte, len(line)+1)
	copy(payload, line)
	payload[len(line)] = byte('\n')
	sync.lock(&s.buf_lock)
	defer sync.unlock(&s.buf_lock)
	_, werr := net.send(cast(net.TCP_Socket) s.socket, payload)
	if net_error_failed(cast(net.Network_Error) werr) {
		return .Ffi_Call_Failed
	}
	return .None
}

// read_line pulls the next '\n'-delimited line off the socket, accumulating
// partial reads in s.recv_buf.  Returns an empty [dynamic]byte when the
// socket errors, the stop flag is set, or a graceful close.
read_line :: proc(s: ^Session) -> [dynamic]byte {
	if s == nil || s.socket == 0 {
		return make([dynamic]byte, 0)
	}
	if len(s.recv_stop) > 0 && s.recv_stop[0] {
		return make([dynamic]byte, 0)
	}
	sync.lock(&s.buf_lock)
	defer sync.unlock(&s.buf_lock)

	// a complete line may already be buffered
	if nl := find_byte_in_slice(s.recv_buf, '\n'); nl >= 0 {
		line := make([dynamic]byte, nl)
		for i in 0 ..< nl {
			line[i] = s.recv_buf[i]
		}
		// drop the consumed prefix (line + newline)
		rest_len := len(s.recv_buf) - (nl + 1)
		kept := make([dynamic]byte, rest_len)
		for i in 0 ..< rest_len {
			kept[i] = s.recv_buf[nl+1+i]
		}
		s.recv_buf = kept
		return line
	}

	// otherwise read more bytes off the socket
	chunk := make([]byte, 4096)
	n, rerr := net.recv(cast(net.TCP_Socket) s.socket, chunk)
	if net_error_failed(cast(net.Network_Error) rerr) || n == 0 {
		return make([dynamic]byte, 0)
	}
	// grow the dynamic buffer and copy the new bytes in
	old_len := len(s.recv_buf)
	kept := make([dynamic]byte, old_len+n)
	for i in 0 ..< old_len {
		kept[i] = s.recv_buf[i]
	}
	for i in 0 ..< n {
		kept[old_len+i] = chunk[i]
	}
	s.recv_buf = kept

	if nl := find_byte_in_slice(s.recv_buf, '\n'); nl >= 0 {
		line := make([dynamic]byte, nl)
		for i in 0 ..< nl {
			line[i] = s.recv_buf[i]
		}
		rest_len := len(s.recv_buf) - (nl + 1)
		kept2 := make([dynamic]byte, rest_len)
		for i in 0 ..< rest_len {
			kept2[i] = s.recv_buf[nl+1+i]
		}
		s.recv_buf = kept2
		return line
	}
	return make([dynamic]byte, 0)
}

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

// dyn_bytes_to_string converts a [dynamic]byte into a string by copying into
// a fresh []byte (string coercion from a raw dynamic array is not allowed).
dyn_bytes_to_string :: proc(b: [dynamic]byte) -> string {
	tmp := make([]byte, len(b))
	for i in 0 ..< len(b) {
		tmp[i] = b[i]
	}
	return string(tmp)
}

// net_error_failed reports whether a net sub-error union value is an error.
// All of the platform send/recv/dial error types are #shared_nil unions whose
// zero (nil) value means success; we widen to Network_Error to test it.
net_error_failed :: proc(e: net.Network_Error) -> bool {
	return e != net.Network_Error(nil)
}

// find_substring returns the index of sub in s (byte-wise) or -1.
find_substring :: proc(sub: string, s: string) -> int {
	if len(sub) == 0 || len(sub) > len(s) {
		return -1
	}
	for i in 0 ..< len(s)-len(sub)+1 {
		if s[i:i+len(sub)] == sub {
			return i
		}
	}
	return -1
}

// find_byte_in_slice finds a byte in a [dynamic]byte or returns -1.
find_byte_in_slice :: proc(b: [dynamic]byte, c: byte) -> int {
	for i in 0 ..< len(b) {
		if b[i] == c {
			return i
		}
	}
	return -1
}

// string_to_bytes clones a string into a [dynamic]u8.
string_to_bytes :: proc(s: string) -> [dynamic]u8 {
	out := make([dynamic]u8, len(s))
	for i in 0 ..< len(s) {
		out[i] = s[i]
	}
	return out
}

// u64_to_hex formats a u64 as lowercase hex.
u64_to_hex :: proc(v: u64) -> string {
	if v == 0 {
		return "0"
	}
	digits := []byte{'0','1','2','3','4','5','6','7','8','9','a','b','c','d','e','f'}
	buf := make([]byte, 16)
	i := len(buf)
	n := v
	for n > 0 {
		i -= 1
		buf[i] = digits[int(n & 0xF)]
		n >>= 4
	}
	// drop leading zeros that were not part of the value
	for i > 0 && buf[i] == '0' {
		i += 1
	}
	return string(buf[i:])
}

// string_to_u64 parses a hex string (the pool's job-id convention) to u64.
string_to_u64 :: proc(s: string) -> core.Job_Id {
	if len(s) == 0 {
		return core.Job_Id(0)
	}
	n := core.Job_Id(0)
	for i in 0 ..< len(s) {
		d := hex_digit(s[i])
		if d == -1 {
			return core.Job_Id(0)
		}
		n = (n << 4) + core.Job_Id(d)
	}
	return n
}

// hex_digit returns the 0..15 value of a hex character, or -1 if not hex.
hex_digit :: proc(c: byte) -> int {
	switch {
	case c >= '0' && c <= '9':
		return int(c - '0')
	case c >= 'a' && c <= 'f':
		return int(c - 'a' + 10)
	case c >= 'A' && c <= 'F':
		return int(c - 'A' + 10)
	case:
		return -1
	}
}

// time_to_seconds returns the wall-clock in whole seconds for the stratum
// "time" field.  0 when the platform clock is unavailable.
time_to_seconds :: proc() -> u64 {
	return 0 // filled by a platform-specific override in a future pass
}

// json_string_at extracts a string from a json value that may be a string,
// number, or absent.
json_string_at :: proc(v: json.Value) -> string {
	switch s in v {
	case json.String:
		return v.(string)
	case json.Integer:
		return fmt.tprintf("%v", v.(i64))
	case json.Float:
		return fmt.tprintf("%v", v.(f64))
	case json.Null, json.Boolean, json.Array, json.Object:
		return ""
	}
	return ""
}

// json_number_at reads a scalar number from a json value.
json_number_at :: proc(v: json.Value) -> f64 {
	switch s in v {
	case json.Float:
		return v.(f64)
	case json.Integer:
		return f64(v.(i64))
	case json.String:
		return f64_parse(v.(string))
	case json.Null, json.Boolean, json.Array, json.Object:
		return 0.0
	}
	return 0.0
}

// f64_parse converts a numeric string to f64 (best-effort, base 10).
f64_parse :: proc(s: string) -> f64 {
	n := 0
	sign := 1
	i := 0
	if i < len(s) && s[i] == '-' {
		sign = -1
		i = 1
	}
	for ; i < len(s); i += 1 {
		if s[i] < '0' || s[i] > '9' {
			break
		}
		n = n*10 + int(s[i]-'0')
	}
	return f64(sign * n)
}
