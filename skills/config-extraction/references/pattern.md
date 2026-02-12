# Config Extraction Pattern — Complete Reference

## Architecture

```
Global config.Configuration (loaded from TOML/YAML/env)
  → ConfigToXxxConfig() pure conversion function
    → XxxConfig focused struct (lives in subsystem package)
      → Subsystem constructor takes XxxConfig
        → Subsystem never imports the config package
```

Key invariant: **the conversion function is the only place the subsystem touches the global config**. After conversion, the subsystem works entirely with its own types.

## 1. Define the Focused Config Struct

The struct lives in the subsystem's package. Inline all fields — never embed original config sub-structs, as that would drag the config package dependency back in.

```go
package mysubsystem

// MySubsystemConfig contains all configuration needed by this subsystem.
// Fields are pre-resolved and ready to use — no further lookups needed.
type MySubsystemConfig struct {
    // Simple scalar fields (mapped directly from global config)
    BaseUrl     string
    RefreshUrl  string
    LastNDays   int
    AuthEnabled bool

    // Pre-resolved values (derived from cross-referencing in global config)
    ConnectionInfo  azure.AzureBlobConnectionInfo
    ExportBlob      azure.AzureBlob
}
```

### Design principles:

- **Flat over nested** — `AuthEnabled` not `Auth.Enabled`
- **Pre-resolved over raw** — store the looked-up storage key, not the account name that requires a lookup
- **Concrete over generic** — if the subsystem uses 3 of 20 fields from a sub-struct, take only those 3

## 2. Write the Conversion Function

The conversion function is a **pure function** that lives in the subsystem package. It takes the global config, validates, resolves cross-references, and returns the focused config.

```go
package mysubsystem

import "myapp/config"

func ConfigToMySubsystemConfig(conf config.Configuration) (MySubsystemConfig, error) {
    msc := MySubsystemConfig{
        // Direct field mappings
        BaseUrl:     conf.Web.BaseUrl,
        RefreshUrl:  conf.Web.RefreshUrl,
        LastNDays:   conf.BlobDataSync.LastNDays,
        AuthEnabled: conf.Web.WebAuth.Enabled,
    }

    // Pre-resolve cross-references (e.g. storage account name → key)
    // Use conditional resolution so callers that don't need this
    // capability can still use the same conversion function.
    if sa, ok := conf.Azure.StorageAccounts[conf.MyService.StorageAccount]; ok {
        msc.ConnectionInfo = azure.AzureBlobConnectionInfo{
            ContainerName: conf.MyService.Container,
            AccountName:   conf.MyService.StorageAccount,
            AccountKey:    sa.StorageAccountKey,
        }
        msc.ExportBlob = azure.AzureBlob{
            ContainerName: conf.MyService.Container,
            BlobKey:       conf.MyService.ExportPrefix + "/output.csv",
            AccountName:   conf.MyService.StorageAccount,
            AccountKey:    sa.StorageAccountKey,
        }
    }

    return msc, nil
}
```

### Key patterns in the conversion function:

- **Conditional resolution**: `if sa, ok := ...; ok { }` — allows binaries that don't configure a particular storage account to still call this function without error.
- **Pre-build composite values**: If the subsystem always constructs a blob from prefix + filename, do it here once rather than in every handler.
- **Validation**: If certain fields are required, check them here and return an error.

## 3. Update the Subsystem

Change the stored config type and constructor parameter:

```go
// BEFORE
type MyService struct {
    conf config.Configuration  // imports global config package
}

func NewMyService(conf config.Configuration) *MyService { ... }

// handler accesses deeply nested fields:
//   m.conf.Web.WebAuth.Enabled
//   m.conf.Azure.StorageAccounts[m.conf.MyService.StorageAccount]

// AFTER
type MyService struct {
    conf MySubsystemConfig  // no config package import needed
}

func NewMyService(conf MySubsystemConfig) *MyService { ... }

// handler accesses flat fields:
//   m.conf.AuthEnabled
//   m.conf.ConnectionInfo  (already resolved)
```

### Mechanical transformation workflow:

1. Change the struct field type → build fails everywhere
2. Change the constructor parameter type → more build failures surface
3. For each compiler error, map `m.conf.X.Y.Z` → `m.conf.Z` using your field catalog
4. Remove the `config` package import from files that no longer need it
5. Build after each file to catch issues incrementally

## 4. Update Call Sites

At each call site (`cmd/main.go`, etc.), call the conversion function before the constructor:

```go
// BEFORE
svc := mysubsystem.NewMyService(globalConf)

// AFTER
subsystemConf, err := mysubsystem.ConfigToMySubsystemConfig(globalConf)
if err != nil {
    return err
}
svc := mysubsystem.NewMyService(subsystemConf)
```

If multiple consumers need the same focused config (e.g. both a constructor and an HTTP bootstrapper), create the focused config once and pass it to both.

## 5. Update Tests

Test helpers keep constructing the global `config.Configuration` and pass it through the conversion function. This validates the full path:

```go
func setupTest() *MyService {
    conf := config.Configuration{
        Web: config.Web{BaseUrl: "http://localhost"},
        // ... test values ...
    }
    msc, err := ConfigToMySubsystemConfig(conf)
    if err != nil {
        panic(err)
    }
    return NewMyService(msc)
}
```

For unit tests of the subsystem in isolation (not testing the conversion), construct `MySubsystemConfig` directly:

```go
func TestSomething(t *testing.T) {
    svc := NewMyService(MySubsystemConfig{
        BaseUrl:     "http://test",
        AuthEnabled: false,
    })
    // ... test ...
}
```

## Checklist Per Subsystem

- [ ] Cataloged all `conf.X.Y.Z` field accesses in the package
- [ ] Defined focused config struct (flat, no config package types)
- [ ] Wrote `ConfigToXxxConfig()` conversion function with pre-resolution
- [ ] Changed stored config type on the service struct
- [ ] Changed constructor to accept focused config
- [ ] Updated all field references (follow compiler errors)
- [ ] Removed unused `config` package imports
- [ ] Updated all call sites to use conversion function
- [ ] Updated test helpers
- [ ] All binaries build
- [ ] All tests compile and pass
- [ ] Committed
