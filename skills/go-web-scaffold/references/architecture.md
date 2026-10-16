# Go Web Application Architecture

## Directory Layout

```
<project>/
├── cmd/app/
│   └── main.go              # Entrypoint, CLI, config, route wiring
├── internal/
│   ├── <domain>/            # Domain logic (e.g., weather/, users/)
│   └── web/
│       ├── assets/
│       │   ├── embed.go     # //go:embed static
│       │   └── static/
│       │       ├── app.js
│       │       ├── css/
│       │       │   ├── tokens.css       # Design tokens (colors, spacing, fonts)
│       │       │   ├── base.css         # Reset + global styles
│       │       │   └── components.css   # Component classes
│       │       └── vendor/              # Vendored frontend deps (htmx, etc.)
│       ├── handlers/        # HTTP handlers (one file per concern)
│       └── pages/           # .templ source files
├── build.sh                 # Central build/dev script
├── .air.toml                # Live reload config
├── .gitignore
├── go.mod
├── go.sum
└── CLAUDE.md                # Project instructions for Claude Code
```

## Key Libraries

| Library | Purpose | Import |
|---------|---------|--------|
| chi | HTTP router | `github.com/go-chi/chi/v5` |
| templ | Type-safe HTML templates | `github.com/a-h/templ` |
| htmx | Frontend interactivity (vendored JS) | N/A |
| go-flags | CLI parsing with subcommands | `github.com/jessevdk/go-flags` |
| BurntSushi/toml | TOML config parsing | `github.com/BurntSushi/toml` |

## Single Binary Architecture

All static assets are embedded via `//go:embed`. The `embed.go` file:

```go
package assets

import "embed"

//go:embed static
var StaticFS embed.FS
```

Served in main.go:
```go
staticFS, _ := fs.Sub(assets.StaticFS, "static")
r.Handle("/static/*", http.StripPrefix("/static/", http.FileServer(http.FS(staticFS))))
```

## build.sh Pattern

Central script for all build/dev tasks. Never invoke `go build`, `go test`, `templ generate` directly.

Required flags:
- `--generate` / `-g` — run `templ generate ./...`
- `--build` / `-b` — static binary to `bin/app` (`CGO_ENABLED=0`)
- `--run` / `-r` — run the app
- `--test` / `-t` — run tests
- `--develop` / `-D` — build once then run `air` for live reload
- `--clean` / `-c` — remove `bin/`

Vendor refresh flags (one per vendored dep):
- `--refresh-htmx` / `-H`
- `--refresh-normalize` / `-N`
- Add more as deps are added

Pattern: version variable with env override, URL constructed from version, download with curl.

```bash
HTMX_VERSION="${HTMX_VERSION:-2.0.7}"
HTMX_URL="https://unpkg.com/htmx.org@${HTMX_VERSION}/dist/htmx.min.js"
```

Build auto-generates templ if no `*_templ.go` files exist (an implied flag, below, not a call from the build step).

### Parse flags, then run linearly

The argument loop only records what was asked for; the steps then run once each in one fixed order. Flags whose work overlaps (`-b -D`, `-g -b`) never repeat a step, and the order the user types flags in never matters. Reference implementation: `~/bhf/data-management-service/build.sh`.

```bash
# --- Parse: record what was asked for; run nothing. ---
DO_CLEAN=false DO_GENERATE=false DO_TEST=false DO_BUILD=false DO_DEVELOP=false DO_RUN=false
RUN_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -c|--clean)    DO_CLEAN=true ;;
    -g|--generate) DO_GENERATE=true ;;
    -t|--test)     DO_TEST=true ;;
    -b|--build)    DO_BUILD=true ;;
    -D|--develop)  DO_DEVELOP=true ;;
    -r|--run)      DO_RUN=true; shift; RUN_ARGS=("$@"); break ;; # the rest goes to the app
    -h|--help)     usage; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage; exit 1 ;;
  esac
  shift
done

# --- Implied steps: a step switches on what it needs; no step calls another. ---
if [[ "$DO_DEVELOP" == true ]]; then DO_BUILD=true; fi
if [[ "$DO_BUILD" == true || "$DO_TEST" == true || "$DO_RUN" == true ]] && ! has_generated_templates; then
  DO_GENERATE=true
fi
if [[ "$DO_DEVELOP" == true && "$DO_RUN" == true ]]; then
  echo "ERROR: --develop and --run both run the app; pick one" >&2; exit 1
fi

# --- Run: each requested step once, in this order. ---
if [[ "$DO_CLEAN" == true ]]; then run_clean; fi
if [[ "$DO_GENERATE" == true ]]; then run_generate; fi
if [[ "$DO_TEST" == true ]]; then run_tests; fi
if [[ "$DO_BUILD" == true ]]; then run_build; fi
if [[ "$DO_DEVELOP" == true ]]; then run_develop; fi   # long-running: last
if [[ "$DO_RUN" == true ]]; then run_app "${RUN_ARGS[@]}"; fi
```

Rules:
- A new flag gets a `DO_*` variable, a `case` line, a step function, and one line in the run section at its place in the order. If it needs another step, add a line to the implied-steps block; never call that step's function from its own.
- Tests run before the build, so a failure stops the run before the slow steps.
- Anything that never returns (`air`, `exec` of the binary) is last, and only one of them may be requested.
- If a late step needs a tool, check for it before the slow steps (a preflight line in the run section, ahead of generate and build).
- Arguments that belong to another program (`go test` flags, the app's own flags) come last on the command line and are captured into an array during parsing.

## Config Pattern

### Settings structs with `toml` + `doc` tags

```go
type settings struct {
    Server  serverSettings  `toml:"server" doc:"HTTP server settings."`
}

type serverSettings struct {
    Listen string `toml:"listen" doc:"Listen address in host:port format."`
}
```

### Separate file-config structs with pointer fields for optional override

```go
type fileConfig struct {
    Server fileServer `toml:"server"`
}
type fileServer struct {
    Listen *string `toml:"listen"`
}
```

### Reflective gen-config subcommand

Uses `reflect` to walk the settings struct and emit documented TOML from struct tags:

```go
func renderDocumentedConfig(cfg settings) (string, error) { ... }
```

Invoked via: `./bin/app gen-config --output config.toml`

### Default subcommand pattern

App defaults to `serve` when invoked with no args:

```go
args := os.Args[1:]
if len(args) == 0 {
    args = []string{"serve"}
}
```

## Route Wiring

All routes wired in `serveCommand.Execute()`:

```go
r := chi.NewRouter()
r.Use(middleware.RequestID)
r.Use(middleware.RealIP)
r.Use(middleware.Recoverer)
r.Use(middleware.Logger)

r.Get("/", handlers.Home(...))
r.Get("/ping", handlers.Ping())
r.Handle("/static/*", http.StripPrefix("/static/", http.FileServer(http.FS(staticFS))))
```

## Handler Pattern

Handlers are constructor functions returning `http.HandlerFunc`, accepting dependencies as arguments:

```go
func Home(c MyService) http.HandlerFunc {
    return func(w http.ResponseWriter, r *http.Request) {
        data, _ := c.GetData()
        component := pages.HomePage(data)
        templ.Handler(component).ServeHTTP(w, r)
    }
}
```

## Template Structure

### Layout (layout.templ)

HTML shell with CSS/JS tags. Uses `{ children... }` for content injection:

```
templ Layout(title string) {
    <!doctype html>
    <html lang="en">
        <head>
            <link rel="stylesheet" href="/static/vendor/modern-normalize.css"/>
            <link rel="stylesheet" href="/static/css/tokens.css"/>
            <link rel="stylesheet" href="/static/css/base.css"/>
            <link rel="stylesheet" href="/static/css/components.css"/>
        </head>
        <body>
            <main class="shell">{ children... }</main>
            <script src="/static/vendor/htmx.min.js"></script>
            <script src="/static/app.js"></script>
        </body>
    </html>
}
```

### Pages use @Layout wrapper

```
templ HomePage(data *MyData) {
    @Layout("Page Title") {
        <section class="stack">
            ...
        </section>
    }
}
```

## CSS Design Token System

### tokens.css — Design primitives

```css
:root {
  --font-sans: "Avenir Next", "Segoe UI", "Helvetica Neue", Helvetica, Arial, sans-serif;
  --font-serif: "Iowan Old Style", "Palatino Linotype", Palatino, serif;
  --space-1: 0.25rem;  /* through --space-7: 3rem */
  --radius-1: 0.375rem;
  --color-bg: #f4f2ee;
  --color-surface: #fffcf8;
  --color-border: #ddd7cb;
  --color-text: #1a1a1a;
  --color-muted: #5f5a50;
  --color-brand: #8f4e2c;
  --shadow-1: 0 12px 26px rgba(20, 15, 10, 0.08);
}
```

### base.css — Reset + global typography

Box-sizing reset, body font, `.shell` max-width container, heading/paragraph resets.

### components.css — Reusable classes

`.stack` (grid with gap), `.surface` (card), `.row` (flex), `.button`, `.eyebrow`, `.lede`, `.muted`, `.big-value`, `.label`.

## .air.toml

```toml
root = "."
tmp_dir = "tmp"

[build]
cmd = "templ generate ./... && go build -trimpath -o ./tmp/app ./cmd/app"
entrypoint = ["./tmp/app"]
include_ext = ["go", "templ", "toml", "css", "js"]
include_dir = ["cmd", "internal"]
exclude_dir = ["bin", "tmp", ".git"]
exclude_regex = ["_test\\.go", "_templ\\.go"]
delay = 300
stop_on_error = true
send_interrupt = true
kill_delay = "500ms"

[log]
time = true
```

## .gitignore

```
bin/
tmp/
config.toml
```

## Health Check

Always include `GET /ping` returning `pong <timestamp>`.
