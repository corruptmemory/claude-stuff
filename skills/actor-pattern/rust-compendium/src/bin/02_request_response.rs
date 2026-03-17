//! Example 02: Request-Response Actor -- Key-Value Store
//!
//! A more realistic actor: an in-memory key-value store with Set, Get, Delete,
//! and Keys operations. Demonstrates:
//!   - Multiple payload fields embedded in command variants
//!   - Returning clones of data (not references to actor-owned state)
//!   - Error handling within the actor (key not found)
//!   - The handle struct is Clone-able for sharing across threads
//!
//! Run: cargo run --bin 02_request_response

use std::collections::HashMap;
use std::sync::mpsc::{self, Sender};
use std::thread;

// --- Command enum ---

enum Command {
    Set {
        key: String,
        value: String,
        reply: Sender<()>,
    },
    Get {
        key: String,
        reply: Sender<Result<String, String>>,
    },
    Delete {
        key: String,
        reply: Sender<()>,
    },
    Keys {
        reply: Sender<Vec<String>>,
    },
}

// --- Actor handle ---

#[derive(Clone)]
struct KVStore {
    tx: Sender<Command>,
}

impl KVStore {
    fn new() -> Self {
        let (tx, rx) = mpsc::channel::<Command>();

        thread::spawn(move || {
            // All mutable state lives here.
            let mut data: HashMap<String, String> = HashMap::new();

            while let Ok(cmd) = rx.recv() {
                match cmd {
                    Command::Set { key, value, reply } => {
                        data.insert(key, value);
                        let _ = reply.send(());
                    }
                    Command::Get { key, reply } => {
                        let result = match data.get(&key) {
                            Some(v) => Ok(v.clone()),
                            None => Err(format!("key not found: {:?}", key)),
                        };
                        let _ = reply.send(result);
                    }
                    Command::Delete { key, reply } => {
                        data.remove(&key);
                        let _ = reply.send(());
                    }
                    Command::Keys { reply } => {
                        let mut keys: Vec<String> = data.keys().cloned().collect();
                        keys.sort();
                        let _ = reply.send(keys);
                    }
                }
            }
        });

        KVStore { tx }
    }

    fn set(&self, key: &str, value: &str) {
        let (reply_tx, reply_rx) = mpsc::channel();
        self.tx
            .send(Command::Set {
                key: key.to_string(),
                value: value.to_string(),
                reply: reply_tx,
            })
            .unwrap();
        reply_rx.recv().unwrap();
    }

    fn get(&self, key: &str) -> Result<String, String> {
        let (reply_tx, reply_rx) = mpsc::channel();
        self.tx
            .send(Command::Get {
                key: key.to_string(),
                reply: reply_tx,
            })
            .unwrap();
        reply_rx.recv().unwrap()
    }

    fn delete(&self, key: &str) {
        let (reply_tx, reply_rx) = mpsc::channel();
        self.tx
            .send(Command::Delete {
                key: key.to_string(),
                reply: reply_tx,
            })
            .unwrap();
        reply_rx.recv().unwrap();
    }

    fn keys(&self) -> Vec<String> {
        let (reply_tx, reply_rx) = mpsc::channel();
        self.tx.send(Command::Keys { reply: reply_tx }).unwrap();
        reply_rx.recv().unwrap()
    }
}

// --- Demo ---

fn main() {
    let store = KVStore::new();

    // Set some values from multiple threads.
    let pairs = vec![
        ("name", "Alice"),
        ("city", "Portland"),
        ("lang", "Rust"),
        ("editor", "Emacs"),
    ];

    let mut handles = Vec::new();
    for (k, v) in &pairs {
        let s = store.clone();
        let key = k.to_string();
        let val = v.to_string();
        handles.push(thread::spawn(move || {
            s.set(&key, &val);
        }));
    }
    for h in handles {
        h.join().unwrap();
    }

    // Read them back.
    for (k, _) in &pairs {
        match store.get(k) {
            Ok(v) => println!("{} = {}", k, v),
            Err(e) => println!("get {:?}: error: {}", k, e),
        }
    }

    // Try a missing key.
    match store.get("nonexistent") {
        Ok(v) => println!("nonexistent = {}", v),
        Err(e) => println!("missing key error: {}", e),
    }

    // Delete and verify.
    store.delete("city");
    let keys = store.keys();
    println!("keys after delete: {:?}", keys);
}
