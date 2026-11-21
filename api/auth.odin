package api

import "core:crypto/sha2"
import "core:sync"
import "core:time"
import os "core:os"

// Token / login-key alphabet and length.  A 64-character draw from this 66
// symbol charset yields ~385 bits of entropy, comfortably beyond a 64-bit
// brute force and collision space.
TOKEN_CHARSET :: "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_-+&"
TOKEN_LEN :: 64

// TOKEN_TTL is the validity window a token stays usable after issuance.
TOKEN_TTL :: 30 * time.Minute

// sha256_of writes sha256(data) into dst (len >= 32).
sha256_of :: proc(data: []u8, dst: []u8) {
	ctx: sha2.Context_256
	sha2.init_256(&ctx)
	sha2.update(&ctx, data)
	sha2.final(&ctx, dst)
}

// random_token draws TOKEN_LEN characters from TOKEN_CHARSET using
// /dev/urandom.  The caller owns the returned string.
random_token :: proc() -> string {
	buf := make([]u8, TOKEN_LEN)
	f, _ := os.open("/dev/urandom", os.File_Flags{.Read})
	if f != nil {
		defer os.close(f)
		_, _ = os.read(f, buf)
	}
	charset := TOKEN_CHARSET
	for i in 0 ..< TOKEN_LEN {
		buf[i] = charset[int(buf[i]) % len(charset)]
	}
	return string(buf)
}

// Auth_State is the single-slot credential store.  The login key is stored
// only as its SHA-256 digest; the active token likewise.  At most one token is
// live at a time (issuing a new one invalidates the previous).
Auth_State :: struct {
	mu:            sync.Mutex,
	login_key_hash: [32]u8,
	token_hash:    [32]u8,
	token_issued:  time.Time,
	token_valid:   bool,
}

// auth_init records the startup login key (plaintext is discarded; only its
// digest is retained) and clears any previous token.
auth_init :: proc(a: ^Auth_State, login_key: string) {
	sync.lock(&a.mu)
	defer sync.unlock(&a.mu)
	sha256_of(transmute([]byte)login_key, a.login_key_hash[:])
	a.token_valid = false
}

// auth_login validates `presented` against the stored login-key digest.  On a
// match it invalidates any previous token and issues a fresh one.
auth_login :: proc(a: ^Auth_State, presented: string) -> (token: string, ok: bool) {
	sync.lock(&a.mu)
	defer sync.unlock(&a.mu)
	h: [32]u8
	sha256_of(transmute([]byte)presented, h[:])
	if !bytes_equal(h[:], a.login_key_hash[:]) {
		return "", false
	}
	token = random_token()
	sha256_of(transmute([]byte)token, a.token_hash[:])
	a.token_issued = time.now()
	a.token_valid = true
	return token, true
}

// auth_verify reports whether `token` is the active, unexpired token.
auth_verify :: proc(a: ^Auth_State, token: string) -> bool {
	sync.lock(&a.mu)
	defer sync.unlock(&a.mu)
	if !a.token_valid {
		return false
	}
	if time.since(a.token_issued) > TOKEN_TTL {
		a.token_valid = false
		return false
	}
	h: [32]u8
	sha256_of(transmute([]byte)token, h[:])
	return bytes_equal(h[:], a.token_hash[:])
}

// auth_destroy invalidates the current token and mints a replacement that the
// caller must print to stdout.  The replacement is immediately valid for
// TOKEN_TTL.
auth_destroy :: proc(a: ^Auth_State) -> string {
	sync.lock(&a.mu)
	defer sync.unlock(&a.mu)
	a.token_valid = false
	token := random_token()
	sha256_of(transmute([]byte)token, a.token_hash[:])
	a.token_issued = time.now()
	a.token_valid = true
	return token
}

// bytes_equal compares two byte slices with constant-ish structure.
bytes_equal :: proc(a, b: []u8) -> bool {
	if len(a) != len(b) {
		return false
	}
	for i in 0 ..< len(a) {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}
