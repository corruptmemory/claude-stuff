// Example 02: Scaling Fault Line
//
// Demonstrates the same interface backed by two implementations:
//   - MemoryCache: in-process map with TTL expiration
//   - SimulatedRemoteCache: pretends to talk to a remote service (same interface)
//
// The scaling decision is made at construction time. Every consumer sees CacheStore.
//
// Run: go run ./02_scaling_fault_line
package main

import (
	"context"
	"errors"
	"fmt"
	"sync"
	"time"
)

// ---------------------------------------------------------------------------
// The contract
// ---------------------------------------------------------------------------

var ErrCacheMiss = errors.New("cache miss")

type CacheStore interface {
	Get(ctx context.Context, key string) ([]byte, error)
	Set(ctx context.Context, key string, value []byte, ttl time.Duration) error
	Delete(ctx context.Context, key string) error
}

// ---------------------------------------------------------------------------
// Implementation A: In-process (single-instance deployments)
// ---------------------------------------------------------------------------

type cacheEntry struct {
	value   []byte
	expires time.Time
}

type MemoryCache struct {
	mu      sync.Mutex
	entries map[string]cacheEntry
}

func NewMemoryCache() *MemoryCache {
	return &MemoryCache{entries: make(map[string]cacheEntry)}
}

func (m *MemoryCache) Get(_ context.Context, key string) ([]byte, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	e, ok := m.entries[key]
	if !ok || time.Now().After(e.expires) {
		delete(m.entries, key)
		return nil, ErrCacheMiss
	}
	cp := make([]byte, len(e.value))
	copy(cp, e.value)
	return cp, nil
}

func (m *MemoryCache) Set(_ context.Context, key string, value []byte, ttl time.Duration) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	cp := make([]byte, len(value))
	copy(cp, value)
	m.entries[key] = cacheEntry{value: cp, expires: time.Now().Add(ttl)}
	return nil
}

func (m *MemoryCache) Delete(_ context.Context, key string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	delete(m.entries, key)
	return nil
}

// ---------------------------------------------------------------------------
// Implementation B: Simulated remote (multi-instance deployments)
// ---------------------------------------------------------------------------

type SimulatedRemoteCache struct {
	mu      sync.Mutex
	entries map[string]cacheEntry
	latency time.Duration // simulates network round-trip
}

func NewSimulatedRemoteCache(latency time.Duration) *SimulatedRemoteCache {
	return &SimulatedRemoteCache{
		entries: make(map[string]cacheEntry),
		latency: latency,
	}
}

func (r *SimulatedRemoteCache) Get(ctx context.Context, key string) ([]byte, error) {
	time.Sleep(r.latency)
	r.mu.Lock()
	defer r.mu.Unlock()
	e, ok := r.entries[key]
	if !ok || time.Now().After(e.expires) {
		delete(r.entries, key)
		return nil, ErrCacheMiss
	}
	cp := make([]byte, len(e.value))
	copy(cp, e.value)
	return cp, nil
}

func (r *SimulatedRemoteCache) Set(ctx context.Context, key string, value []byte, ttl time.Duration) error {
	time.Sleep(r.latency)
	r.mu.Lock()
	defer r.mu.Unlock()
	cp := make([]byte, len(value))
	copy(cp, value)
	r.entries[key] = cacheEntry{value: cp, expires: time.Now().Add(ttl)}
	return nil
}

func (r *SimulatedRemoteCache) Delete(ctx context.Context, key string) error {
	time.Sleep(r.latency)
	r.mu.Lock()
	defer r.mu.Unlock()
	delete(r.entries, key)
	return nil
}

// ---------------------------------------------------------------------------
// Construction-time decision
// ---------------------------------------------------------------------------

func NewCacheStore(useRemote bool) CacheStore {
	if useRemote {
		return NewSimulatedRemoteCache(5 * time.Millisecond)
	}
	return NewMemoryCache()
}

// ---------------------------------------------------------------------------
// Business logic — only sees CacheStore
// ---------------------------------------------------------------------------

func CachedLookup(cache CacheStore, key string) ([]byte, error) {
	ctx := context.Background()
	val, err := cache.Get(ctx, key)
	if err == nil {
		return val, nil
	}
	// Cache miss — "compute" the value and cache it.
	val = []byte(fmt.Sprintf("computed-%s", key))
	_ = cache.Set(ctx, key, val, 10*time.Second)
	return val, nil
}

// ---------------------------------------------------------------------------
// Demo
// ---------------------------------------------------------------------------

func main() {
	for _, remote := range []bool{false, true} {
		label := "in-process"
		if remote {
			label = "simulated-remote"
		}
		fmt.Printf("--- %s ---\n", label)

		cache := NewCacheStore(remote)
		ctx := context.Background()

		// First lookup: miss, computes and caches.
		start := time.Now()
		val, _ := CachedLookup(cache, "user:123")
		fmt.Printf("  First:  %s (%v)\n", val, time.Since(start).Truncate(time.Millisecond))

		// Second lookup: hit.
		start = time.Now()
		val, _ = CachedLookup(cache, "user:123")
		fmt.Printf("  Second: %s (%v)\n", val, time.Since(start).Truncate(time.Millisecond))

		// Delete and re-lookup.
		_ = cache.Delete(ctx, "user:123")
		start = time.Now()
		val, _ = CachedLookup(cache, "user:123")
		fmt.Printf("  After delete: %s (%v)\n", val, time.Since(start).Truncate(time.Millisecond))
	}
}
