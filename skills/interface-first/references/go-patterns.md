# Interface-First Design — Go Patterns Reference

## 1. Store Interface with Closure-Based Transactions

The canonical pattern: read-only methods on the main interface, writes behind an `Update` closure.

```go
// UserStore is the contract. Nothing here reveals SQL, file paths, or wire protocols.
type UserStore interface {
    // Read-only
    GetUser(ctx context.Context, id string) (*User, error)
    ListUsers(ctx context.Context, filter UserFilter) ([]*User, error)
    CountUsers(ctx context.Context) (int, error)

    // Transactional writes
    Update(ctx context.Context, fn func(tx UserWriteTx) error) error
}

// UserWriteTx is available only inside an Update closure.
type UserWriteTx interface {
    CreateUser(user *User) error
    UpdateUser(user *User) error
    DeleteUser(id string) error
}
```

Key properties:
- **No `Close()`** — the store's lifecycle is managed by whoever created it (main, test setup), not by consumers
- **No connection details** — consumers don't know if this is SQLite, Postgres, or a map
- **`ctx` on reads, not on writes** — the `Update` call carries the context; individual write operations inside the transaction inherit it
- **`error` returns on everything** — even operations that "can't fail" in the mock might fail against a real database

## 2. In-Memory Mock Implementation

The mock is a real, working implementation — not a recording stub. It maintains state so tests can verify sequences of operations.

```go
type MemoryUserStore struct {
    mu    sync.Mutex
    users map[string]*User

    // Ad-hoc observation hooks — add what you need per test scenario.
    // There is no "universal mock recorder" — build what you need.
    CreateCalls []User   // records what was created
    DeleteCalls []string // records what was deleted
}

func NewMemoryUserStore() *MemoryUserStore {
    return &MemoryUserStore{users: make(map[string]*User)}
}

func (m *MemoryUserStore) GetUser(_ context.Context, id string) (*User, error) {
    m.mu.Lock()
    defer m.mu.Unlock()
    u, ok := m.users[id]
    if !ok {
        return nil, ErrNotFound
    }
    copy := *u
    return &copy, nil
}

func (m *MemoryUserStore) ListUsers(_ context.Context, filter UserFilter) ([]*User, error) {
    m.mu.Lock()
    defer m.mu.Unlock()
    var result []*User
    for _, u := range m.users {
        if filter.Matches(u) {
            copy := *u
            result = append(result, &copy)
        }
    }
    return result, nil
}

func (m *MemoryUserStore) CountUsers(_ context.Context) (int, error) {
    m.mu.Lock()
    defer m.mu.Unlock()
    return len(m.users), nil
}

func (m *MemoryUserStore) Update(_ context.Context, fn func(tx UserWriteTx) error) error {
    m.mu.Lock()
    defer m.mu.Unlock()

    // Snapshot for rollback on error.
    snapshot := make(map[string]*User, len(m.users))
    for k, v := range m.users {
        copy := *v
        snapshot[k] = &copy
    }

    tx := &memoryWriteTx{store: m}
    if err := fn(tx); err != nil {
        m.users = snapshot // rollback
        return err
    }
    return nil
}

type memoryWriteTx struct {
    store *MemoryUserStore
}

func (tx *memoryWriteTx) CreateUser(user *User) error {
    if _, exists := tx.store.users[user.ID]; exists {
        return ErrAlreadyExists
    }
    copy := *user
    tx.store.users[user.ID] = &copy
    tx.store.CreateCalls = append(tx.store.CreateCalls, copy)
    return nil
}

func (tx *memoryWriteTx) UpdateUser(user *User) error {
    if _, exists := tx.store.users[user.ID]; !exists {
        return ErrNotFound
    }
    copy := *user
    tx.store.users[user.ID] = &copy
    return nil
}

func (tx *memoryWriteTx) DeleteUser(id string) error {
    if _, exists := tx.store.users[id]; !exists {
        return ErrNotFound
    }
    delete(tx.store.users, id)
    tx.store.DeleteCalls = append(tx.store.DeleteCalls, id)
    return nil
}
```

Critical details:
- **Returns copies, not pointers to internal state** — callers can't mutate the mock's state by accident
- **Snapshot-and-rollback** — the `Update` closure semantics are real: if `fn` returns an error, the state reverts. Tests that depend on rollback behavior work correctly against the mock.
- **Observation hooks are exported fields** — `CreateCalls`, `DeleteCalls`. Tests inspect them directly. No framework, no assertion library integration, no ceremony.
- **The mutex is on the store, not the tx** — the `Update` call holds the lock for the entire transaction, just like a real database transaction holds a write lock.

## 3. SQL Implementation (The Real Thing)

Same interface, backed by a real database.

```go
type SQLUserStore struct {
    db *sql.DB
}

func NewSQLUserStore(db *sql.DB) *SQLUserStore {
    return &SQLUserStore{db: db}
}

func (s *SQLUserStore) GetUser(ctx context.Context, id string) (*User, error) {
    row := s.db.QueryRowContext(ctx, "SELECT id, name, email FROM users WHERE id = ?", id)
    var u User
    if err := row.Scan(&u.ID, &u.Name, &u.Email); err != nil {
        if errors.Is(err, sql.ErrNoRows) {
            return nil, ErrNotFound
        }
        return nil, err
    }
    return &u, nil
}

func (s *SQLUserStore) Update(ctx context.Context, fn func(tx UserWriteTx) error) error {
    sqlTx, err := s.db.BeginTx(ctx, nil)
    if err != nil {
        return err
    }
    defer sqlTx.Rollback() // no-op after commit

    wtx := &sqlWriteTx{tx: sqlTx}
    if err := fn(wtx); err != nil {
        return err
    }
    return sqlTx.Commit()
}

type sqlWriteTx struct {
    tx *sql.Tx
}

func (wtx *sqlWriteTx) CreateUser(user *User) error {
    _, err := wtx.tx.Exec("INSERT INTO users (id, name, email) VALUES (?, ?, ?)",
        user.ID, user.Name, user.Email)
    return err
}

// ... UpdateUser, DeleteUser follow the same pattern
```

Notice: **`defer sqlTx.Rollback()`** — if `fn` returns an error, the deferred rollback fires. If `fn` succeeds, `Commit()` runs first; the deferred `Rollback()` is a no-op on an already-committed transaction. This is a standard Go database pattern.

## 4. The Scaling Fault Line Pattern

When the same interface can be backed by an in-process implementation or a remote service:

```go
// CacheStore — the contract. Callers don't know if this is a map or Redis.
type CacheStore interface {
    Get(ctx context.Context, key string) ([]byte, error)
    Set(ctx context.Context, key string, value []byte, ttl time.Duration) error
    Delete(ctx context.Context, key string) error
}

// In-process implementation — good for single-instance deployments.
type MemoryCache struct {
    mu      sync.Mutex
    entries map[string]cacheEntry
}

// Remote implementation — same interface, talks to Redis.
type RedisCache struct {
    client *redis.Client
}

// Wire at startup based on configuration:
func NewCacheStore(cfg Config) CacheStore {
    if cfg.RedisAddr != "" {
        return NewRedisCache(cfg.RedisAddr)
    }
    return NewMemoryCache()
}
```

The scaling decision is made at construction time. Every consumer sees `CacheStore`. When you outgrow a single instance, you change the config — not the code.

## 5. The BeginTransaction Escape Hatch

When the closure pattern doesn't fit — typically streaming writes or interactive workflows where the caller must interleave its own logic with transactional operations:

```go
type StreamStore interface {
    // ... read methods ...

    // Escape hatch: caller manages the transaction lifecycle.
    BeginTransaction(ctx context.Context) (StreamWriteTx, error)
}

type StreamWriteTx interface {
    WriteChunk(data []byte) error
    Commit() error
    Rollback() error
}

// Usage — note the caller must handle Commit/Rollback:
func UploadFile(store StreamStore, ctx context.Context, reader io.Reader) error {
    tx, err := store.BeginTransaction(ctx)
    if err != nil {
        return err
    }
    defer tx.Rollback() // safety net

    buf := make([]byte, 4096)
    for {
        n, err := reader.Read(buf)
        if n > 0 {
            if err := tx.WriteChunk(buf[:n]); err != nil {
                return err
            }
        }
        if err == io.EOF {
            break
        }
        if err != nil {
            return err
        }
    }
    return tx.Commit()
}
```

This is the **escape hatch**, not the preferred path. It exists because sometimes the transaction must span caller-controlled iteration. Use `Update(func(WriteTx) error)` whenever possible.

## 6. Composing Read and ReadWrite Interfaces

When reads and writes share methods, embed the read interface in the write interface:

```go
type Reader interface {
    GetUser(ctx context.Context, id string) (*User, error)
    ListUsers(ctx context.Context) ([]*User, error)
}

type ReadWriter interface {
    Reader
    CreateUser(user *User) error
    DeleteUser(id string) error
}

type Store interface {
    Reader
    Update(ctx context.Context, fn func(tx ReadWriter) error) error
}
```

Inside the `Update` closure, `tx` can both read and write — which is exactly how database transactions work. Read methods outside `Update` see committed state only.

## 7. Testing Through the Interface

Tests use the mock, exercise real business logic, and verify through observation:

```go
func TestCreateUserDeduplicates(t *testing.T) {
    store := NewMemoryUserStore()

    user := &User{ID: "1", Name: "Alice", Email: "alice@example.com"}

    // First create succeeds.
    err := store.Update(context.Background(), func(tx UserWriteTx) error {
        return tx.CreateUser(user)
    })
    if err != nil {
        t.Fatal(err)
    }

    // Second create fails with ErrAlreadyExists.
    err = store.Update(context.Background(), func(tx UserWriteTx) error {
        return tx.CreateUser(user)
    })
    if !errors.Is(err, ErrAlreadyExists) {
        t.Fatalf("expected ErrAlreadyExists, got %v", err)
    }

    // Verify via observation hook.
    if len(store.CreateCalls) != 1 {
        t.Fatalf("expected 1 create call, got %d", len(store.CreateCalls))
    }

    // Verify the store has exactly one user.
    count, _ := store.CountUsers(context.Background())
    if count != 1 {
        t.Fatalf("expected 1 user, got %d", count)
    }
}

func TestUpdateRollsBackOnError(t *testing.T) {
    store := NewMemoryUserStore()

    // Seed a user.
    store.Update(context.Background(), func(tx UserWriteTx) error {
        return tx.CreateUser(&User{ID: "1", Name: "Alice"})
    })

    // Attempt a multi-step update that fails partway through.
    err := store.Update(context.Background(), func(tx UserWriteTx) error {
        tx.UpdateUser(&User{ID: "1", Name: "Bob"})
        return fmt.Errorf("something went wrong")
    })
    if err == nil {
        t.Fatal("expected error")
    }

    // Verify rollback: name should still be Alice.
    u, _ := store.GetUser(context.Background(), "1")
    if u.Name != "Alice" {
        t.Fatalf("expected rollback to Alice, got %s", u.Name)
    }
}
```

The tests are **testing business logic**, not mock plumbing. The mock is invisible — it's just a `UserStore` that happens to live in memory.

## Design Principles

**Accept interfaces, return structs.** Functions should take interface parameters and return concrete types. This makes dependency injection natural without a framework.

**Keep interfaces small.** A 3-method interface is easier to mock, implement, and reason about than a 15-method one. Split by read/write or by domain concept. The `io.Reader`/`io.Writer` split is the gold standard.

**Don't export the implementation.** Export `NewUserStore(db *sql.DB) UserStore` — not `NewSQLUserStore`. Callers bind to the interface, never to the concrete type.

**Mock at the boundary, not everywhere.** Mock databases, external APIs, clocks, random number generators. Don't mock your own business logic — test it directly through the interface.

**Each mock is bespoke.** Build the observation hooks you need for the tests you're writing. A slice of recorded calls here, a counter there, a channel for async verification somewhere else. No universal mock recorder — the freight costs exceed the value.

**Compose read/write interfaces for transactional stores.** When a store has both reads and writes, split the interfaces and compose:

```go
type ReadOps interface { GetFoo(id int64) (*Foo, error) }
type WriteOps interface { CreateFoo(f *Foo) error }
type WriteTx interface { ReadOps; WriteOps }  // reads + writes inside tx
type Store interface { ReadOps; Update(func(WriteTx) error) error; Close() error }
```

Reads go directly on the store (no transaction needed for WAL-mode SQLite or read replicas). Writes always go through `Update`. The `WriteTx` embeds `ReadOps` because writes often need to read-modify-write atomically. Callers can't accidentally bypass the transaction boundary — the type system enforces it.

**The Sausage Theorem.** Problems have a minimum amount of complexity. Extracting an interface doesn't reduce total lines — it moves them. The value is that each piece now has a single responsibility: the interface defines the contract, the real implementation handles persistence, the fake records calls for tests, and the consumer (actor, handler) handles orchestration. Same meat, better slicing.
