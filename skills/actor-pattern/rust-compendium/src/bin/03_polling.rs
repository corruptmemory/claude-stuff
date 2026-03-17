//! Example 03: Polling Actor -- Timer-Based Background Work
//!
//! An actor that combines request-response commands with a background poller.
//! The poller uses sleep-after-work to avoid the cron-stampede problem.
//! Demonstrates:
//!   - Poller as a plain function spawning a thread
//!   - Poller lifecycle owned by the actor via a stop flag and JoinHandle
//!   - Poller sending commands on the actor's channel
//!   - Sleep after work completes (adaptive interval)
//!   - Shutdown via dropping all sender clones; poller checks its stop flag
//!
//! Run: cargo run --bin 03_polling

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{self, Sender};
use std::sync::Arc;
use std::thread;
use std::time::Duration;

// --- Command enum ---

enum Command {
    NewReading {
        value: f64,
        reply: Sender<()>,
    },
    Latest {
        reply: Sender<f64>,
    },
    History {
        reply: Sender<Vec<f64>>,
    },
}

// --- Poller ---
// A plain function, not a struct. It has no meaningful state beyond lifecycle
// coordination.

fn start_poller(
    read_sensor: fn() -> f64,
    cmd_tx: Sender<Command>,
    stop: Arc<AtomicBool>,
    interval: Duration,
) -> thread::JoinHandle<()> {
    thread::spawn(move || {
        while !stop.load(Ordering::Relaxed) {
            let reading = read_sensor();

            let (reply_tx, reply_rx) = mpsc::channel();
            // If the actor has shut down, send will fail -- just exit.
            if cmd_tx
                .send(Command::NewReading {
                    value: reading,
                    reply: reply_tx,
                })
                .is_err()
            {
                break;
            }
            // Wait for the actor to process it.
            let _ = reply_rx.recv();

            // Sleep AFTER work completes (adaptive interval).
            // Check stop flag in small increments to allow prompt shutdown.
            let steps = 10;
            let step_dur = interval / steps;
            for _ in 0..steps {
                if stop.load(Ordering::Relaxed) {
                    return;
                }
                thread::sleep(step_dur);
            }
        }
    })
}

// --- Actor handle ---

#[derive(Clone)]
struct SensorService {
    tx: Sender<Command>,
}

impl SensorService {
    fn new(read_sensor: fn() -> f64, poll_interval: Duration) -> Self {
        let (tx, rx) = mpsc::channel::<Command>();
        let poller_tx = tx.clone();

        let stop = Arc::new(AtomicBool::new(false));
        let poller_stop = stop.clone();

        // Start the poller thread.
        let poller_handle = start_poller(read_sensor, poller_tx, poller_stop, poll_interval);

        thread::spawn(move || {
            // All mutable state lives here.
            let mut readings: Vec<f64> = Vec::new();
            let mut latest: f64 = 0.0;

            while let Ok(cmd) = rx.recv() {
                match cmd {
                    Command::NewReading { value, reply } => {
                        latest = value;
                        readings.push(value);
                        let _ = reply.send(());
                    }
                    Command::Latest { reply } => {
                        let _ = reply.send(latest);
                    }
                    Command::History { reply } => {
                        let _ = reply.send(readings.clone());
                    }
                }
            }

            // Actor is shutting down -- stop the poller.
            stop.store(true, Ordering::Relaxed);
            let _ = poller_handle.join();
        });

        SensorService { tx }
    }

    fn latest(&self) -> f64 {
        let (reply_tx, reply_rx) = mpsc::channel();
        self.tx.send(Command::Latest { reply: reply_tx }).unwrap();
        reply_rx.recv().unwrap()
    }

    fn history(&self) -> Vec<f64> {
        let (reply_tx, reply_rx) = mpsc::channel();
        self.tx.send(Command::History { reply: reply_tx }).unwrap();
        reply_rx.recv().unwrap()
    }
}

// --- Simulated sensor ---

fn read_sensor() -> f64 {
    use std::collections::hash_map::DefaultHasher;
    use std::hash::{Hash, Hasher};
    // Pseudo-random based on thread id and time.
    let mut hasher = DefaultHasher::new();
    std::thread::current().id().hash(&mut hasher);
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos()
        .hash(&mut hasher);
    let hash = hasher.finish();
    // Map to 20.0..30.0 range.
    20.0 + (hash % 10000) as f64 / 1000.0
}

// --- Demo ---

fn main() {
    let svc = SensorService::new(read_sensor, Duration::from_millis(200));

    // Let the poller collect some readings.
    thread::sleep(Duration::from_secs(1));

    let latest = svc.latest();
    println!("Latest reading: {:.2}\u{00b0}C", latest);

    let history = svc.history();
    println!("Collected {} readings:", history.len());
    for (i, r) in history.iter().enumerate() {
        println!("  [{}] {:.2}\u{00b0}C", i, r);
    }

    // Dropping `svc` (and the contained Sender) shuts down the actor.
    // The actor thread then signals the poller to stop.
    drop(svc);

    // Give the background threads a moment to clean up.
    thread::sleep(Duration::from_millis(100));
    println!("Shutdown complete.");
}
