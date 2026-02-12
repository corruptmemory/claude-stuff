#!/usr/bin/env python3
"""Scaffold a new Go web project with templ, htmx, chi, and build.sh."""

import argparse
import os
import stat
import sys
import textwrap


def main():
    parser = argparse.ArgumentParser(description="Scaffold a Go web project")
    parser.add_argument("name", help="Project name (used for directory and binary)")
    parser.add_argument("--module", required=True, help="Go module path")
    parser.add_argument("--dir", default=".", help="Parent directory to create project in")
    args = parser.parse_args()

    root = os.path.join(args.dir, args.name)
    mod = args.module
    name = args.name

    if os.path.exists(root):
        print(f"ERROR: {root} already exists", file=sys.stderr)
        sys.exit(1)

    dirs = [
        "cmd/app",
        "internal/web/assets/static/css",
        "internal/web/assets/static/vendor",
        "internal/web/handlers",
        "internal/web/pages",
    ]
    for d in dirs:
        os.makedirs(os.path.join(root, d))

    files = {
        "go.mod": go_mod(mod),
        "cmd/app/main.go": main_go(mod),
        "internal/web/assets/embed.go": embed_go(),
        "internal/web/assets/static/app.js": app_js(),
        "internal/web/assets/static/css/tokens.css": tokens_css(),
        "internal/web/assets/static/css/base.css": base_css(),
        "internal/web/assets/static/css/components.css": components_css(),
        "internal/web/handlers/ping.go": ping_handler(),
        "internal/web/handlers/home.go": home_handler(mod),
        "internal/web/pages/layout.templ": layout_templ(),
        "internal/web/pages/home.templ": home_templ(),
        "build.sh": build_sh(name),
        ".air.toml": air_toml(),
        ".gitignore": gitignore(),
        "CLAUDE.md": claude_md(),
    }

    for path, content in files.items():
        full = os.path.join(root, path)
        with open(full, "w") as f:
            f.write(content)

    # Make build.sh executable
    build_path = os.path.join(root, "build.sh")
    st = os.stat(build_path)
    os.chmod(build_path, st.st_mode | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH)

    print(f"Created project at {root}")
    print(f"Next steps:")
    print(f"  cd {root}")
    print(f"  ./build.sh --refresh-htmx --refresh-normalize")
    print(f"  ./build.sh --generate")
    print(f"  go mod tidy")
    print(f"  ./build.sh --build")
    print(f"  ./build.sh --run")


def go_mod(mod):
    return textwrap.dedent(f"""\
        module {mod}

        go 1.24.0

        require (
        \tgithub.com/BurntSushi/toml v1.6.0
        \tgithub.com/a-h/templ v0.3.977
        \tgithub.com/go-chi/chi/v5 v5.2.5
        \tgithub.com/jessevdk/go-flags v1.6.1
        )
        """)


def main_go(mod):
    return textwrap.dedent(f"""\
        package main

        import (
        \t"errors"
        \t"fmt"
        \t"io/fs"
        \t"log"
        \t"net/http"
        \t"os"
        \t"reflect"
        \t"strconv"
        \t"strings"

        \t"{mod}/internal/web/assets"
        \t"{mod}/internal/web/handlers"
        \t"github.com/BurntSushi/toml"
        \t"github.com/go-chi/chi/v5"
        \t"github.com/go-chi/chi/v5/middleware"
        \t"github.com/jessevdk/go-flags"
        )

        const version = "0.1.0"
        const defaultConfigPath = "./config.toml"

        type options struct {{
        \tServe     serveCommand     `command:"serve" description:"Run the web server"`
        \tGenConfig genConfigCommand `command:"gen-config" description:"Generate documented TOML config from code defaults"`
        \tVersion   versionCommand   `command:"version" description:"Print version information"`
        }}

        type serveCommand struct {{
        \tConfig string `long:"config" default:"./config.toml" description:"Path to TOML config file"`
        \tListen string `long:"listen" description:"Listen address (host:port)"`
        }}

        type genConfigCommand struct {{
        \tOutput string `long:"output" default:"-" description:"Output path, or - for stdout"`
        }}

        type versionCommand struct{{}}

        func (c *serveCommand) Execute(_ []string) error {{
        \tsettings, err := loadSettings(c.Config)
        \tif err != nil {{
        \t\treturn err
        \t}}
        \tif c.Listen != "" {{
        \t\tsettings.Server.Listen = c.Listen
        \t}}

        \tstaticFS, err := fs.Sub(assets.StaticFS, "static")
        \tif err != nil {{
        \t\tlog.Fatal(err)
        \t}}

        \tr := chi.NewRouter()
        \tr.Use(middleware.RequestID)
        \tr.Use(middleware.RealIP)
        \tr.Use(middleware.Recoverer)
        \tr.Use(middleware.Logger)

        \tr.Get("/", handlers.Home())
        \tr.Get("/ping", handlers.Ping())
        \tr.Handle("/static/*", http.StripPrefix("/static/", http.FileServer(http.FS(staticFS))))

        \tlog.Printf("listening on %s", settings.Server.Listen)
        \tif err := http.ListenAndServe(settings.Server.Listen, r); err != nil {{
        \t\tlog.Fatal(err)
        \t}}
        \treturn nil
        }}

        func (c *genConfigCommand) Execute(_ []string) error {{
        \tcontent, err := renderDocumentedConfig(defaultSettings())
        \tif err != nil {{
        \t\treturn err
        \t}}
        \tif c.Output == "-" {{
        \t\t_, err = os.Stdout.WriteString(content)
        \t\treturn err
        \t}}
        \treturn os.WriteFile(c.Output, []byte(content), 0o644)
        }}

        func (c *versionCommand) Execute(_ []string) error {{
        \t_, err := os.Stdout.WriteString("app " + version + "\\n")
        \treturn err
        }}

        func main() {{
        \tvar opts options
        \tparser := flags.NewParser(&opts, flags.Default)
        \targs := os.Args[1:]
        \tif len(args) == 0 {{
        \t\targs = []string{{"serve"}}
        \t}}
        \tif _, err := parser.ParseArgs(args); err != nil {{
        \t\tvar flagsErr *flags.Error
        \t\tif errors.As(err, &flagsErr) && flagsErr.Type == flags.ErrHelp {{
        \t\t\tos.Exit(0)
        \t\t}}
        \t\tos.Exit(1)
        \t}}
        }}

        type settings struct {{
        \tServer serverSettings `toml:"server" doc:"HTTP server settings."`
        }}

        type serverSettings struct {{
        \tListen string `toml:"listen" doc:"Listen address in host:port format."`
        }}

        type fileConfig struct {{
        \tServer fileServer `toml:"server"`
        }}

        type fileServer struct {{
        \tListen *string `toml:"listen"`
        }}

        func defaultSettings() settings {{
        \treturn settings{{
        \t\tServer: serverSettings{{
        \t\t\tListen: ":8080",
        \t\t}},
        \t}}
        }}

        func loadSettings(configPath string) (settings, error) {{
        \tout := defaultSettings()
        \t_, statErr := os.Stat(configPath)
        \tif statErr != nil {{
        \t\tif os.IsNotExist(statErr) && configPath == defaultConfigPath {{
        \t\t\treturn out, nil
        \t\t}}
        \t\treturn out, fmt.Errorf("config file error for %q: %w", configPath, statErr)
        \t}}
        \tvar cfg fileConfig
        \tif _, err := toml.DecodeFile(configPath, &cfg); err != nil {{
        \t\treturn out, fmt.Errorf("config parse error for %q: %w", configPath, err)
        \t}}
        \tif cfg.Server.Listen != nil {{
        \t\tout.Server.Listen = *cfg.Server.Listen
        \t}}
        \treturn out, nil
        }}

        func renderDocumentedConfig(cfg settings) (string, error) {{
        \tvar b strings.Builder
        \tb.WriteString("# Generated by `app gen-config`.\\n")
        \tb.WriteString("# Source of truth: defaults defined in code.\\n")
        \tb.WriteString("# Copy to config.toml and edit as needed.\\n\\n")
        \tt := reflect.TypeFor[settings]()
        \tv := reflect.ValueOf(cfg)
        \tif t.Kind() != reflect.Struct {{
        \t\treturn "", fmt.Errorf("settings must be a struct")
        \t}}
        \tif err := writeSections(&b, t, v, nil, ""); err != nil {{
        \t\treturn "", err
        \t}}
        \treturn strings.TrimRight(b.String(), "\\n") + "\\n", nil
        }}

        func writeSections(b *strings.Builder, t reflect.Type, v reflect.Value, path []string, sectionDoc string) error {{
        \tif len(path) > 0 {{
        \t\tif sectionDoc != "" {{
        \t\t\twriteCommentBlock(b, sectionDoc)
        \t\t}}
        \t\tb.WriteString("[" + strings.Join(path, ".") + "]\\n")
        \t}}
        \twroteValues := false
        \tfor i := 0; i < t.NumField(); i++ {{
        \t\tfield := t.Field(i)
        \t\tif !field.IsExported() {{
        \t\t\tcontinue
        \t\t}}
        \t\tname := tomlName(field)
        \t\tif name == "" {{
        \t\t\tcontinue
        \t\t}}
        \t\tfv := v.Field(i)
        \t\tif field.Type.Kind() == reflect.Struct {{
        \t\t\tcontinue
        \t\t}}
        \t\tdoc := strings.TrimSpace(field.Tag.Get("doc"))
        \t\tif doc != "" {{
        \t\t\twriteCommentBlock(b, doc)
        \t\t}}
        \t\tliteral, err := tomlLiteral(fv)
        \t\tif err != nil {{
        \t\t\treturn fmt.Errorf("render %q: %w", strings.Join(append(path, name), "."), err)
        \t\t}}
        \t\tb.WriteString(name + " = " + literal + "\\n")
        \t\twroteValues = true
        \t}}
        \tif len(path) > 0 && wroteValues {{
        \t\tb.WriteString("\\n")
        \t}}
        \tfor i := 0; i < t.NumField(); i++ {{
        \t\tfield := t.Field(i)
        \t\tif !field.IsExported() {{
        \t\t\tcontinue
        \t\t}}
        \t\tname := tomlName(field)
        \t\tif name == "" {{
        \t\t\tcontinue
        \t\t}}
        \t\tif field.Type.Kind() != reflect.Struct {{
        \t\t\tcontinue
        \t\t}}
        \t\tif err := writeSections(b, field.Type, v.Field(i), append(path, name), strings.TrimSpace(field.Tag.Get("doc"))); err != nil {{
        \t\t\treturn err
        \t\t}}
        \t}}
        \treturn nil
        }}

        func writeCommentBlock(b *strings.Builder, text string) {{
        \tfor _, line := range strings.Split(text, "\\n") {{
        \t\ttrimmed := strings.TrimSpace(line)
        \t\tif trimmed == "" {{
        \t\t\tcontinue
        \t\t}}
        \t\tb.WriteString("# " + trimmed + "\\n")
        \t}}
        }}

        func tomlName(field reflect.StructField) string {{
        \ttag := strings.TrimSpace(field.Tag.Get("toml"))
        \tif tag == "" || tag == "-" {{
        \t\treturn ""
        \t}}
        \tname := strings.Split(tag, ",")[0]
        \tif name == "" || name == "-" {{
        \t\treturn ""
        \t}}
        \treturn name
        }}

        func tomlLiteral(v reflect.Value) (string, error) {{
        \tswitch v.Kind() {{
        \tcase reflect.String:
        \t\treturn strconv.Quote(v.String()), nil
        \tcase reflect.Bool:
        \t\treturn strconv.FormatBool(v.Bool()), nil
        \tcase reflect.Int, reflect.Int8, reflect.Int16, reflect.Int32, reflect.Int64:
        \t\treturn strconv.FormatInt(v.Int(), 10), nil
        \tcase reflect.Uint, reflect.Uint8, reflect.Uint16, reflect.Uint32, reflect.Uint64, reflect.Uintptr:
        \t\treturn strconv.FormatUint(v.Uint(), 10), nil
        \tcase reflect.Float32, reflect.Float64:
        \t\treturn strconv.FormatFloat(v.Float(), 'f', -1, 64), nil
        \tcase reflect.Slice, reflect.Array:
        \t\titems := make([]string, 0, v.Len())
        \t\tfor i := 0; i < v.Len(); i++ {{
        \t\t\titem, err := tomlLiteral(v.Index(i))
        \t\t\tif err != nil {{
        \t\t\t\treturn "", err
        \t\t\t}}
        \t\t\titems = append(items, item)
        \t\t}}
        \t\treturn "[" + strings.Join(items, ", ") + "]", nil
        \tdefault:
        \t\treturn "", fmt.Errorf("unsupported type %s", v.Kind())
        \t}}
        }}
        """)


def embed_go():
    return textwrap.dedent("""\
        package assets

        import "embed"

        // StaticFS contains all web assets served from /static.
        //
        //go:embed static
        var StaticFS embed.FS
        """)


def app_js():
    return "// Application-level JS (htmx handles interactions declaratively).\n"


def tokens_css():
    return textwrap.dedent("""\
        :root {
          --font-sans: "Avenir Next", "Segoe UI", "Helvetica Neue", Helvetica, Arial, sans-serif;
          --font-serif: "Iowan Old Style", "Palatino Linotype", Palatino, serif;
          --line: 1.5;

          --space-1: 0.25rem;
          --space-2: 0.5rem;
          --space-3: 0.75rem;
          --space-4: 1rem;
          --space-5: 1.5rem;
          --space-6: 2rem;
          --space-7: 3rem;

          --radius-1: 0.375rem;
          --radius-2: 0.625rem;
          --radius-3: 0.875rem;

          --color-bg: #f4f2ee;
          --color-bg-accent: #fceede;
          --color-surface: #fffcf8;
          --color-border: #ddd7cb;
          --color-text: #1a1a1a;
          --color-muted: #5f5a50;
          --color-brand: #8f4e2c;
          --color-brand-hover: #7d4324;
          --color-result-bg: #f2ece3;
          --shadow-1: 0 12px 26px rgba(20, 15, 10, 0.08);
        }
        """)


def base_css():
    return textwrap.dedent("""\
        *,
        *::before,
        *::after {
          box-sizing: border-box;
        }

        html,
        body {
          margin: 0;
          padding: 0;
        }

        body {
          font-family: var(--font-sans);
          line-height: var(--line);
          color: var(--color-text);
          background: radial-gradient(circle at top right, var(--color-bg-accent), var(--color-bg) 45%);
        }

        .shell {
          width: min(100% - 2rem, 58rem);
          margin: var(--space-7) auto;
        }

        h1,
        h2,
        h3 {
          margin: 0;
          font-family: var(--font-serif);
          line-height: 1.2;
        }

        p {
          margin: 0;
        }

        pre,
        code {
          font-family: "JetBrains Mono", "SFMono-Regular", Menlo, Consolas, monospace;
          font-size: 0.925rem;
        }

        @media (max-width: 640px) {
          .shell {
            margin: var(--space-6) auto;
          }
        }
        """)


def components_css():
    return textwrap.dedent("""\
        .stack {
          display: grid;
          gap: var(--space-4);
        }

        .surface {
          padding: var(--space-6);
          border: 1px solid var(--color-border);
          border-radius: var(--radius-3);
          background: var(--color-surface);
          box-shadow: var(--shadow-1);
        }

        .eyebrow {
          font-size: 0.82rem;
          letter-spacing: 0.08em;
          text-transform: uppercase;
          color: var(--color-muted);
        }

        .lede {
          color: var(--color-muted);
          max-width: 60ch;
        }

        .muted {
          color: var(--color-muted);
        }

        .row {
          display: flex;
          gap: var(--space-3);
          align-items: center;
          flex-wrap: wrap;
        }

        .button {
          border: 0;
          border-radius: var(--radius-2);
          padding: 0.65rem 0.95rem;
          color: #fff;
          background: var(--color-brand);
          font-weight: 600;
          cursor: pointer;
        }

        .button:hover,
        .button:focus-visible {
          background: var(--color-brand-hover);
        }

        .label {
          font-weight: 700;
        }

        .big-value {
          font-family: var(--font-serif);
          font-size: 1.8rem;
          line-height: 1.1;
          font-weight: 700;
        }
        """)


def ping_handler():
    return textwrap.dedent("""\
        package handlers

        import (
        \t"fmt"
        \t"net/http"
        \t"time"
        )

        func Ping() http.HandlerFunc {
        \treturn func(w http.ResponseWriter, r *http.Request) {
        \t\tw.Header().Set("Content-Type", "text/html; charset=utf-8")
        \t\tnow := time.Now().UTC().Format(time.RFC3339)
        \t\t_, _ = fmt.Fprintf(w, "<code>pong %s</code>", now)
        \t}
        }
        """)


def home_handler(mod):
    return textwrap.dedent(f"""\
        package handlers

        import (
        \t"net/http"

        \t"{mod}/internal/web/pages"

        \t"github.com/a-h/templ"
        )

        func Home() http.HandlerFunc {{
        \treturn func(w http.ResponseWriter, r *http.Request) {{
        \t\tcomponent := pages.HomePage()
        \t\ttempl.Handler(component).ServeHTTP(w, r)
        \t}}
        }}
        """)


def layout_templ():
    return textwrap.dedent("""\
        package pages

        templ Layout(title string) {
        \t<!doctype html>
        \t<html lang="en">
        \t\t<head>
        \t\t\t<meta charset="utf-8"/>
        \t\t\t<meta name="viewport" content="width=device-width, initial-scale=1"/>
        \t\t\t<title>{ title }</title>
        \t\t\t<link rel="stylesheet" href="/static/vendor/modern-normalize.css"/>
        \t\t\t<link rel="stylesheet" href="/static/css/tokens.css"/>
        \t\t\t<link rel="stylesheet" href="/static/css/base.css"/>
        \t\t\t<link rel="stylesheet" href="/static/css/components.css"/>
        \t\t</head>
        \t\t<body>
        \t\t\t<main class="shell">
        \t\t\t\t{ children... }
        \t\t\t</main>
        \t\t\t<script src="/static/vendor/htmx.min.js"></script>
        \t\t\t<script src="/static/app.js"></script>
        \t\t</body>
        \t</html>
        }
        """)


def home_templ():
    return textwrap.dedent("""\
        package pages

        templ HomePage() {
        \t@Layout("Home") {
        \t\t<section class="stack">
        \t\t\t<header class="stack">
        \t\t\t\t<h1>Welcome</h1>
        \t\t\t\t<p class="lede">Your app is running.</p>
        \t\t\t</header>
        \t\t</section>
        \t}
        }
        """)


def build_sh(name):
    return textwrap.dedent(f"""\
        #!/usr/bin/env bash
        set -euo pipefail

        SCRIPT_DIR="$(cd "$(dirname "${{BASH_SOURCE[0]}}")" && pwd)"
        ROOT_DIR="$SCRIPT_DIR"
        BIN_DIR="$ROOT_DIR/bin"
        HTMX_VERSION="${{HTMX_VERSION:-2.0.7}}"
        HTMX_URL="https://unpkg.com/htmx.org@${{HTMX_VERSION}}/dist/htmx.min.js"
        HTMX_VENDOR_DIR="$ROOT_DIR/internal/web/assets/static/vendor"
        HTMX_FILE="$HTMX_VENDOR_DIR/htmx.min.js"
        HTMX_VERSION_FILE="$HTMX_VENDOR_DIR/htmx.version"
        NORMALIZE_VERSION="${{NORMALIZE_VERSION:-3.0.1}}"
        NORMALIZE_URL="https://unpkg.com/modern-normalize@${{NORMALIZE_VERSION}}/modern-normalize.css"
        NORMALIZE_FILE="$HTMX_VENDOR_DIR/modern-normalize.css"
        NORMALIZE_VERSION_FILE="$HTMX_VENDOR_DIR/modern-normalize.version"

        function usage() {{
          cat <<'EOF'
        Usage: ./build.sh [options]

        Options:
          -h, --help       Show this help text
          -N, --refresh-normalize Download vendored modern-normalize.css
          -H, --refresh-htmx Download vendored htmx.min.js
          -D, --develop    Build once, then run air
          -g, --generate   Run templ code generation
          -b, --build      Build the app binary
          -r, --run        Run the app
          -t, --test       Run Go tests
          -c, --clean      Remove build artifacts

        Examples:
          ./build.sh --refresh-htmx --refresh-normalize
          ./build.sh --generate --build
          ./build.sh --run
          ./build.sh --test
        EOF
        }}

        function check_available() {{
          local name="$1"
          if ! command -v "$name" >/dev/null 2>&1; then
            echo "ERROR: required program missing: $name"
            exit 1
          fi
        }}

        function has_generated_templates() {{
          compgen -G "$ROOT_DIR/internal/web/pages/*_templ.go" >/dev/null
        }}

        function ensure_go() {{
          check_available go
        }}

        function ensure_templ() {{
          check_available templ
        }}

        function run_generate() {{
          ensure_templ
          echo "==> Generating templ files"
          (cd "$ROOT_DIR" && templ generate ./...)
        }}

        function run_build() {{
          ensure_go
          local bin_path
          bin_path="$(resolve_bin_path)"
          if ! has_generated_templates; then
            echo "==> No generated templ files found; running generate first"
            run_generate
          fi
          mkdir -p "$BIN_DIR"
          echo "==> Building static binary $bin_path"
          (cd "$ROOT_DIR" && CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o "$bin_path" ./cmd/app)
        }}

        function run_app() {{
          ensure_go
          if ! has_generated_templates; then
            echo "==> No generated templ files found; running generate first"
            run_generate
          fi
          echo "==> Running app on http://localhost:8080"
          (cd "$ROOT_DIR" && go run ./cmd/app)
        }}

        function run_tests() {{
          ensure_go
          if ! has_generated_templates; then
            echo "==> No generated templ files found; running generate first"
            run_generate
          fi
          echo "==> Running tests"
          (cd "$ROOT_DIR" && go test ./...)
        }}

        function run_clean() {{
          echo "==> Cleaning build artifacts"
          rm -rf "$BIN_DIR"
        }}

        function ensure_air() {{
          if command -v air >/dev/null 2>&1; then
            echo "air"
            return 0
          fi
          ensure_go
          echo "==> air not found; installing github.com/air-verse/air@latest" >&2
          (cd "$ROOT_DIR" && go install github.com/air-verse/air@latest)
          if command -v air >/dev/null 2>&1; then
            echo "air"
            return 0
          fi
          local gopath_bin
          gopath_bin="$(go env GOPATH)/bin/air"
          if [[ -x "$gopath_bin" ]]; then
            echo "$gopath_bin"
            return 0
          fi
          echo "ERROR: air installation completed, but binary not found on PATH or at $gopath_bin"
          exit 1
        }}

        function resolve_bin_path() {{
          ensure_go
          local goexe
          goexe="$(go env GOEXE)"
          printf '%s/app%s' "$BIN_DIR" "$goexe"
        }}

        function run_develop() {{
          local air_cmd
          air_cmd="$(ensure_air | tail -n 1)"
          run_build
          echo "==> Starting air with $air_cmd"
          (cd "$ROOT_DIR" && CGO_ENABLED=0 "$air_cmd")
        }}

        function run_refresh_htmx() {{
          check_available curl
          mkdir -p "$HTMX_VENDOR_DIR"
          echo "==> Downloading htmx $HTMX_VERSION"
          curl -fsSL "$HTMX_URL" -o "$HTMX_FILE"
          printf '%s\\n' "$HTMX_VERSION" > "$HTMX_VERSION_FILE"
        }}

        function run_refresh_normalize() {{
          check_available curl
          mkdir -p "$HTMX_VENDOR_DIR"
          echo "==> Downloading modern-normalize $NORMALIZE_VERSION"
          curl -fsSL "$NORMALIZE_URL" -o "$NORMALIZE_FILE"
          printf '%s\\n' "$NORMALIZE_VERSION" > "$NORMALIZE_VERSION_FILE"
        }}

        DO_REFRESH_NORMALIZE=false
        DO_REFRESH_HTMX=false
        DO_DEVELOP=false
        DO_GENERATE=false
        DO_BUILD=false
        DO_RUN=false
        DO_TEST=false
        DO_CLEAN=false

        if [[ $# -eq 0 ]]; then
          usage
          exit 0
        fi

        while [[ $# -gt 0 ]]; do
          case "$1" in
            -h|--help)
              usage
              exit 0
              ;;
            -H|--refresh-htmx)
              DO_REFRESH_HTMX=true
              shift
              ;;
            -N|--refresh-normalize)
              DO_REFRESH_NORMALIZE=true
              shift
              ;;
            -D|--develop)
              DO_DEVELOP=true
              shift
              ;;
            -g|--generate)
              DO_GENERATE=true
              shift
              ;;
            -b|--build)
              DO_BUILD=true
              shift
              ;;
            -r|--run)
              DO_RUN=true
              shift
              ;;
            -t|--test)
              DO_TEST=true
              shift
              ;;
            -c|--clean)
              DO_CLEAN=true
              shift
              ;;
            *)
              echo "ERROR: unknown argument: $1"
              echo
              usage
              exit 1
              ;;
          esac
        done

        if [[ "$DO_CLEAN" == "true" ]]; then
          run_clean
        fi

        if [[ "$DO_REFRESH_HTMX" == "true" ]]; then
          run_refresh_htmx
        fi

        if [[ "$DO_REFRESH_NORMALIZE" == "true" ]]; then
          run_refresh_normalize
        fi

        if [[ "$DO_GENERATE" == "true" ]]; then
          run_generate
        fi

        if [[ "$DO_BUILD" == "true" ]]; then
          run_build
        fi

        if [[ "$DO_DEVELOP" == "true" ]]; then
          run_develop
        fi

        if [[ "$DO_TEST" == "true" ]]; then
          run_tests
        fi

        if [[ "$DO_RUN" == "true" ]]; then
          run_app
        fi
        """)


def air_toml():
    return textwrap.dedent("""\
        root = "."
        tmp_dir = "tmp"

        [build]
        cmd = "templ generate ./... && go build -trimpath -o ./tmp/app ./cmd/app"
        entrypoint = ["./tmp/app"]
        include_ext = ["go", "templ", "toml", "css", "js"]
        include_dir = ["cmd", "internal"]
        exclude_dir = ["bin", "tmp", ".git"]
        exclude_regex = ["_test\\\\.go", "_templ\\\\.go"]
        delay = 300
        stop_on_error = true
        send_interrupt = true
        kill_delay = "500ms"

        [log]
        time = true
        """)


def gitignore():
    return textwrap.dedent("""\
        bin/
        tmp/
        config.toml
        """)


def claude_md():
    return textwrap.dedent("""\
        # CLAUDE.md

        ## Build & Development Commands

        **Always use `./build.sh` for building, testing, template generation, and other dev workflows.**

        - `./build.sh --generate` — run templ code generation
        - `./build.sh --build` — static binary to `bin/app` (`CGO_ENABLED=0`)
        - `./build.sh --run` — run the app on `:8080`
        - `./build.sh --test` — run tests
        - `./build.sh --develop` — build once then run `air` for live reload
        - `./build.sh --clean` — remove `bin/`

        Flags can be combined: `./build.sh --generate --build`.

        The app defaults to the `serve` subcommand when invoked with no args.

        ## Coding Conventions

        - Format with `gofmt`
        - Templates: edit `*.templ` files, then run `./build.sh --generate` — never hand-edit `*_templ.go`
        - Static frontend deps are vendored under `internal/web/assets/static/vendor/`
        - Prefer CLI flags and TOML config over environment variables
        """)


if __name__ == "__main__":
    main()
