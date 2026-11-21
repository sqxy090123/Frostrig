package frostrig_gui

import algo "../algo"
import "core:net"
import "core:thread"
import "core:time"
import "core:fmt"
import "core:strings"
import os "core:os"

// GUI_PORT is the port the 3D viewer listens on when --gui-port is not given.
// It sits away from frostrig-api's 18081 so the two servers can run together.
GUI_PORT :: u16(18090)

Gui_Server :: struct {
	state:    ^algo.Gui_State,
	listener: net.TCP_Socket,
	running:  bool,
	port:     u16,
	// token is a per-process secret embedded in the served page; /gui/trace
	// only answers a request that echoes it, so walk coordinates are not
	// exposed to a scanner that never loaded the viewer.
	token: string,
}

// Gui_Conn is the per-connection context handed to a handler thread.
Gui_Conn :: struct {
	server: ^Gui_Server,
	client: net.TCP_Socket,
}

Gui_Trace :: struct {
	rows:   u32,
	cols:   u32,
	layers: u32,
	cell:   u32,
	steps:  u64,
	hashes: u64,
	stride: u32,
	trail:  []algo.Worm2_Cell,
}

// Trace_Json renders one snapshot as the compact JSON the viewer polls into a
// caller-owned buffer: returning a freshly concatenated string made every poll
// an allocation the request loop had to remember to free.  The trail array runs
// oldest-first so the page can fade it straight through.
Trace_Json :: proc(s: ^algo.Gui_State, out: ^[dynamic]u8) -> string {
	v := algo.Gui_Snapshot(s)
	joins := make([dynamic]string, 0, 32)
	defer delete(joins)
	append(&joins, `{"rows":`)
	append(&joins, fmt.tprintf("%d", int(v.rows)))
	append(&joins, `,"cols":`)
	append(&joins, fmt.tprintf("%d", int(v.cols)))
	append(&joins, `,"layers":`)
	append(&joins, fmt.tprintf("%d", int(v.layers)))
	append(&joins, `,"cell":`)
	append(&joins, fmt.tprintf("%d", int(v.cell)))
	append(&joins, `,"steps":`)
	append(&joins, fmt.tprintf("%d", int(v.steps)))
	append(&joins, `,"hashes":`)
	append(&joins, fmt.tprintf("%d", int(v.hashes)))
	append(&joins, `,"stride":`)
	append(&joins, fmt.tprintf("%d", int(v.stride)))
	append(&joins, `,"trail":[`)
	for i in 0 ..< int(v.count) {
		c := v.trail[i]
		if i > 0 {
			append(&joins, ",")
		}
		append(&joins, `{"x":`)
		append(&joins, fmt.tprintf("%d", int(c.x)))
		append(&joins, `,"y":`)
		append(&joins, fmt.tprintf("%d", int(c.y)))
		append(&joins, `,"z":`)
		append(&joins, fmt.tprintf("%d", int(c.z)))
		append(&joins, "}")
	}
	append(&joins, "]}")
	// copy straight into the caller's buffer so no string has to be allocated and
	// later remembered for freeing
	for i in 0 ..< len(joins) {
		append(out, ..transmute([]u8)joins[i])
	}
	return string(out[:])
}

// start binds the listener and launches the accept loop.  The state pointer is
// handed in here rather than kept in a package global so two viewers could
// coexist if that ever becomes useful.
start :: proc(s: ^Gui_Server, state: ^algo.Gui_State,
	host: net.Address, port: u16) -> (err: net.Network_Error) {
	s.state = state
	s.token = new_token()
	ep := net.Endpoint{address = host, port = int(port)}
	s.listener, err = net.listen_tcp(ep)
	if err != nil {
		return err
	}
	s.port = port
	s.running = true
	thread.run_with_poly_data(s, accept_loop)
	return nil
}

stop :: proc(s: ^Gui_Server) {
	if s == nil {
		return
	}
	s.running = false
	net.close(s.listener)
	if s.token != "" {
		delete(s.token)
	}
	s.token = ""
}

// new_token draws TOKEN_HEX_LEN hex characters from /dev/urandom.  Hex is
// chosen so the value embeds safely in the served page's JS and in a header
// value with no escaping.  The caller owns the returned string.
new_token :: proc() -> string {
	TOKEN_HEX_LEN :: 32
	buf := make([]u8, TOKEN_HEX_LEN)
	defer delete(buf)
	f, _ := os.open("/dev/urandom", os.File_Flags{.Read})
	if f != nil {
		defer os.close(f)
		_, _ = os.read(f, buf)
	}
	hexchars := "0123456789abcdef"
	tok := make([]u8, TOKEN_HEX_LEN)
	for i in 0 ..< TOKEN_HEX_LEN {
		tok[i] = hexchars[int(buf[i]) & 0xf]
	}
	return string(tok)
}

accept_loop :: proc(s: ^Gui_Server) {
	for s.running {
		client, _, aerr := net.accept_tcp(s.listener)
		if aerr != nil {
			if !s.running {
				break
			}
			continue
		}
		conn := Gui_Conn{server = s, client = client}
		thread.run_with_poly_data(conn, handle_conn)
	}
}

// handle_conn serves exactly one request per socket: the viewer is a
// poll-and-close client, so a keep-alive state machine buys nothing here.
handle_conn :: proc(c: Gui_Conn) {
	_ = net.set_option(c.client, .Receive_Timeout, 5 * time.Second)
	_ = net.set_option(c.client, .Send_Timeout, 5 * time.Second)
	defer net.close(c.client)

	// one scratch buffer per connection keeps the trace body free of allocations
	scratch := make([dynamic]u8, 0, 1024)
	defer delete(scratch)
	// the request target is copied into its own small buffer so the trace body
	// below can reuse the scratch buffer without invalidating the route path
	path_buf := make([dynamic]u8, 0, 256)
	defer delete(path_buf)
	token_buf := make([dynamic]u8, 0, 128)
	defer delete(token_buf)

	path := read_request_line(c.client, &path_buf, &token_buf)
	if path == "" {
		respond(c.client, 400, "application/json", `{"ok":false,"error":"bad request"}`)
		return
	}
	if path == "/gui/trace" {
		// the walk coordinates are only for the viewer that loaded the page and
		// got the per-process token; anything else is refused rather than leaked
		if string(token_buf[:]) != c.server.token {
			respond(c.client, 403, "application/json", `{"ok":false,"error":"forbidden"}`)
			return
		}
		respond(c.client, 200, "application/json", Trace_Json(c.server.state, &scratch))
		return
	}
	if path == "/favicon.ico" {
		respond(c.client, 204, "image/x-icon", "")
		return
	}
	if path == "/" || path == "/index.html" {
		respond(c.client, 200, "text/html; charset=utf-8", page_html(c.server.token))
		return
	}
	respond(c.client, 404, "application/json", `{"ok":false,"error":"not found"}`)
}

// read_request_line pulls the request target and the viewer token out of a GET
// line and its headers, returning an empty string for anything else
// (unsupported method, no request yet, or a header block that blew past a
// plausible size).  The target is copied into `out`, which the caller owns and
// must keep alive past the route dispatch: slicing the scratch header directly
// would dangle once that buffer is freed.
read_request_line :: proc(client: net.TCP_Socket, out: ^[dynamic]u8,
	token_out: ^[dynamic]u8) -> string {
	clear(out)
	clear(token_out)
	buf: [4096]u8
	hdr := make([dynamic]u8, 0, 4096)
	defer delete(hdr)
	end := -1
	for {
		n, err := net.recv(client, buf[:])
		if n <= 0 {
			return ""
		}
		append(&hdr, ..buf[:n])
		if end < 0 {
			end = strings.index(string(hdr[:]), "\r\n\r\n")
		}
		if end >= 0 {
			break
		}
		if len(hdr) > 8192 {
			return ""
		}
	}
	// `end` marks the blank line that closes the header block; the request line
	// itself stops at the *first* CRLF, so the target cannot be mangled by an
	// oversized Host header.
	first := strings.index(string(hdr[:]), "\r\n")
	if first < 0 {
		first = len(hdr)
	}
	line := string(hdr[:first])
	if !strings.has_prefix(line, "GET ") {
		return ""
	}
	// target spans from after "GET " to the next space; index it directly so no
	// []string and no format string are built per request
	sp := strings.index(line[4:], " ")
	if sp < 0 {
		return ""
	}
	target := line[4:4+sp]
	if len(target) == 0 {
		return ""
	}
	append(out, ..transmute([]u8)target)
	// the viewer proves it loaded the page by echoing the token it found in a
	// script tag; this keeps a stray scanner from reading walk coordinates
	// without first pulling the document
	header_block := string(hdr[:end])
	ti := strings.index(header_block, "X-Trace-Token:")
	if ti >= 0 {
		tv := header_block[ti+len("X-Trace-Token:"):]
		tv = strings.trim_left_space(tv)
		tline := strings.index(tv, "\r\n")
		if tline >= 0 {
			tv = tv[:tline]
		}
		append(token_out, ..transmute([]u8)tv)
	}
	return string(out[:])
}

respond :: proc(client: net.TCP_Socket, status: int, ctype: string, body: string) {
	header := fmt.tprintf("HTTP/1.1 %d %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n",
		status, status_text(status), ctype, len(body))
	_, _ = net.send(client, transmute([]byte)header)
	if len(body) > 0 {
		_, _ = net.send(client, transmute([]byte)body)
	}
}

status_text :: proc(code: int) -> string {
	switch code {
	case 200:
		return "OK"
	case 204:
		return "No Content"
	case 400:
		return "Bad Request"
	case 403:
		return "Forbidden"
	case 404:
		return "Not Found"
	case 500:
		return "Internal Server Error"
	}
	return "Unknown"
}
