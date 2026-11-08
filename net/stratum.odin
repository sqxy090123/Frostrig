package frostrig_net

import core "../core"

connect :: proc(session: ^Session, endpoint: Endpoint) -> core.Error {
	if session == nil {
		return .Invalid_Argument
	}
	session.endpoint = endpoint
	session.state = .Connecting
	return .Not_Implemented
}

login :: proc(session: ^Session, user: string, pass: string) -> core.Error {
	if session == nil {
		return .Invalid_Argument
	}
	_ = user
	_ = pass
	return .Not_Implemented
}

submit :: proc(session: ^Session, share: core.Share) -> core.Error {
	if session == nil {
		return .Invalid_Argument
	}
	_ = share
	return .Not_Implemented
}

close :: proc(session: ^Session) -> core.Error {
	if session == nil {
		return .Invalid_Argument
	}
	session.state = .Closed
	return .Not_Implemented
}
