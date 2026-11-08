package frostrig_tests

import testing "core:testing"
import worker "../worker"
import core "../core"

@(test)
queue_empty_returns_queue_empty :: proc(t: ^testing.T) {
	q: worker.Job_Queue
	_, err := worker.dequeue(&q)
	testing.expect(t, err == core.Error.Queue_Empty, "dequeue from empty queue must return Queue_Empty")
}

@(test)
queue_full_returns_queue_full :: proc(t: ^testing.T) {
	q: worker.Job_Queue
	for i in 0 ..< worker.MAX_QUEUE {
		j: core.Job
		j.id = 0
		j.algo = core.Algo_Id(i)
		err := worker.enqueue(&q, j)
		testing.expect(t, err == core.Error.None, "enqueue below capacity must succeed")
	}
	full: core.Job
	err := worker.enqueue(&q, full)
	testing.expect(t, err == core.Error.Queue_Full, "enqueue at capacity must return Queue_Full")
}
