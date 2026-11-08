package frostrig_tests

import testing "core:testing"
import core "../core"
import net "../net"

@(test)
connect_nil_session_returns_invalid_argument :: proc(t: ^testing.T) {
	err := net.connect(nil, net.Endpoint{host = "127.0.0.1", port = 8080})
	testing.expect(t, err == core.Error.Invalid_Argument, "connect with nil session must return Invalid_Argument")
}

@(test)
connect_valid_session_returns_not_implemented :: proc(t: ^testing.T) {
	s := new(net.Session)
	err := net.connect(s, net.Endpoint{host = "127.0.0.1", port = 8080})
	testing.expect(t, err == core.Error.Not_Implemented, "connect must return Not_Implemented")
	testing.expect(t, s.state == net.Session_State.Connecting, "connect must set state to Connecting")
	defer free(s)
}

@(test)
login_returns_not_implemented :: proc(t: ^testing.T) {
	s := new(net.Session)
	err := net.login(s, "user", "pass")
	testing.expect(t, err == core.Error.Not_Implemented, "login must return Not_Implemented")
	defer free(s)
}

@(test)
submit_returns_not_implemented :: proc(t: ^testing.T) {
	s := new(net.Session)
	err := net.submit(s, core.Share{})
	testing.expect(t, err == core.Error.Not_Implemented, "submit must return Not_Implemented")
	defer free(s)
}

@(test)
close_valid_session_returns_not_implemented_and_closes :: proc(t: ^testing.T) {
	s := new(net.Session)
	err := net.close(s)
	testing.expect(t, err == core.Error.Not_Implemented, "close must return Not_Implemented")
	testing.expect(t, s.state == net.Session_State.Closed, "close must set state to Closed")
	defer free(s)
}
