// Example 03: Polling Actor — Timer-Based Background Work
//
// An actor that combines request-response commands with a background poller.
// The poller uses time.NewTimer (not Ticker) with reset-after-work to avoid
// the cron-stampede problem. Demonstrates:
//   - Poller as a plain function (not a struct)
//   - Poller lifecycle owned by run() via done channel and WaitGroup
//   - Poller sending commands on the actor's channel
//   - Timer.Reset after work completes (adaptive interval)
//
// Run: go run ./03_polling
package main

import (
	"fmt"
	"math/rand/v2"
	"sync"
	"time"

	"actor-examples/chanutil"
)

// --- Public interface ---

type SensorService interface {
	Latest() (float64, error)
	History() ([]float64, error)
	Stop()
	Wait()
}

// --- Command tags ---

type commandTag int

const (
	cmdNewReading commandTag = iota
	cmdLatest
	cmdHistory
)

// --- Command struct ---

type sensorCommand struct {
	tag     commandTag
	reading float64
	result  chan any
}

func (c sensorCommand) WithResult(ch chan any) sensorCommand {
	c.result = ch
	return c
}

// --- Poller ---
// A plain function, not a struct. It has no meaningful state beyond lifecycle
// coordination, and run() already owns that via a WaitGroup and done channel.

func startPoller(wg *sync.WaitGroup, readSensor func() float64, commands chan<- sensorCommand, done <-chan struct{}, interval time.Duration) {
	wg.Add(1)
	go func() {
		defer wg.Done()

		timer := time.NewTimer(0) // fire immediately for initial reading
		defer timer.Stop()

		for {
			select {
			case <-done:
				return
			case <-timer.C:
			}

			reading := readSensor()

			// Send the reading to the actor via the command channel.
			re := make(chan any, 1)
			select {
			case commands <- sensorCommand{tag: cmdNewReading, reading: reading, result: re}:
				<-re // wait for actor to process
			case <-done:
				return
			}

			timer.Reset(interval) // interval measured from END of work
		}
	}()
}

// --- Unexported implementation ---

type sensorService struct {
	commands chan sensorCommand
	done     chan struct{}
	wg       sync.WaitGroup
}

func NewSensorService(readSensor func() float64, pollInterval time.Duration) SensorService {
	s := &sensorService{
		commands: make(chan sensorCommand, 64),
		done:     make(chan struct{}),
	}
	s.wg.Add(1)
	go s.run(readSensor, pollInterval)
	return s
}

func (s *sensorService) run(readSensor func() float64, pollInterval time.Duration) {
	// --- All mutable state lives here ---
	var readings []float64
	latest := 0.0

	// Start the poller — its lifecycle is owned by this function.
	var pollerWg sync.WaitGroup
	pollerDone := make(chan struct{})
	startPoller(&pollerWg, readSensor, s.commands, pollerDone, pollInterval)

	defer func() {
		close(pollerDone)  // signal poller to stop
		pollerWg.Wait()    // wait for it to exit
		s.wg.Done()
	}()

	// --- Handler closures ---

	handleNewReading := func(msg sensorCommand) {
		latest = msg.reading
		readings = append(readings, msg.reading)
		msg.result <- error(nil)
	}

	handleLatest := func(msg sensorCommand) {
		msg.result <- latest
	}

	handleHistory := func(msg sensorCommand) {
		// Return a copy.
		cp := make([]float64, len(readings))
		copy(cp, readings)
		msg.result <- cp
	}

	// --- Dispatch loop ---

	for {
		var msg sensorCommand
		select {
		case <-s.done:
			return
		case msg = <-s.commands:
		}

		switch msg.tag {
		case cmdNewReading:
			handleNewReading(msg)
		case cmdLatest:
			handleLatest(msg)
		case cmdHistory:
			handleHistory(msg)
		}
		close(msg.result)
	}
}

// --- Public methods ---

func (s *sensorService) Latest() (float64, error) {
	return chanutil.SendReceive[sensorCommand, float64](s.commands, sensorCommand{
		tag: cmdLatest,
	})
}

func (s *sensorService) History() ([]float64, error) {
	return chanutil.SendReceive[sensorCommand, []float64](s.commands, sensorCommand{
		tag: cmdHistory,
	})
}

func (s *sensorService) Stop() {
	defer func() { recover() }()
	close(s.done)
}

func (s *sensorService) Wait() {
	s.wg.Wait()
}

// --- Demo ---

func main() {
	// Simulate a sensor that returns random temperatures.
	readSensor := func() float64 {
		return 20.0 + rand.Float64()*10.0
	}

	svc := NewSensorService(readSensor, 200*time.Millisecond)
	defer func() { svc.Stop(); svc.Wait() }()

	// Let the poller collect some readings.
	time.Sleep(1 * time.Second)

	latest, err := svc.Latest()
	if err != nil {
		fmt.Printf("error: %v\n", err)
		return
	}
	fmt.Printf("Latest reading: %.2f°C\n", latest)

	history, err := svc.History()
	if err != nil {
		fmt.Printf("error: %v\n", err)
		return
	}
	fmt.Printf("Collected %d readings:\n", len(history))
	for i, r := range history {
		fmt.Printf("  [%d] %.2f°C\n", i, r)
	}
}
