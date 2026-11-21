# Requirements Document

## Introduction

Frostrig SHALL expose a local HTTP API (`frostrig-api`) through which an
authenticated user can modify the mining pool URL and the miner name at
runtime.  Access control uses a token scheme: loopback non-proxied requests
are exempt; every other request must present a random 64-character token that
is verified by SHA-256 comparison, expires 30 minutes after issuance, and
admits only one concurrent login.  The token account supports self-destruction,
after which a new token is printed to stdout.

## Glossary

- **API**: the HTTP server exposed by frostrig on `0.0.0.0:18081`.
- **Login key**: a random 64-character string, charset `0-9a-zA-Z_\-+&`,
  generated at startup and printed to stdout; the credential accepted by `/login`.
- **Token**: a random 64-character string, same charset, issued by `/login` and
  required for authenticated requests.
- **Loopback**: a request whose source address is `127.0.0.0/8` or `::1`.
- **Proxy indicator**: a request carrying `X-Forwarded-For`, `Forwarded`,
  `X-Real-IP`, or `Via` header, i.e. forwarded by an intermediary.
- **Authenticated request**: a request that is loopback-non-proxied, or that
  presents a valid, unexpired token.

## Requirements

### Requirement 1: API exposure

**User Story:** AS an administrator, I want frostrig to expose an HTTP API, so
that I can reconfigure the pool and miner name without restarting the miner.

#### Acceptance Criteria

1. THE API SHALL listen on `0.0.0.0:18081`.
2. THE API SHALL serve HTTP/1.1 requests.
3. THE API SHALL expose the endpoints `/login`, `/config`, and `/token/destroy`.

### Requirement 2: Loopback non-proxy exemption

**User Story:** AS an administrator running frostrig locally, I want direct
local requests to skip authentication, so that local tooling can reconfigure
without tokens.

#### Acceptance Criteria

1. WHEN a request is loopback AND carries no proxy indicator, the system SHALL
   treat it as authenticated.
2. WHEN a request is non-loopback OR carries a proxy indicator, the system
   SHALL require a valid token.

### Requirement 3: Token authentication

**User Story:** AS an administrator, I want remote API access to be
authenticated, so that only a holder of a valid token can modify the miner.

#### Acceptance Criteria

1. THE system SHALL verify a presented token by comparing the SHA-256 digest of
   the presented token against the stored digest.
2. WHEN verification fails, the system SHALL respond `401 Unauthorized`.
3. WHEN verification succeeds and the token is unexpired, the system SHALL
   authorize the request.

### Requirement 4: Login key

**User Story:** AS an administrator, I want a startup-generated login key, so
that I can authenticate to obtain a token.

#### Acceptance Criteria

1. AT STARTUP, the system SHALL generate a random 64-character key drawn from
   charset `0-9a-zA-Z_\-+&` and print it to stdout.
2. THE system SHALL store only the SHA-256 digest of the login key, never the
   plaintext key.

### Requirement 5: Login

**User Story:** AS an administrator holding the login key, I want to obtain a
token, so that I can make authenticated API calls.

#### Acceptance Criteria

1. WHEN a request to `/login` presents a value whose SHA-256 digest equals the
   stored login-key digest, the system SHALL issue a token valid for 30 minutes.
2. WHEN a request to `/login` presents a non-matching value, the system SHALL
   respond `401 Unauthorized`.
3. THE system SHALL allow at most one active token: issuing a new token SHALL
   invalidate the previously active token.

### Requirement 6: Token lifetime

**User Story:** AS an administrator, I want tokens to expire, so that a leaked
token does not grant access forever.

#### Acceptance Criteria

1. A TOKEN SHALL expire 30 minutes after issuance.
2. WHEN an expired token is presented, the system SHALL respond
   `401 Unauthorized`.

### Requirement 7: Self-destruction

**User Story:** AS an administrator, I want to destroy my token account, so
that I can rotate credentials.

#### Acceptance Criteria

1. WHEN an authenticated request calls `/token/destroy`, the system SHALL
   invalidate the current token.
2. AFTER invalidation, the system SHALL generate a new token, print it to
   stdout, and respond with success.
3. THE newly printed token SHALL be valid for 30 minutes.

### Requirement 8: Runtime modification

**User Story:** AS an administrator, I want to change the pool and miner name
at runtime, so that I can point the miner at a different pool or identity
without restarting.

#### Acceptance Criteria

1. WHEN an authenticated request modifies the pool URL, the system SHALL close
   the current stratum connection, connect to the new URL, and re-login.
2. WHEN an authenticated request modifies the miner name, the system SHALL
   re-login to the pool using the new name.
3. MODIFICATIONS SHALL apply at runtime only and SHALL NOT be persisted to
   disk.
