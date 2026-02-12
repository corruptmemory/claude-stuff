# User Preferences

## Go Web Applications

I build Go web apps as single static binaries with all assets embedded. My preferred stack:

- **Router:** chi (`github.com/go-chi/chi/v5`)
- **Templates:** templ (`github.com/a-h/templ`) — type-safe HTML, edit `.templ` files only
- **Frontend interactivity:** htmx (vendored JS, no npm/node)
- **CLI parsing:** go-flags (`github.com/jessevdk/go-flags`) with subcommands
- **Config:** TOML via BurntSushi/toml, with reflection-based `gen-config` subcommand
- **CSS:** Custom design tokens (tokens.css) + utility classes, no frameworks
- **Frontend deps:** Vendored under `static/vendor/`, downloaded via `build.sh --refresh-*`
- **Live reload:** air (`.air.toml`)

Always use `./build.sh` — never invoke `go build`, `go test`, `templ generate` directly.

## Concurrency Pattern

For shared mutable state accessed by HTTP handlers, I prefer the goroutine actor pattern over mutexes or atomic pointers. A single goroutine owns all mutable state, handlers communicate via typed command channels. See the `actor-pattern` skill for the full implementation guide.

## General Preferences

- Format Go with `gofmt`
- Prefer CLI flags and TOML config over environment variables
- Keep things simple — no over-abstraction, no unnecessary dependencies
- Tests should be straightforward table-driven or sequential, using `t.TempDir()` for isolation
