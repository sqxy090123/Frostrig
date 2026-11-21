package api

import "core:net"
import "core:thread"
import "core:time"
import "core:fmt"
import "core:strings"
import "core:encoding/json"
import "core:strconv"
import os "core:os"

// Api_Server owns the HTTP listener plus the shared auth and runtime-control
// state.  It runs on a background thread; the main loop drains Runtime_Control.
Api_Server :: struct {
	auth:     ^Auth_State,
	control:  ^Runtime_Control,
	listener: net.TCP_Socket,
	running:  bool,
}

// Conn is the per-connection context handed to the handler thread.
Conn :: struct {
	server: ^Api_Server,
	client: net.TCP_Socket,
	src:    net.Endpoint,
}

// server_start binds the listener and launches the accept loop.  It does not
// block.
server_start :: proc(server: ^Api_Server, host: net.Address, port: u16) -> (err: net.Network_Error) {
	ep := net.Endpoint{address = host, port = int(port)}
	server.listener, err = net.listen_tcp(ep)
	if err != nil {
		return err
	}
	server.running = true
	thread.run_with_poly_data(server, accept_loop)
	return nil
}

// server_stop closes the listener and stops the accept loop.
server_stop :: proc(server: ^Api_Server) {
	server.running = false
	net.close(server.listener)
}

accept_loop :: proc(server: ^Api_Server) {
	for server.running {
		client, src, aerr := net.accept_tcp(server.listener)
		if aerr != nil {
			if !server.running {
				break
			}
			continue
		}
		conn := Conn{server = server, client = client, src = src}
		thread.run_with_poly_data(conn, handle_conn)
	}
}

// handle_conn reads one HTTP/1.1 request, routes it, and closes the socket.
handle_conn :: proc(c: Conn) {
	defer net.close(c.client)
	_ = net.set_option(c.client, .Receive_Timeout, 10 * time.Second)
	_ = net.set_option(c.client, .Send_Timeout, 10 * time.Second)

	req, ok := read_request(c.client)
	if !ok {
		respond(c.client, 400, `{"ok":false,"error":"bad request"}`)
		return
	}
	defer delete(req.headers)

	// route
	if req.method == "POST" && req.path == "/login" {
		handle_login(c, req)
		return
	}
	if req.method == "POST" && req.path == "/config" {
		handle_config(c, req)
		return
	}
	if req.method == "POST" && req.path == "/token/destroy" {
		handle_destroy(c, req)
		return
	}
	respond(c.client, 404, `{"ok":false,"error":"not found"}`)
}

// ---------------------------------------------------------------------------
// Handlers
// ---------------------------------------------------------------------------

handle_login :: proc(c: Conn, req: Request) {
	Login_Req :: struct {
		key: string,
	}
	lr: Login_Req
	if json.unmarshal(req.body, &lr) != nil || lr.key == "" {
		respond(c.client, 400, `{"ok":false,"error":"bad login payload"}`)
		return
	}
	token, ok := auth_login(c.server.auth, lr.key)
	if !ok {
		respond(c.client, 401, `{"ok":false,"error":"invalid login key"}`)
		return
	}
	respond_json(c.client, 200, strings.concatenate([]string{`{"ok":true,"token":"`, token, `"}`}))
}

handle_config :: proc(c: Conn, req: Request) {
	if !authorized(c, req) {
		respond(c.client, 401, `{"ok":false,"error":"unauthorized"}`)
		return
	}
	Config_Req :: struct {
		pool_url:  string `json:"pool_url"`,
		miner_name: string `json:"miner_name"`,
	}
	cr: Config_Req
	if json.unmarshal(req.body, &cr) != nil {
		respond(c.client, 400, `{"ok":false,"error":"bad config payload"}`)
		return
	}
	if cr.pool_url == "" && cr.miner_name == "" {
		respond(c.client, 400, `{"ok":false,"error":"no fields to update"}`)
		return
	}
	control_apply(c.server.control, cr.pool_url, cr.miner_name)
	respond_json(c.client, 200, `{"ok":true}`)
}

handle_destroy :: proc(c: Conn, req: Request) {
	if !authorized(c, req) {
		respond(c.client, 401, `{"ok":false,"error":"unauthorized"}`)
		return
	}
	new_token := auth_destroy(c.server.auth)
	// The rotated token must reach the operator: print it to stdout.
	fmt.printfln("[frostrig-api] new token: %s", new_token)
	respond_json(c.client, 200, strings.concatenate([]string{`{"ok":true,"token":"`, new_token, `"}`}))
}

// ---------------------------------------------------------------------------
// Auth helpers
// ---------------------------------------------------------------------------

// authorized implements the loopback-non-proxy exemption, falling back to the
// token check for everything else.
authorized :: proc(c: Conn, req: Request) -> bool {
	if is_loopback_noproxied(c.src, req.headers) {
		return true
	}
	token := extract_token(req)
	if token == "" {
		return false
	}
	return auth_verify(c.server.auth, token)
}

// is_loopback_noproxied is true for a direct (non-forwarded) loopback peer.
is_loopback_noproxied :: proc(src: net.Endpoint, headers: map[string]string) -> bool {
	if header_present(headers, "X-Forwarded-For") ||
		header_present(headers, "Forwarded") ||
		header_present(headers, "X-Real-IP") ||
		header_present(headers, "Via") {
		return false
	}
	if a4, ok := src.address.(net.IP4_Address); ok {
		return a4[0] == 127
	}
	if a6, ok := src.address.(net.IP6_Address); ok {
		if a6 == net.IP6_Loopback {
			return true
		}
		// IPv4-mapped ::ffff:127.0.0.1
		if a6[0] == 0 && a6[1] == 0 && a6[2] == 0 && a6[3] == 0 &&
			a6[4] == 0 && a6[5] == 0xffff && (u16(a6[6]) >> 8) == 0x7f {
			return true
		}
	}
	return false
}

// extract_token pulls a token from Authorization: Bearer, X-Auth-Token, or the
// ?token= query parameter (in that order).
extract_token :: proc(req: Request) -> string {
	if v := req.headers["authorization"]; v != "" {
		if strings.has_prefix(v, "Bearer ") {
			return strings.trim_space(v[7:])
		}
		return strings.trim_space(v)
	}
	if v := req.headers["x-auth-token"]; v != "" {
		return strings.trim_space(v)
	}
	if q := query_param(req.path, "token"); q != "" {
		return q
	}
	return ""
}

header_present :: proc(headers: map[string]string, key: string) -> bool {
	// Keys are stored lowercased at parse time; compare without allocating.
	for k in headers {
		if strings.equal_fold(k, key) {
			return true
		}
	}
	return false
}

// query_param extracts the first value of `name` from a URL query string.
query_param :: proc(path: string, name: string) -> string {
	qidx := strings.index(path, "?")
	if qidx < 0 {
		return ""
	}
	query := path[qidx + 1:]
	for pair in strings.split(query, "&") {
		kv := strings.split(pair, "=")
		if len(kv) == 2 && kv[0] == name {
			return kv[1]
		}
	}
	return ""
}

// ---------------------------------------------------------------------------
// HTTP parsing / writing
// ---------------------------------------------------------------------------

Request :: struct {
	method:  string,
	path:    string,
	headers: map[string]string,
	body:    []u8,
}

read_request :: proc(client: net.TCP_Socket) -> (req: Request, ok: bool) {
	hdr := make([dynamic]u8, 0, 4096)
	defer delete(hdr)
	buf: [4096]u8
	header_end := -1
	for {
		n, err := net.recv(client, buf[:])
		if n <= 0 {
			return req, false
		}
		append(&hdr, ..buf[:n])
		header_end = find_header_end(hdr[:])
		if header_end >= 0 {
			break
		}
		if len(hdr) > 64 * 1024 {
			return req, false
		}
	}
	// split header block into lines
	head := hdr[:header_end]
	lines := strings.split(string(head), "\r\n")
	if len(lines) == 0 {
		return req, false
	}
	method, path, ok2 := parse_request_line(lines[0])
	if !ok2 {
		return req, false
	}
	// The header block lives in `hdr`, which is deleted when this proc returns.
	// Every string we hand back must therefore own its own memory: clone them.
	req.method = strings.clone(method)
	req.path = strings.clone(path)
	req.headers = make(map[string]string)
	for i in 1 ..< len(lines) {
		idx := strings.index(lines[i], ":")
		if idx <= 0 {
			continue
		}
		key := strings.clone(strings.trim_space(strings.to_lower(strings.trim_space(lines[i][:idx]))))
		val := strings.clone(strings.trim_space(lines[i][idx + 1:]))
		req.headers[key] = val
	}
	// read body.  Any body bytes that arrived in the same packet as the header
	// sit right after the \r\n\r\n terminator and must not be discarded.
	cl := 0
	if clv, ok := strconv.parse_int(req.headers["content-length"], 10); ok && clv > 0 {
		cl = clv
	}
	if cl > 0 {
		body := make([]u8, cl)
		pre := hdr[header_end + 4:]
		got := min(len(pre), cl)
		for i in 0 ..< got {
			body[i] = pre[i]
		}
		for got < cl {
			n, err := net.recv(client, body[got:])
			if n <= 0 {
				delete(req.headers)
				return req, false
			}
			got += n
		}
		req.body = body
	}
	return req, true
}

find_header_end :: proc(data: []u8) -> int {
	// locate first "\r\n\r\n"
	for i in 0 ..< len(data) {
		if i + 3 < len(data) &&
			data[i] == '\r' && data[i + 1] == '\n' &&
			data[i + 2] == '\r' && data[i + 3] == '\n' {
			return i
		}
	}
	return -1
}

parse_request_line :: proc(line: string) -> (method, path: string, ok: bool) {
	parts := strings.split(line, " ")
	if len(parts) < 3 {
		return "", "", false
	}
	return parts[0], parts[1], true
}

respond :: proc(client: net.TCP_Socket, status: int, body: string) {
	header := fmt.tprintf(
		"HTTP/1.1 %d %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n",
		status, status_text(status), len(body))
	_, _ = net.send(client, transmute([]byte)header)
	_, _ = net.send(client, transmute([]byte)body)
}

respond_json :: proc(client: net.TCP_Socket, status: int, body: string) {
	respond(client, status, body)
}

status_text :: proc(code: int) -> string {
	switch code {
	case 200:
		return "OK"
	case 400:
		return "Bad Request"
	case 401:
		return "Unauthorized"
	case 404:
		return "Not Found"
	case 405:
		return "Method Not Allowed"
	case 500:
		return "Internal Server Error"
	}
	return "Unknown"
}
