package frostrig_tests

import testing "core:testing"
import core "../core"
import net "../net"
import fmt "core:fmt"

// parse_stratum_url is pure string logic; it is the safest part of the
// stratum layer to unit-test because it performs no I/O.

@(test)
parse_stratum_url_strips_scheme_and_splits_host_port :: proc(t: ^testing.T) {
	host, port, err := net.parse_stratum_url("stratum+tcp://example.com:3333")
	testing.expect(t, err == "", fmt.tprintf("no error expected: got %v", err))
	testing.expect(t, host == "example.com", fmt.tprintf("host mismatch: got %v", host))
	testing.expect(t, port == 3333, fmt.tprintf("port mismatch: got %v", port))
}

@(test)
parse_stratum_url_plain_host_port :: proc(t: ^testing.T) {
	host, port, err := net.parse_stratum_url("192.0.2.1:5555")
	testing.expect(t, err == "", fmt.tprintf("no error expected: got %v", err))
	testing.expect(t, host == "192.0.2.1",
		fmt.tprintf("host mismatch: got %v", host))
	testing.expect(t, port == 5555, fmt.tprintf("port mismatch: got %v", port))
}

@(test)
parse_stratum_url_rejects_missing_port :: proc(t: ^testing.T) {
	_, _, err := net.parse_stratum_url("stratum+tcp://example.com")
	testing.expect(t, err != "", "expected an error when the port is missing")
}

@(test)
parse_stratum_url_rejects_bad_port :: proc(t: ^testing.T) {
	_, _, err := net.parse_stratum_url("stratum+tcp://example.com:99999")
	testing.expect(t, err != "", "expected an error when the port is out of range")
}

// connect with a nil session must reject before any I/O.

@(test)
connect_nil_session_returns_invalid_argument :: proc(t: ^testing.T) {
	err := net.connect(nil, net.Endpoint{host = "127.0.0.1", port = 8080})
	testing.expect(t, err == core.Error.Invalid_Argument,
		"connect with nil session must return Invalid_Argument")
}

// connect to a closed local port must fail fast with a non-None error and
// leave the session back in Idle.  127.0.0.1 with nothing listening returns
// a fast "connection refused" so the test never blocks and needs no network.

@(test)
connect_to_refused_port_fails_and_resets_state :: proc(t: ^testing.T) {
	s := new(net.Session)
	err := net.connect(s, net.Endpoint{host = "127.0.0.1", port = 1})
	testing.expect(t, err != core.Error.None,
		"connect to a refused port must fail")
	testing.expect(t, s.state == net.Session_State.Idle,
		fmt.tprintf("failed connect must reset the session to Idle, got %v", s.state))
	testing.expect(t, s.socket == 0, "socket must be 0 after a failed connect")
	defer free(s)
}

// close on a fresh session is a safe no-op that still marks it closed.

@(test)
close_fresh_session_returns_none_and_closes :: proc(t: ^testing.T) {
	s := new(net.Session)
	err := net.close(s)
	testing.expect(t, err == core.Error.None,
		fmt.tprintf("close on a fresh session must succeed, got %v", err))
	testing.expect(t, s.state == net.Session_State.Closed,
		fmt.tprintf("close must set state to Closed, got %v", s.state))
	defer free(s)
}
