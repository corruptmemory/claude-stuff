//! Example 04: Actor Hierarchy -- Coordinator with Sub-Actors
//!
//! A coordinator (Application) manages sub-actors representing distinct
//! operational modes. Demonstrates:
//!   - SubActor trait (analogous to Go's Stoppable interface)
//!   - StateBuilder type alias for deferred actor construction
//!   - Coordinator that owns one sub-actor at a time
//!   - Fire-and-forget SetState (avoids the deadlock trap)
//!   - RecoverableError for graceful fallback chains
//!   - ErrorApp as terminal state
//!   - Sub-actor triggering its own replacement
//!   - Coordinator forwarding typed queries to the current sub-actor
//!
//! Run: cargo run --bin 04_actor_hierarchy

use std::sync::mpsc::{self, Sender};
use std::thread;
use std::time::{Duration, Instant};

// ============================================================================
// Core Abstractions
// ============================================================================

/// Common interface for all managed sub-actors.
trait SubActor: Send {
    /// Signal the sub-actor to stop and wait for its thread to finish.
    fn stop_and_join(&mut self);

    /// Describe the current state for display.
    fn describe(&self) -> StateDescription;

    /// Try to advance (only meaningful for SetupMode, others return None).
    fn try_advance(&self) -> Option<Result<(), String>> {
        None
    }
}

/// What the coordinator returns when asked about current state.
#[derive(Debug)]
enum StateDescription {
    Setup { step: i32 },
    Running { status: String, config: String },
    Error { msg: String },
}

/// Defers actor construction until the coordinator calls it.
type StateBuilder = Box<dyn FnOnce(&AppHandle) -> Result<Box<dyn SubActor>, BuildError> + Send>;

/// An error that optionally carries a fallback builder.
struct BuildError {
    msg: String,
    fallback: Option<StateBuilder>,
}

impl std::fmt::Display for BuildError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.msg)
    }
}

/// Try the builder, then one level of recovery, then ErrorApp.
fn build_state(app: &AppHandle, builder: StateBuilder) -> Box<dyn SubActor> {
    match builder(app) {
        Ok(actor) => actor,
        Err(BuildError {
            fallback: Some(next),
            msg,
        }) => {
            println!(
                "[Coordinator] Primary failed ({}), trying fallback...",
                msg
            );
            match next(app) {
                Ok(actor) => actor,
                Err(e) => Box::new(ErrorApp::new(e.msg)),
            }
        }
        Err(e) => Box::new(ErrorApp::new(e.msg)),
    }
}

// ============================================================================
// ErrorApp -- Terminal State
// ============================================================================

struct ErrorApp {
    err: String,
}

impl ErrorApp {
    fn new(err: String) -> Self {
        ErrorApp { err }
    }
}

impl SubActor for ErrorApp {
    fn stop_and_join(&mut self) {}

    fn describe(&self) -> StateDescription {
        StateDescription::Error {
            msg: self.err.clone(),
        }
    }
}

// ============================================================================
// Coordinator (Application)
// ============================================================================

enum AppCommand {
    /// Synchronous -- returns a description of the current state.
    GetState {
        reply: Sender<StateDescription>,
    },
    /// Synchronous -- advance the current sub-actor if it supports it.
    AdvanceSetup {
        reply: Sender<Option<Result<(), String>>>,
    },
    /// Fire-and-forget -- no reply channel. Critical to avoid deadlock
    /// when a sub-actor triggers its own replacement.
    SetState {
        builder: StateBuilder,
    },
}

/// Clone-able handle for interacting with the coordinator.
#[derive(Clone)]
struct AppHandle {
    tx: Sender<AppCommand>,
}

impl AppHandle {
    fn new(initial: StateBuilder) -> Self {
        let (tx, rx) = mpsc::channel::<AppCommand>();
        let handle = AppHandle { tx };
        let handle_for_thread = handle.clone();

        thread::spawn(move || {
            let mut current: Box<dyn SubActor> = build_state(&handle_for_thread, initial);

            while let Ok(cmd) = rx.recv() {
                match cmd {
                    AppCommand::GetState { reply } => {
                        let _ = reply.send(current.describe());
                    }
                    AppCommand::AdvanceSetup { reply } => {
                        let _ = reply.send(current.try_advance());
                    }
                    AppCommand::SetState { builder } => {
                        current.stop_and_join();
                        current = build_state(&handle_for_thread, builder);
                    }
                }
            }

            // Channel closed -- shut down current sub-actor.
            current.stop_and_join();
        });

        handle
    }

    fn get_state(&self) -> StateDescription {
        let (reply_tx, reply_rx) = mpsc::channel();
        self.tx
            .send(AppCommand::GetState { reply: reply_tx })
            .unwrap();
        reply_rx.recv().unwrap()
    }

    fn advance_setup(&self) -> Option<Result<(), String>> {
        let (reply_tx, reply_rx) = mpsc::channel();
        self.tx
            .send(AppCommand::AdvanceSetup { reply: reply_tx })
            .unwrap();
        reply_rx.recv().unwrap()
    }

    /// Fire-and-forget. If the channel is closed, silently ignore.
    fn set_state(&self, builder: StateBuilder) {
        let _ = self.tx.send(AppCommand::SetState { builder });
    }
}

// ============================================================================
// Sub-Actor: SetupMode
// ============================================================================

enum SetupCommand {
    GetStep { reply: Sender<i32> },
    Advance { reply: Sender<Result<(), String>> },
}

struct SetupMode {
    tx: Option<Sender<SetupCommand>>,
    handle: Option<thread::JoinHandle<()>>,
}

impl SetupMode {
    fn new(app: &AppHandle) -> Result<Box<dyn SubActor>, BuildError> {
        let (tx, rx) = mpsc::channel::<SetupCommand>();
        let app_handle = app.clone();

        let join_handle = thread::spawn(move || {
            let mut step = 1;
            let total_steps = 3;

            while let Ok(cmd) = rx.recv() {
                match cmd {
                    SetupCommand::GetStep { reply } => {
                        let _ = reply.send(step);
                    }
                    SetupCommand::Advance { reply } => {
                        if step < total_steps {
                            step += 1;
                            let _ = reply.send(Ok(()));
                        } else {
                            let _ = reply.send(Ok(()));
                            // Trigger transition -- fire-and-forget.
                            let config = format!("config-from-step-{}", total_steps);
                            app_handle.set_state(Box::new(move |a: &AppHandle| {
                                RunningMode::new(a, &config)
                            }));
                        }
                    }
                }
            }
        });

        Ok(Box::new(SetupMode {
            tx: Some(tx),
            handle: Some(join_handle),
        }))
    }
}

impl SubActor for SetupMode {
    fn stop_and_join(&mut self) {
        // Drop the sender to signal the thread to exit.
        self.tx.take();
        if let Some(h) = self.handle.take() {
            let _ = h.join();
        }
    }

    fn describe(&self) -> StateDescription {
        if let Some(ref tx) = self.tx {
            let (reply_tx, reply_rx) = mpsc::channel();
            if tx.send(SetupCommand::GetStep { reply: reply_tx }).is_ok() {
                if let Ok(step) = reply_rx.recv() {
                    return StateDescription::Setup { step };
                }
            }
        }
        StateDescription::Setup { step: 0 }
    }

    fn try_advance(&self) -> Option<Result<(), String>> {
        if let Some(ref tx) = self.tx {
            let (reply_tx, reply_rx) = mpsc::channel();
            if tx
                .send(SetupCommand::Advance { reply: reply_tx })
                .is_ok()
            {
                return Some(reply_rx.recv().unwrap_or(Err("recv failed".to_string())));
            }
        }
        Some(Err("setup actor stopped".to_string()))
    }
}

// ============================================================================
// Sub-Actor: RunningMode
// ============================================================================

enum RunningCommand {
    GetStatus { reply: Sender<String> },
}

struct RunningMode {
    tx: Option<Sender<RunningCommand>>,
    handle: Option<thread::JoinHandle<()>>,
    config: String, // immutable -- safe for direct reads
}

impl RunningMode {
    fn new(_app: &AppHandle, config: &str) -> Result<Box<dyn SubActor>, BuildError> {
        let (tx, rx) = mpsc::channel::<RunningCommand>();
        let cfg = config.to_string();
        let cfg_for_thread = cfg.clone();

        let join_handle = thread::spawn(move || {
            let up_since = Instant::now();

            while let Ok(cmd) = rx.recv() {
                match cmd {
                    RunningCommand::GetStatus { reply } => {
                        let uptime = up_since.elapsed();
                        let _ = reply.send(format!(
                            "running (config={}, uptime={:.0?})",
                            cfg_for_thread, uptime
                        ));
                    }
                }
            }
        });

        Ok(Box::new(RunningMode {
            tx: Some(tx),
            handle: Some(join_handle),
            config: cfg,
        }))
    }
}

impl SubActor for RunningMode {
    fn stop_and_join(&mut self) {
        self.tx.take();
        if let Some(h) = self.handle.take() {
            let _ = h.join();
        }
    }

    fn describe(&self) -> StateDescription {
        if let Some(ref tx) = self.tx {
            let (reply_tx, reply_rx) = mpsc::channel();
            if tx
                .send(RunningCommand::GetStatus { reply: reply_tx })
                .is_ok()
            {
                if let Ok(status) = reply_rx.recv() {
                    return StateDescription::Running {
                        status,
                        config: self.config.clone(),
                    };
                }
            }
        }
        StateDescription::Running {
            status: "stopped".to_string(),
            config: self.config.clone(),
        }
    }
}

// ============================================================================
// Demo
// ============================================================================

fn main() {
    // Start in SetupMode.
    let app = AppHandle::new(Box::new(|a: &AppHandle| SetupMode::new(a)));

    // Walk through the setup wizard.
    for _ in 0..4 {
        let desc = app.get_state();
        match &desc {
            StateDescription::Setup { step } => {
                println!("[Setup] On step {}", step);
                if let Some(result) = app.advance_setup() {
                    if let Err(e) = result {
                        println!("[Setup] Advance error: {}", e);
                    }
                }
                // Give fire-and-forget SetState a moment to process.
                thread::sleep(Duration::from_millis(50));
            }
            StateDescription::Running { status, config } => {
                println!("[Running] {}", status);
                println!("[Running] Config (direct getter): {}", config);
            }
            StateDescription::Error { msg } => {
                println!("[Error] {}", msg);
            }
        }
    }

    // Demonstrate RecoverableError: force a transition to a builder that fails
    // with recovery.
    println!("\n--- Triggering recoverable error ---");
    app.set_state(Box::new(|_a: &AppHandle| {
        Err(BuildError {
            msg: "primary database unavailable".to_string(),
            fallback: Some(Box::new(|a: &AppHandle| {
                println!("[Recovery] Falling back to read-only mode");
                RunningMode::new(a, "read-only-fallback")
            })),
        })
    }));
    thread::sleep(Duration::from_millis(50));

    match app.get_state() {
        StateDescription::Running { status, .. } => {
            println!("[After Recovery] {}", status);
        }
        other => println!("[After Recovery] unexpected: {:?}", other),
    }

    // Demonstrate unrecoverable error -> ErrorApp.
    println!("\n--- Triggering unrecoverable error ---");
    app.set_state(Box::new(|_a: &AppHandle| {
        Err(BuildError {
            msg: "everything is on fire".to_string(),
            fallback: Some(Box::new(|_a: &AppHandle| {
                Err(BuildError {
                    msg: "recovery also failed".to_string(),
                    fallback: None,
                })
            })),
        })
    }));
    thread::sleep(Duration::from_millis(50));

    match app.get_state() {
        StateDescription::Error { msg } => {
            println!("[ErrorApp] Parked with: {}", msg);
        }
        other => println!("[ErrorApp] unexpected: {:?}", other),
    }

    // Shutdown: drop the handle.
    drop(app);
    thread::sleep(Duration::from_millis(50));
}
