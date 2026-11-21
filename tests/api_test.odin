package frostrig_tests

import testing "core:testing"
import "core:net"
import "core:sync"
import "core:time"
import "core:strings"
import "core:fmt"
import api "../api"

// ---------------------------------------------------------------------------
// unit: token / key store
// ---------------------------------------------------------------------------

@(test)
api_auth_login_verify_destroy :: proc(t: ^testing.T) {
	key := api.random_token()
	testing.expect(t, len(key) == api.TOKEN_LEN, "login key length")

	a: api.Auth_State
	api.auth_init(&a, key)

	tok, ok := api.auth_login(&a, "wrong-key")
	testing.expect(t, !ok, "wrong key must be rejected")
	testing.expect(t, tok == "", "no token on failure")

	tok, ok = api.auth_login(&a, key)
	testing.expect(t, ok, "correct key issues a token")
	testing.expect(t, len(tok) == api.TOKEN_LEN, "issued token length")
	testing.expect(t, api.auth_verify(&a, tok), "issued token verifies")
	testing.expect(t, !api.auth_verify(&a, "not-the-token"), "foreign token must fail")

	// single session: a second login invalidates the first
	tok2, ok2 := api.auth_login(&a, key)
	testing.expect(t, ok2, "second login succeeds")
	testing.expect(t, !api.auth_verify(&a, tok), "old token invalidated")
	testing.expect(t, api.auth_verify(&a, tok2), "new token verifies")

	// self-destruction rotates: old token dead, replacement minted
	rot := api.auth_destroy(&a)
	testing.expect(t, !api.auth_verify(&a, tok2), "destroyed token invalid")
	testing.expect(t, api.auth_verify(&a, rot), "rotated token valid")
	testing.expect(t, rot != tok2, "rotation mints a distinct token")
}

@(test)
api_auth_expiry :: proc(t: ^testing.T) {
	a: api.Auth_State
	api.auth_init(&a, "k")
	tok, ok := api.auth_login(&a, "k")
	testing.expect(t, ok, "login")

	sync.lock(&a.mu)
	a.token_issued = time.time_add(time.now(), -(api.TOKEN_TTL + time.Minute))
	sync.unlock(&a.mu)
	testing.expect(t, !api.auth_verify(&a, tok), "expired token must fail")
}

// ---------------------------------------------------------------------------
// unit: loopback / proxy classification
// ---------------------------------------------------------------------------

@(test)
api_loopback_classification :: proc(t: ^testing.T) {
	headers := map[string]string{}

	ep := net.Endpoint{address = net.IP4_Address{127, 0, 0, 1}, port = 1}
	testing.expect(t, api.is_loopback_noproxied(ep, headers), "loopback no proxy exempt")

	headers["x-forwarded-for"] = "1.2.3.4"
	testing.expect(t, !api.is_loopback_noproxied(ep, headers), "loopback but proxied not exempt")

	delete_key(&headers, "x-forwarded-for")
	ep2 := net.Endpoint{address = net.IP4_Address{192, 168, 1, 1}, port = 1}
	testing.expect(t, !api.is_loopback_noproxied(ep2, headers), "non-loopback not exempt")

	ep6 := net.Endpoint{address = net.IP6_Loopback, port = 1}
	testing.expect(t, api.is_loopback_noproxied(ep6, map[string]string{}), "ipv6 loopback exempt")
}

// ---------------------------------------------------------------------------
// integration: HTTP roundtrip over loopback
// ---------------------------------------------------------------------------

@(test)
api_http_roundtrip :: proc(t: ^testing.T) {
	key := "integration-login-key"
	a: api.Auth_State
	api.auth_init(&a, key)
	ctl: api.Runtime_Control
	api.control_init(&ctl, "stratum+tcp://old:1", "oldminer", "pass")

	srv := new(api.Api_Server)
	srv.auth = &a
	srv.control = &ctl
	serr := api.server_start(srv, net.Address(net.IP4_Loopback), 18082)
	testing.expect(t, serr == nil, "listen must succeed")
	defer api.server_stop(srv)
	time.sleep(150 * time.Millisecond)

	// login -> token
	resp := http_request(18082, "POST", "/login", strings.concatenate([]string{`{"key":"`, key, `"}`}), nil)
	testing.expect(t, strings.has_prefix(resp, "HTTP/1.1 200"), fmt.tprintf("login 200: %s", resp))
	tok := extract_json_string(resp, "token")
	testing.expect(t, tok != "", "login returns a token")

	// loopback + proxy header is NOT exempt -> 401 without a token
	resp401 := http_request(18082, "POST", "/config", `{"pool_url":"stratum+tcp://x:2"}`, []string{"X-Forwarded-For: 1.2.3.4"})
	testing.expect(t, strings.has_prefix(resp401, "HTTP/1.1 401"), fmt.tprintf("proxied loopback must 401: %s", resp401))

	// loopback direct is exempt -> config applies without a token
	resp2 := http_request(18082, "POST", "/config", `{"pool_url":"stratum+tcp://new:3333","miner_name":"newminer"}`, nil)
	testing.expect(t, strings.has_prefix(resp2, "HTTP/1.1 200"), fmt.tprintf("config 200: %s", resp2))
	_, _, _, reconnect := api.control_consume(&ctl)
	testing.expect(t, reconnect, "config raises pending")

	// self-destruction mints a fresh token
	resp3 := http_request(18082, "POST", "/token/destroy", `{}`, nil)
	testing.expect(t, strings.has_prefix(resp3, "HTTP/1.1 200"), fmt.tprintf("destroy 200: %s", resp3))
	nt := extract_json_string(resp3, "token")
	testing.expect(t, nt != "" && nt != tok, "destroy rotates the token")

	// unknown path -> 404
	resp4 := http_request(18082, "GET", "/nope", "", nil)
	testing.expect(t, strings.has_prefix(resp4, "HTTP/1.1 404"), fmt.tprintf("unknown path 404: %s", resp4))
}

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

http_request :: proc(port: int, method, path, body: string, headers: []string) -> string {
	sock, derr := net.dial_tcp_from_hostname_and_port_string(fmt.tprintf("127.0.0.1:%d", port))
	if derr != nil {
		return ""
	}
	defer net.close(sock)
	_ = net.set_option(sock, .Receive_Timeout, 5 * time.Second)
	_ = net.set_option(sock, .Send_Timeout, 5 * time.Second)

	parts: [dynamic]string
	defer delete(parts)
	append(&parts, fmt.tprintf("%s %s HTTP/1.1\r\nHost: 127.0.0.1:%d\r\nContent-Length: %d\r\n", method, path, port, len(body)))
	for h in headers {
		append(&parts, fmt.tprintf("%s\r\n", h))
	}
	append(&parts, "\r\n")
	append(&parts, body)
	req := strings.concatenate(parts[:])
	_, _ = net.send(sock, transmute([]byte)req)

	resp := make([dynamic]u8, 0, 2048)
	defer delete(resp)
	buf: [4096]u8
	for {
		n, _ := net.recv(sock, buf[:])
		if n <= 0 {
			break
		}
		append(&resp, ..buf[:n])
		if len(resp) > 1024 * 1024 {
			break
		}
	}
	return string(resp[:])
}

extract_json_string :: proc(s, key: string) -> string {
	pat := fmt.tprintf(`"%s":"`, key)
	i := strings.index(s, pat)
	if i < 0 {
		return ""
	}
	start := i + len(pat)
	j := strings.index(s[start:], `"`)
	if j < 0 {
		return ""
	}
	return s[start:start + j]
}
