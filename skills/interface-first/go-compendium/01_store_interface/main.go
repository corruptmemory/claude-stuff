// Example 01: Store Interface with Closure-Based Transactions
//
// Demonstrates the core interface-first pattern:
//   - A UserStore interface with read methods and Update(func(WriteTx) error)
//   - An in-memory mock with snapshot-and-rollback and observation hooks
//   - Tests that exercise real business logic through the mock
//
// Run: go run ./01_store_interface
package main

import (
	"context"
	"errors"
	"fmt"
	"sync"
)

// ---------------------------------------------------------------------------
// Domain types
// ---------------------------------------------------------------------------

type User struct {
	ID    string
	Name  string
	Email string
}

var (
	ErrNotFound      = errors.New("not found")
	ErrAlreadyExists = errors.New("already exists")
)

// ---------------------------------------------------------------------------
// The contract — no SQL, no file paths, no wire protocols
// ---------------------------------------------------------------------------

type UserStore interface {
	GetUser(ctx context.Context, id string) (*User, error)
	ListUsers(ctx context.Context) ([]*User, error)
	CountUsers(ctx context.Context) (int, error)
	Update(ctx context.Context, fn func(tx UserWriteTx) error) error
}

type UserWriteTx interface {
	CreateUser(user *User) error
	UpdateUser(user *User) error
	DeleteUser(id string) error
}

// ---------------------------------------------------------------------------
// In-memory mock implementation
// ---------------------------------------------------------------------------

type MemoryUserStore struct {
	mu    sync.Mutex
	users map[string]*User

	// Observation hooks — ad-hoc, per-need.
	CreateCalls []User
	DeleteCalls []string
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

func (m *MemoryUserStore) ListUsers(_ context.Context) ([]*User, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	var result []*User
	for _, u := range m.users {
		copy := *u
		result = append(result, &copy)
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

	// Snapshot for rollback.
	snapshot := make(map[string]*User, len(m.users))
	for k, v := range m.users {
		copy := *v
		snapshot[k] = &copy
	}

	tx := &memoryWriteTx{store: m}
	if err := fn(tx); err != nil {
		m.users = snapshot
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

// ---------------------------------------------------------------------------
// Business logic — takes the interface, not the implementation
// ---------------------------------------------------------------------------

func RegisterUser(store UserStore, name, email string) (*User, error) {
	user := &User{
		ID:    fmt.Sprintf("user_%s", name),
		Name:  name,
		Email: email,
	}
	err := store.Update(context.Background(), func(tx UserWriteTx) error {
		return tx.CreateUser(user)
	})
	if err != nil {
		return nil, err
	}
	return user, nil
}

func TransferOwnership(store UserStore, fromID, toID, newName string) error {
	return store.Update(context.Background(), func(tx UserWriteTx) error {
		if err := tx.DeleteUser(fromID); err != nil {
			return fmt.Errorf("delete old owner: %w", err)
		}
		return tx.CreateUser(&User{ID: toID, Name: newName, Email: toID + "@example.com"})
	})
}

// ---------------------------------------------------------------------------
// Demo — exercises the business logic through the mock
// ---------------------------------------------------------------------------

func main() {
	store := NewMemoryUserStore()
	ctx := context.Background()

	// Register users.
	alice, err := RegisterUser(store, "alice", "alice@example.com")
	if err != nil {
		fmt.Printf("register error: %v\n", err)
		return
	}
	fmt.Printf("Registered: %s (%s)\n", alice.Name, alice.Email)

	bob, _ := RegisterUser(store, "bob", "bob@example.com")
	fmt.Printf("Registered: %s (%s)\n", bob.Name, bob.Email)

	// Duplicate detection.
	_, err = RegisterUser(store, "alice", "alice2@example.com")
	fmt.Printf("Duplicate: %v\n", err)

	// Count.
	count, _ := store.CountUsers(ctx)
	fmt.Printf("Users: %d\n", count)

	// Transfer ownership (multi-step transaction).
	err = TransferOwnership(store, "user_bob", "user_charlie", "Charlie")
	if err != nil {
		fmt.Printf("transfer error: %v\n", err)
	}

	// Verify.
	users, _ := store.ListUsers(ctx)
	fmt.Println("After transfer:")
	for _, u := range users {
		fmt.Printf("  %s: %s\n", u.ID, u.Name)
	}

	// Rollback demo: try to transfer a non-existent user.
	err = TransferOwnership(store, "user_nonexistent", "user_dave", "Dave")
	fmt.Printf("Bad transfer: %v\n", err)

	// State should be unchanged after rollback.
	count, _ = store.CountUsers(ctx)
	fmt.Printf("Users after failed transfer: %d (should be 2)\n", count)

	// Observation hooks.
	fmt.Printf("Create calls: %d\n", len(store.CreateCalls))
	fmt.Printf("Delete calls: %v\n", store.DeleteCalls)
}
