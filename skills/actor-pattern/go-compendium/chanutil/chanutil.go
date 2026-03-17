// Package chanutil provides generic channel helpers for the actor pattern.
// Commands are sent via a typed channel; results come back on a per-command
// result channel. The recover() in each helper catches panics from sending
// on a closed channel, which happens when the actor has been stopped.
package chanutil

import "io"

// WithResult is implemented by command structs to attach a result channel.
// Use a value receiver so the caller's original struct is unmodified.
type WithResult[T any] interface {
	WithResult(c chan any) T
}

// SendReceive sends a command and waits for a typed result.
// Returns io.EOF if the commands channel is closed (actor stopped).
func SendReceive[C WithResult[C], K any](commands chan C, msg C) (result K, err error) {
	defer func() {
		if recover() != nil {
			err = io.EOF
		}
	}()
	re := make(chan any, 1)
	commands <- msg.WithResult(re)
	value := <-re
	switch v := value.(type) {
	case error:
		err = v
	case K:
		result = v
	}
	return
}

// SendReceiveError sends a command and waits for an error-only result.
func SendReceiveError[C WithResult[C]](commands chan C, msg C) (err error) {
	defer func() {
		if recover() != nil {
			err = io.EOF
		}
	}()
	re := make(chan any, 1)
	commands <- msg.WithResult(re)
	value := <-re
	if value == nil {
		return nil
	}
	if e, ok := value.(error); ok {
		return e
	}
	return nil
}
