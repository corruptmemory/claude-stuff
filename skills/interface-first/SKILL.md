---
name: interface-first
description: "Design around contracts, not implementations. Use when: (1) building multi-step features where placeholders would otherwise accumulate, (2) expensive or stateful objects need mock and real implementations (databases, caches, external services), (3) scaling fault lines exist where in-proc vs. remote implementations should be swappable, (4) test mocks need to verify behavior through observation hooks, (5) designing a system that may need to scale from single-process to distributed without a rewrite, (6) the user mentions 'interface first', 'mock implementation', 'store interface', 'transaction boundary', 'scaling fault line', 'single binary', 'deployment topology', or 'test contract'. Primarily Go, but applicable to any language with interface-like constructs (Rust traits, Java/Scala interfaces)."
---

# Interface-First Design

Program against the contract, not the implementation. Define interfaces before writing any concrete code. Stubs become real implementations additively — never a rewrite.

## Why This Should Be a First-Reach Tool

This pattern prevents three engineering failure modes:

**The placeholder trap.** "I'll build the real thing later" is how tech debt ships to customers. If the interface exists first, your stub already has the right shape. The progression from stub → working code is additive. Nothing gets rewritten, nothing gets accidentally shipped as a placeholder.

**Scaling fault lines.** Interfaces mark the architectural boundaries where deployment topology can change. Same interface, different backing: in-proc SQLite store vs. sharded Postgres cluster, local cache vs. Redis. The interface *is* the scaling decision point. You don't refactor your callers when you scale — you swap the implementation. See "The Single Binary Principle" below for the full vision.

**Test mocks with observation hooks.** Not "mock everything" (which is fragile) but "mock the expensive boundaries" — databases, network services, clocks — with implementations that are correct enough to exercise real business logic. Each mock is purpose-built for what it needs to observe. Don't build the universal mock framework; build what you need, export it, move on.

## When to Apply

- You feel the urge to build a placeholder implementation in a multi-step build
- An expensive or stateful object (database, cache, external API) needs isolation from its consumers
- You can identify a "scaling fault line" — a boundary where in-proc and remote implementations should be interchangeable
- You need test mocks that verify behavior, not just return canned data
- Multiple consumers of a subsystem are coupled to its implementation details

## The Transaction Pattern

When an interface wraps a transactional store, prefer the **closure-based `Update` pattern** over `BeginTransaction`:

```go
type Store interface {
    // Read-only queries
    GetUser(ctx context.Context, id string) (*User, error)
    ListUsers(ctx context.Context) ([]*User, error)

    // Transactional writes — the boundary is completely explicit
    Update(ctx context.Context, fn func(tx WriteTx) error) error
}

type WriteTx interface {
    CreateUser(user *User) error
    DeleteUser(id string) error
}
```

The `Update` closure makes the transactional boundary unambiguous: everything inside `fn` is one transaction, committed on nil return, rolled back on error. There's no forgotten `Commit()`, no leaked transaction handle, no "who owns this connection?" confusion.

**Escape hatch:** `BeginTransaction(ctx) (WriteTx, error)` with an explicit `Commit()` on the `WriteTx`. Use this only when the transaction must span caller-controlled logic that can't be captured in a closure (e.g., streaming writes, interactive workflows). It exists because sometimes you've painted yourself into an API corner — acknowledge it, use it, don't pretend it's the preferred path.

This pattern has deep roots: Clojure's Refs and Transactions use the same "pass a function to the transactional boundary" approach. The principle is language-agnostic even when the syntax is Go-specific.

## Mock Philosophy

Don't build the universal mock framework. Build what you need, export it, move on.

It's not unusual to see several implementations of the same interface in a codebase — a real implementation, a test mock with recording, a simpler test mock for a different scenario. Each is purpose-built. Be kind, export your goodies, someone else may find them useful. But the "universal mock tool" rarely pays its freight costs.

Mock implementations should be **correct enough** that business logic exercised through them produces meaningful results. A mock store that returns hardcoded data can verify happy paths; a mock store that actually maintains state in a map can verify sequences of reads and writes. Choose the level of fidelity your tests actually need.

Observation hooks are ad-hoc: a slice of recorded calls, a channel that receives events, a counter, a callback. Whatever the test needs to verify its correctness criteria. No ceremony required.

## Narrow test seams for time, randomness, and system calls

When the subject-under-test reaches for a global (time.Now, rand.Read,
os.Stdin), introduce a narrow interface at the boundary. One real
impl, one test impl. Production passes the real one; tests pass a
fake that exposes observation + control methods. Example from
`idpair-inbound`:

```go
type Ticker interface {
    GetTick() <-chan time.Time
    Reset(d time.Duration)
    Stop()
}
```

The test's ManualTicker exposes `Fire()` to push a tick and
`AwaitReset()` as a deterministic sync barrier (via unbuffered
channel). Tests then run without `time.Sleep`.

The interface should only contain methods the actor actually uses —
not the full time.Ticker surface. YAGNI applies.

## The Single Binary Principle

Every distributed application can be modeled as a single app. The default state is that the logic and coherence of the entire system can be shown to be sound, because you can run it as a single process. Not as a dozen Docker containers each running whatever was built by other teams — but something the compiler validates as a whole.

**How it works:** One Go binary, multiple subcommands. Deployment topology is selected by CLI flags, not by which container you're running.

```go
// All implementations live in the same binary.
var ud UserDirectory

switch cfg.Mode {
case "standalone":
    ud = NewSQLiteUserDirectory(cfg.DBPath)
case "sharded":
    ud = NewShardedClient(cfg.RegistrationServer)
}

app := NewApp(ud, /* ... */)
```

Deploying standalone (everything in one process):
```
super-app main-app --mode standalone --db ./users.db
```

Deploying sharded (multiple nodes):
```
# Nodes 1-4: run the sharded data store
super-app data-store --shard-range A-B --registration-server ...
super-app data-store --shard-range C-D --registration-server ...
super-app data-store --shard-range E-G --registration-server ...
super-app data-store --shard-range H-Z --registration-server ...

# Node 0: run the main app, pointed at the sharded cluster
super-app main-app --mode sharded --registration-server ...
```

The `main-app` consumer has no idea whether `UserDirectory` is backed by a local SQLite file or a four-node sharded cluster. It calls the same methods, gets the same types back.

**Why this matters:**

- The **compiler validates the whole system**. All modes — standalone, sharded, distributed — compile from the same source. If the interface changes, every implementation must update, and the compiler tells you exactly where.
- **Integration tests run in-process.** You can test the full system — including the sharding logic — in a single test binary with no containers, no network, no Docker Compose.
- **"Microservices" become deployment topology, not code organization.** The boundaries aren't between repos or teams — they're between interface implementations, all living in the same binary. You choose at deployment time, not at architecture-astronaut time.
- **Incremental scaling.** Start standalone. When you outgrow a single node, add the sharded implementation behind the same interface. No rewrite, no new repo, no new CI pipeline. Just a new subcommand and a CLI flag.

This is what "microservices" should have been: not org-chart-driven repository proliferation, but interface-driven deployment flexibility within a coherent, compiler-verified system.

## Intersection with the Actor Pattern

The actor pattern and interface-first design are natural complements. The actor's public interface *is* the contract. The `run()` goroutine and channel machinery are hidden behind it. Callers interact with `MyService` — they don't know whether the implementation is:

- A channel-based actor in the same process
- An RPC client talking to a remote actor
- A test mock recording calls in a slice

This is the scaling fault line in action: the interface lets you start with an in-proc actor and later swap in a remote client without touching any caller code.

## References & Examples

- [references/go-patterns.md](references/go-patterns.md) — Complete Go implementation templates
- [go-compendium/](go-compendium/) — Runnable Go examples

## Implementation Steps (Go)

1. **Define the read interface** — what callers need to query
2. **Define the write interface** (`WriteTx`) — what mutations are allowed inside a transaction
3. **Define the store interface** — read methods + `Update(ctx, func(WriteTx) error) error`
4. **Implement the mock** — in-memory map-based, good enough for tests, with whatever observation hooks specific tests need
5. **Implement the real thing** — wraps the actual database/service, same interface
6. **Wire callers to the interface** — never to the concrete type
7. **Test through the mock** — exercise real business logic, verify via observation
