package frostrig_worker

import core "../core"

MAX_QUEUE :: 64

Job_Queue :: struct {
	items: [MAX_QUEUE]core.Job,
	head:  int,
	tail:  int,
	len:   int,
}

enqueue :: proc(q: ^Job_Queue, job: core.Job) -> core.Error {
	if q == nil {
		return .Invalid_Argument
	}
	if q.len >= MAX_QUEUE {
		return .Queue_Full
	}
	q.items[q.tail] = job
	q.tail = (q.tail + 1) % MAX_QUEUE
	q.len += 1
	return .None
}

dequeue :: proc(q: ^Job_Queue) -> (job: core.Job, err: core.Error) {
	if q == nil {
		return {}, .Invalid_Argument
	}
	if q.len == 0 {
		return {}, .Queue_Empty
	}
	job = q.items[q.head]
	q.head = (q.head + 1) % MAX_QUEUE
	q.len -= 1
	return job, .None
}
