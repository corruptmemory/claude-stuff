//! Example 01: Basic Actor -- Counter
//!
//! The simplest possible actor: a counter that multiple threads can safely
//! increment and read without locks. Demonstrates:
//!   - Command enum with variants carrying one-shot `Sender<Reply>` for responses
//!   - `std::sync::mpsc::channel()` for command and reply channels
//!   - The actor thread owning all mutable state
//!   - Clone-able handle struct wrapping `Sender<Command>`
//!   - Shutdown via dropping all sender clones
//!
//! Run: cargo run --bin 01_basic_actor

use std::sync::mpsc::{self, Sender};
use std::thread;

// --- Command enum ---

enum Command {
    Increment { reply: Sender<()> },
    Get { reply: Sender<i64> },
}

// --- Actor handle ---

#[derive(Clone)]
struct Counter {
    tx: Sender<Command>,
}

impl Counter {
    fn new() -> Self {
        let (tx, rx) = mpsc::channel::<Command>();

        thread::spawn(move || {
            // All mutable state lives here.
            let mut count: i64 = 0;

            while let Ok(cmd) = rx.recv() {
                match cmd {
                    Command::Increment { reply } => {
                        count += 1;
                        let _ = reply.send(());
                    }
                    Command::Get { reply } => {
                        let _ = reply.send(count);
                    }
                }
            }
        });

        Counter { tx }
    }

    fn increment(&self) {
        let (reply_tx, reply_rx) = mpsc::channel();
        self.tx.send(Command::Increment { reply: reply_tx }).unwrap();
        reply_rx.recv().unwrap();
    }

    fn get(&self) -> i64 {
        let (reply_tx, reply_rx) = mpsc::channel();
        self.tx.send(Command::Get { reply: reply_tx }).unwrap();
        reply_rx.recv().unwrap()
    }
}

// --- Demo ---

fn main() {
    let counter = Counter::new();

    // Spawn 10 threads that each increment 100 times.
    let mut handles = Vec::new();
    for _ in 0..10 {
        let c = counter.clone();
        handles.push(thread::spawn(move || {
            for _ in 0..100 {
                c.increment();
            }
        }));
    }
    for h in handles {
        h.join().unwrap();
    }

    let val = counter.get();
    println!("Final count: {} (expected 1000)", val);
}
