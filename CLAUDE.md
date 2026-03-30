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

## Platform: Arch Linux with Brave Browser

This machine runs Arch Linux. Chrome is **not installed**. The browser is **Brave** at `/usr/bin/brave`.

**Playwright MCP setup:** The Playwright plugin must use Brave instead of Chrome. Configure by editing the plugin's `.mcp.json`:

```bash
# Find the plugin config (hash changes on updates):
find ~/.claude/plugins/cache -path '*/playwright/*/.mcp.json'

# It should contain:
```
```json
{
  "playwright": {
    "command": "npx",
    "args": ["@playwright/mcp@latest", "--executable-path", "/usr/bin/brave"]
  }
}
```

**If Playwright fails with "Chromium distribution 'chrome' is not found":**
1. Find the `.mcp.json` with the command above
2. Add `"--executable-path", "/usr/bin/brave"` to the args array
3. Restart Claude Code (the MCP server caches the old config)

**Never** run `npx playwright install` — it tries to install Chrome and fails on Arch. The `--executable-path` flag is discovered via `npx @playwright/mcp@latest --help`.

## MCP Plugin Permissions (stop the prompting)

The `mcp__*` wildcard in global `settings.json` does NOT actually suppress prompts for MCP tools. You must enumerate every tool explicitly in `.claude/settings.local.json` per project.

**Recipe — copy this into any project's `.claude/settings.local.json`:**

```json
{
  "permissions": {
    "allow": [
      "mcp__plugin_playwright_playwright__browser_close",
      "mcp__plugin_playwright_playwright__browser_resize",
      "mcp__plugin_playwright_playwright__browser_console_messages",
      "mcp__plugin_playwright_playwright__browser_handle_dialog",
      "mcp__plugin_playwright_playwright__browser_evaluate",
      "mcp__plugin_playwright_playwright__browser_file_upload",
      "mcp__plugin_playwright_playwright__browser_fill_form",
      "mcp__plugin_playwright_playwright__browser_install",
      "mcp__plugin_playwright_playwright__browser_press_key",
      "mcp__plugin_playwright_playwright__browser_type",
      "mcp__plugin_playwright_playwright__browser_navigate",
      "mcp__plugin_playwright_playwright__browser_navigate_back",
      "mcp__plugin_playwright_playwright__browser_network_requests",
      "mcp__plugin_playwright_playwright__browser_run_code",
      "mcp__plugin_playwright_playwright__browser_take_screenshot",
      "mcp__plugin_playwright_playwright__browser_snapshot",
      "mcp__plugin_playwright_playwright__browser_click",
      "mcp__plugin_playwright_playwright__browser_drag",
      "mcp__plugin_playwright_playwright__browser_hover",
      "mcp__plugin_playwright_playwright__browser_select_option",
      "mcp__plugin_playwright_playwright__browser_tabs",
      "mcp__plugin_playwright_playwright__browser_wait_for",
      "mcp__plugin_serena_serena__read_file",
      "mcp__plugin_serena_serena__create_text_file",
      "mcp__plugin_serena_serena__list_dir",
      "mcp__plugin_serena_serena__find_file",
      "mcp__plugin_serena_serena__replace_content",
      "mcp__plugin_serena_serena__get_symbols_overview",
      "mcp__plugin_serena_serena__find_symbol",
      "mcp__plugin_serena_serena__find_referencing_symbols",
      "mcp__plugin_serena_serena__replace_symbol_body",
      "mcp__plugin_serena_serena__insert_after_symbol",
      "mcp__plugin_serena_serena__insert_before_symbol",
      "mcp__plugin_serena_serena__rename_symbol",
      "mcp__plugin_serena_serena__write_memory",
      "mcp__plugin_serena_serena__read_memory",
      "mcp__plugin_serena_serena__list_memories",
      "mcp__plugin_serena_serena__delete_memory",
      "mcp__plugin_serena_serena__edit_memory",
      "mcp__plugin_serena_serena__execute_shell_command",
      "mcp__plugin_serena_serena__search_for_pattern",
      "mcp__plugin_serena_serena__activate_project",
      "mcp__plugin_serena_serena__switch_modes",
      "mcp__plugin_serena_serena__get_current_config",
      "mcp__plugin_serena_serena__check_onboarding_performed",
      "mcp__plugin_serena_serena__onboarding",
      "mcp__plugin_serena_serena__prepare_for_new_conversation",
      "mcp__plugin_serena_serena__initial_instructions",
      "mcp__plugin_context7_context7__resolve-library-id",
      "mcp__plugin_context7_context7__query-docs"
    ]
  }
}
```

Tool names follow the pattern `mcp__plugin_<pluginname>_<servername>__<toolname>`. If a new plugin shows up and prompts, enumerate its tools the same way.

## glab (GitLab CLI) Quick Reference

`glab` v1.88+ is installed. Key flags that differ from `gh` (GitHub CLI):

```bash
# Create a merge request (non-interactive):
glab mr create \
  --title "Title here" \
  --description "Body here" \    # NOT --body (that's gh)
  --target-branch main \
  --yes                          # -y skips confirmation prompt (REQUIRED for non-interactive use)

# --fill uses commit message as title/description (skips prompts, auto-pushes)
glab mr create --fill --yes

# --recover retries from a saved recovery file but still needs --title or --fill
```

**Common mistakes to avoid:**
- `--body` does not exist — use `--description` (`-d`)
- Without `--yes`, glab drops into an interactive prompt that hangs in non-interactive contexts
- `--repo` accepts `OWNER/REPO` or `GROUP/NAMESPACE/REPO` format, NOT a full `https://` URL
- Auth token can expire silently — check with `glab auth status` before blaming flag syntax

## playwright-cli (standalone CLI browser automation)

`playwright-cli` is installed globally at `/usr/bin/playwright-cli`. This is a **separate tool** from the Playwright MCP plugin — it's a standalone CLI for browser automation.

**Config file:** Each project needs `.playwright/cli.config.json`. The config structure mirrors Playwright's internal object hierarchy — flat top-level keys do NOT work:

```json
{
  "browser": {
    "launchOptions": {
      "channel": "chrome",
      "executablePath": "/usr/bin/brave",
      "headless": false
    }
  }
}
```

**To initialize a project:** Run `playwright-cli install` (this just creates the `.playwright/` workspace directory, it does NOT install browsers).

**Connecting to an existing Brave session (preferred):**

The user has the "Playwright MCP Bridge" browser extension installed in his default Brave profile. To connect to an existing browser instead of launching a new one:

```bash
playwright-cli open --extension
```

This connects via the bridge extension and gives access to pages where the user has active sessions (LinkedIn, etc.). The user will approve the tab connection in the browser.

**Key commands:**
- `playwright-cli snapshot` — get page accessibility tree (best for reading page content)
- `playwright-cli goto <url>` — navigate
- `playwright-cli click <ref>` — click element by ref from snapshot
- `playwright-cli type <text>` — type into focused element
- `playwright-cli fill <ref> <text>` — fill a form field
- `playwright-cli tab-list` — list open tabs
- `playwright-cli tab-select <index>` — switch tabs
- `playwright-cli close` — close the browser session

**Do NOT** run `playwright-cli open` without `--extension` unless you specifically need a fresh browser — it launches a new Brave instance with an in-memory profile (no logins).

**Converting scraped pages to Markdown:** Instead of parsing large accessibility tree snapshots in-context, save the page HTML to a file and use the `to-markdown` MCP server to convert it. This uses Cloudflare AI server-side and returns clean Markdown — far fewer tokens than parsing raw snapshots.

```bash
# 1. Save page source to a file
playwright-cli eval "document.documentElement.outerHTML" > /tmp/page.html

# 2. Use the to-markdown MCP tool on the saved file
#    (call mcp__to-markdown__to-markdown with filePaths=["/tmp/page.html"])
```

The `to-markdown` MCP server is installed at `~/.local/share/mcp-server-to-markdown/`. It requires a Cloudflare account. Per-project setup in `.mcp.json`:

```json
{
  "mcpServers": {
    "to-markdown": {
      "command": "bash",
      "args": [
        "-c",
        "export CLOUDFLARE_API_TOKEN=\"$(cat ~/.cloudflare-api-token)\" && export CLOUDFLARE_ACCOUNT_ID=30d94cb16df85f492ca95b88e561a6c2 && exec node ~/.local/share/mcp-server-to-markdown/dist/index.js"
      ]
    }
  }
}
```

Add `"mcp__to-markdown__to-markdown"` to the project's `.claude/settings.local.json` permissions allow list.

## Available CLI Tools

These tools are installed on all machines and can be used freely:

- **`gh`** — GitHub CLI
- **`glab`** — GitLab CLI
- **`npx @playwright/mcp@latest`** — Playwright MCP server (for Claude Code's MCP plugin)
- **`playwright-cli`** — Standalone browser automation CLI (see section above)
- **`az`** — Azure CLI
- **`aws`** — AWS CLI

## General Preferences

- Format Go with `gofmt`
- **CLI arguments over environment variables** — environment variables are the devil because there's no tooling to ask an arbitrary program "what environment variables do you look at?" Any sane CLI-driven program can tell you what arguments it accepts. Use CLI flags with sensible (or sensibly derived) defaults. It's fine to reach into a shared TOML config for values that are too cumbersome for a CLI invocation, but the config file path itself should be a CLI flag.
- Keep things simple — no over-abstraction, no unnecessary dependencies
- Tests should be straightforward table-driven or sequential, using `t.TempDir()` for isolation
