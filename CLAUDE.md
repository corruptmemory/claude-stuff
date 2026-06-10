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

## Open Brain (personal memory MCP) — install on EVERY machine

**Open Brain must be installed on every machine that runs Claude Code.** It's the self-hosted personal memory system: a docker-compose stack running on `node-0` in the basement, fronted by Caddy at `http://open-brain/` on the home LAN. Any Claude Code instance that isn't registered with Open Brain can neither read from nor contribute to the shared brain — that machine is effectively amnesiac relative to every other machine in the fleet.

### Where the `MCP_ACCESS_KEY` comes from (bootstrap order)

The access key is a random 64-char hex value generated when the Open Brain stack was first deployed on `node-0`. The **authoritative source** is node-0's `.env` file:

```
/home/open-brain/repo/integrations/docker-compose-deployment/.env
```

On **any already-configured machine** (like this desktop), a local copy lives in `~/.claude.json` under `mcpServers["open-brain"].headers["x-brain-key"]`. Two ways to retrieve it on a new machine:

**A) Via SSH to node-0** (requires ssh-agent + ForwardAgent already set up — see the i3-screen-manager docs):
```bash
MCP_KEY=$(ssh node-0 "grep '^MCP_ACCESS_KEY=' /home/open-brain/repo/integrations/docker-compose-deployment/.env | cut -d= -f2-")
```

**B) Via `jq` on an already-configured machine**, then copied to the new machine out-of-band:
```bash
# Run on an existing machine that already has open-brain registered:
jq -r '.mcpServers["open-brain"].headers["x-brain-key"]' ~/.claude.json
```

**Bootstrap order when setting up a brand-new machine** (laptop or similar):

1. ssh-agent fix in `~/.local/bin/start-hyprland` (documented in `~/projects/i3-screen-manager/docs/`)
2. Verify `ssh node-0` works cleanly
3. Clone `~/.claude` from `corruptmemory/claude-stuff` (this gives you this CLAUDE.md and the skill symlinks)
4. Clone `~/projects/open-brain` from `corruptmemory/OB1` (this gives the skill symlinks a target to resolve to)
5. Retrieve the key via Option A or B above
6. Run `claude mcp add` (below)
7. Verify

### Register the MCP connection (once per machine, user-scope)

```bash
# --scope user stores the connector globally in ~/.claude.json so it's visible
# in every Claude Code session on this machine, regardless of project directory.
# NOT project-scoped — this is not the kind of thing you re-add per repo.
claude mcp add open-brain http://open-brain/ \
    --transport http \
    --scope user \
    --header "x-brain-key: ${MCP_KEY}"

# Verify:
claude mcp list | grep open-brain    # expect: "http://open-brain/ (HTTP) - ✓ Connected"
```

**Gotcha:** `claude mcp add`'s `--header` flag is variadic (`<header...>`), so **the URL must come immediately after the name**, before any `--header` option — otherwise the URL gets consumed as another header value and you get `error: missing required argument 'commandOrUrl'`.

### Install the Open Brain skills (also once per machine, as symlinks)

The behavioral skills that tell Claude Code *when* to capture thoughts live in the open-brain repo at `~/projects/open-brain/skills/`. Install them as symlinks so `git pull` in the open-brain clone keeps them fresh automatically:

```bash
# Assumes ~/projects/open-brain is a clone of corruptmemory/OB1.
# Clone it first if the machine doesn't have it yet.
for pack in auto-capture claudeception panning-for-gold \
            research-synthesis competitive-analysis \
            heavy-file-ingestion n-agentic-harnesses; do
    ln -s "$HOME/projects/open-brain/skills/$pack" "$HOME/.claude/skills/$pack"
done
```

`auto-capture` is the minimum viable install — it's the one that teaches Claude Code to write session-end decisions back to the brain without being asked. The other six are general workflow packs curated to daily knowledge work.

### Travel devices (laptop) — the LAN URL isn't valid away from home

`http://open-brain/` only resolves on the home LAN because `open-brain` is a local DNS record on the UDM Pro. When the laptop travels (coffee shop wifi, hotel, cellular hotspot), the hostname stops resolving and every `capture_thought` call fails silently. Two solutions — pick one when wiring up the laptop:

**Option A — Tailscale-native endpoint (set-and-forget).** Run `tailscale serve` on `node-0` to expose the MCP endpoint on the tailnet FQDN with auto-provisioned HTTPS. Current syntax varies across Tailscale versions — verify with `tailscale serve --help` and `tailscale serve status` at deploy time. Conceptually:

```bash
# On node-0, once:
tailscale serve --bg --https 8443 / http://127.0.0.1:8000
```

Then the laptop's Claude Code connector uses `https://node-0.taild01c0a.ts.net:8443/` (or similar). Tailscale MagicDNS resolves the tailnet FQDN from anywhere on the tailnet, so the same URL works from home and abroad. MCP server binding stays at `127.0.0.1:8000` because Tailscale Serve runs as a process on node-0 and can reach loopback like anything else.

**Option B — ROFI toggle script (explicit control).** Write a small script at `~/.local/bin/open-brain-toggle-url` that rewrites the `mcpServers.open-brain.url` field in `~/.claude.json` between two values depending on where the laptop currently is:

- `http://open-brain/` when on home LAN (bogusnet / HOME VLAN)
- `http://node-0:8000/` or the Tailscale Serve URL from Option A when traveling

Bind to a ROFI menu entry so it's a one-keypress switch. Adds a manual step on every network change, but matches the "explicit > implicit" aesthetic and is easier to debug than automatic DNS dispatch ("which URL am I on right now?" → `jq '.mcpServers["open-brain"].url' ~/.claude.json`).

**Recommendation:** Start with **Option B** on the laptop while Open Brain is still a young system being iterated on — explicit control accelerates debugging when something breaks. Once the stack is stable and boring, migrate to **Option A** for set-and-forget. The laptop's Claude Code doesn't care which approach you pick; it just reads whatever URL is in `~/.claude.json`.

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

## chrome-devtools-mcp + WebMCP — install on every Brave machine

Brave 148+ ships the WebMCP browser API (`navigator.modelContext`, `navigator.modelContextTesting`) behind a single `chrome://flags` toggle. To let Claude Code drive a WebMCP-aware page through that Brave, you need three pieces wired together: Brave running with the flag on and `--remote-debugging-port=9222`, the `chrome-devtools-mcp` plugin installed, and the plugin's cached manifest hand-patched to point at your Brave on that port. **The patch matters** — by default the plugin spawns its own Puppeteer-managed Chrome that does NOT have the WebMCP flag, so without step 4 below you get generic devtools against a throwaway browser instead of WebMCP against your actual Brave.

### Bootstrap order (per machine)

```bash
# 1. Enable the chrome://flags toggle (once).
#    In Brave: chrome://flags#enable-webmcp-testing → Enabled → Relaunch.
#    Verify (Brave can be running):
jq -r '.browser.enabled_labs_experiments[]' \
    ~/.config/BraveSoftware/Brave-Browser/Local\ State | grep webmcp
# expect: enable-webmcp-testing@1

# 2. Make sure Brave is launched with --remote-debugging-port=9222.
#    Typically baked into your launcher .desktop file or window-manager config.
#    Verify:
curl -s http://127.0.0.1:9222/json/version | jq -r .Browser
# expect: Chrome/148.x.x.x (or newer)

# 3. Install the plugin (user-scope auto-applied).
claude plugin install chrome-devtools-mcp

# 4. Hand-patch the cached manifests to point at the running Brave.
#    The upstream plugin manifest in claude-plugins-official 1.0.1 dropped the
#    default --browserUrl arg, so without this patch the plugin spawns its own
#    (flagless) Puppeteer Chrome.  Idempotent — safe to re-run after updates.
for DIR in ~/.claude/plugins/cache/claude-plugins-official/chrome-devtools-mcp/*/; do
    for f in "${DIR}.mcp.json" "${DIR}.claude-plugin/plugin.json"; do
        jq '.mcpServers["chrome-devtools"].args |=
            (. - ["--browserUrl", "http://127.0.0.1:9222"])
            + ["--browserUrl", "http://127.0.0.1:9222"]' \
            "$f" > "$f.new" && mv "$f.new" "$f"
    done
done

# 5. Restart any running Claude Code session — MCP servers are launched once
#    per session and won't pick up the new args until relaunch.

# 6. Verify the plugin connects through to your Brave (not its own Chrome).
claude mcp list | grep chrome-devtools
# expect: plugin:chrome-devtools-mcp:chrome-devtools: npx chrome-devtools-mcp@latest --browserUrl http://127.0.0.1:9222 - ✓ Connected
```

### Verify WebMCP is actually exposed in Brave

Direct CDP probe via Node's built-in `WebSocket` (Node 21+, no npm deps). Open any real (non-`chrome://`) page in Brave first:

```bash
node -e '
(async () => {
  const targets = (await (await fetch("http://127.0.0.1:9222/json")).json())
    .filter(t => t.type === "page" && !t.url.startsWith("chrome://") && t.webSocketDebuggerUrl);
  if (!targets.length) { console.log("Open a real page in Brave first."); return; }
  const ws = new WebSocket(targets[0].webSocketDebuggerUrl);
  await new Promise(r => ws.addEventListener("open", r, {once: true}));
  ws.send(JSON.stringify({id: 1, method: "Runtime.evaluate", params: {
    expression: "JSON.stringify({mc: typeof navigator.modelContext, mct: typeof navigator.modelContextTesting})",
    returnByValue: true,
  }}));
  const msg = await new Promise(r => ws.addEventListener("message", e => r(JSON.parse(e.data)), {once: true}));
  console.log(msg.result.result.value);
  ws.close();
})();
'
# expect: {"mc":"object","mct":"object"}
```

### Gotchas

- **The cache patch is fragile.** `claude plugin update chrome-devtools-mcp` will overwrite both `.mcp.json` and `.claude-plugin/plugin.json` from upstream. Re-run step 4 after every plugin update. Long-term fix: either the upstream marketplace pin needs to restore the `--browserUrl` default, or the plugin manifest needs a `userConfig` section so `settings.json -> pluginConfigs.chrome-devtools-mcp@claude-plugins-official.mcpServers.chrome-devtools` can override the args durably. Worth a PR upstream when motivated.
- **Don't add `--categoryExperimentalWebmcp` to the args on Brave 148.** That flag enables a dedicated WebMCP tool category inside chrome-devtools-mcp but requires Chromium 149+ AND a `DevToolsWebMCPSupport` feature flag that Brave 148 doesn't expose. Add it when Brave updates past 149.
- **`evaluate_script` is the working path on Brave 148.** Anything you can do via direct CDP JS eval against `navigator.modelContext` / `navigator.modelContextTesting`, the plugin can do via its `evaluate_script` tool. That's sufficient for WebMCP-aware pages today.
- **Permissions:** Don't forget to add the **chrome-devtools-mcp block** to `.claude/settings.local.json` per project — see the next section.

## MCP Plugin Permissions (stop the prompting)

The `mcp__*` wildcard in global `settings.json` does NOT actually suppress prompts for MCP tools. You must enumerate every tool explicitly in `.claude/settings.local.json` per project.

**Setup procedure for a new project (`just installed Claude Code here` / `first time in this dir`):**

1. Run `claude mcp list` to see which MCP servers are connected on this machine.
2. Always include the **Base plugins block** below (playwright + serena + context7).
3. **ALWAYS** check for `open-brain` in `claude mcp list`. If present (expected on every machine — see the "Open Brain" section), add the **open-brain block**. If it's *missing*, stop and bootstrap open-brain before continuing — a machine without open-brain is amnesiac relative to the rest of the fleet.
4. Check for `perplexity` in `claude mcp list`. If present, add the **perplexity block**.
5. Check for `plugin:chrome-devtools-mcp:chrome-devtools` in `claude mcp list`. If present (expected on every machine with a debug-enabled Brave — see the "chrome-devtools-mcp + WebMCP" section above), add the **chrome-devtools-mcp block**.
6. If any other MCP server shows up that prompts during use, enumerate its tools the same way and consider whether it's worth adding to this recipe for future projects.

Tool names follow the pattern `mcp__plugin_<pluginname>_<servername>__<toolname>` for plugin-hosted servers, or `mcp__<servername>__<toolname>` for directly-registered servers (like open-brain and perplexity — these were added via `claude mcp add`, not via the plugin system, so they skip the `plugin_` infix).

---

### Base plugins block (always include)

```json
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
```

### open-brain block (add whenever `open-brain` is in `claude mcp list` — should be every machine)

```json
"mcp__open-brain__capture_thought",
"mcp__open-brain__coalesce_thoughts",
"mcp__open-brain__delete_thought",
"mcp__open-brain__find_similar_thoughts",
"mcp__open-brain__list_thoughts",
"mcp__open-brain__search_thoughts",
"mcp__open-brain__thought_stats"
```

### perplexity block (add if `perplexity` is in `claude mcp list`)

```json
"mcp__perplexity__perplexity_ask",
"mcp__perplexity__perplexity_reason",
"mcp__perplexity__perplexity_research",
"mcp__perplexity__perplexity_search"
```

### chrome-devtools-mcp block (add when `plugin:chrome-devtools-mcp:chrome-devtools` is in `claude mcp list`)

```json
"mcp__plugin_chrome-devtools-mcp_chrome-devtools__click",
"mcp__plugin_chrome-devtools-mcp_chrome-devtools__close_page",
"mcp__plugin_chrome-devtools-mcp_chrome-devtools__drag",
"mcp__plugin_chrome-devtools-mcp_chrome-devtools__emulate",
"mcp__plugin_chrome-devtools-mcp_chrome-devtools__evaluate_script",
"mcp__plugin_chrome-devtools-mcp_chrome-devtools__fill",
"mcp__plugin_chrome-devtools-mcp_chrome-devtools__fill_form",
"mcp__plugin_chrome-devtools-mcp_chrome-devtools__get_console_message",
"mcp__plugin_chrome-devtools-mcp_chrome-devtools__get_network_request",
"mcp__plugin_chrome-devtools-mcp_chrome-devtools__handle_dialog",
"mcp__plugin_chrome-devtools-mcp_chrome-devtools__hover",
"mcp__plugin_chrome-devtools-mcp_chrome-devtools__lighthouse_audit",
"mcp__plugin_chrome-devtools-mcp_chrome-devtools__list_console_messages",
"mcp__plugin_chrome-devtools-mcp_chrome-devtools__list_network_requests",
"mcp__plugin_chrome-devtools-mcp_chrome-devtools__list_pages",
"mcp__plugin_chrome-devtools-mcp_chrome-devtools__navigate_page",
"mcp__plugin_chrome-devtools-mcp_chrome-devtools__new_page",
"mcp__plugin_chrome-devtools-mcp_chrome-devtools__performance_analyze_insight",
"mcp__plugin_chrome-devtools-mcp_chrome-devtools__performance_start_trace",
"mcp__plugin_chrome-devtools-mcp_chrome-devtools__performance_stop_trace",
"mcp__plugin_chrome-devtools-mcp_chrome-devtools__press_key",
"mcp__plugin_chrome-devtools-mcp_chrome-devtools__resize_page",
"mcp__plugin_chrome-devtools-mcp_chrome-devtools__select_page",
"mcp__plugin_chrome-devtools-mcp_chrome-devtools__take_heapsnapshot",
"mcp__plugin_chrome-devtools-mcp_chrome-devtools__take_screenshot",
"mcp__plugin_chrome-devtools-mcp_chrome-devtools__take_snapshot",
"mcp__plugin_chrome-devtools-mcp_chrome-devtools__type_text",
"mcp__plugin_chrome-devtools-mcp_chrome-devtools__upload_file",
"mcp__plugin_chrome-devtools-mcp_chrome-devtools__wait_for"
```

---

### Full template — wrap the selected blocks like this:

```json
{
  "permissions": {
    "allow": [
      // ... paste selected blocks here, comma-separated ...
    ]
  }
}
```

(JSON doesn't actually allow comments — they're shown above for clarity. Strip them before saving.)

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

## marksnip (preferred web page reading)

**`marksnip` is the preferred way to read web pages.** It uses the MarkSnip browser extension in Brave to convert any page to clean Markdown via a local native messaging bridge. No cloud relay, no feature flags, works with authenticated sessions.

Binary: `~/.local/bin/marksnip` (symlinked from `~/projects/marksnip/marksnip`)

**To read a URL:**
```bash
xdg-open "https://example.com" && sleep 3 && marksnip clip --fresh
```
For heavy JS pages use `sleep 5`. The `--fresh` flag bypasses cache and forces a live capture.

**To read the currently active Brave tab:**
```bash
marksnip clip
```

**JSON output** (includes url, title, markdown, capturedAt):
```bash
marksnip clip --json
```

**Why marksnip over other tools:**
- **vs WebFetch/Perplexity**: sees the actual rendered page in the user's authenticated browser — no paywalls, no stale caches, no JS rendering issues
- **vs playwright-cli/Claude-in-Chrome**: much cheaper (clean Markdown vs HTML or accessibility trees), no ref-tracking, no YAML parsing
- **vs all scraping tools**: works on any site the user is logged into

**Check bridge status:** `marksnip status` — should show `chrome: connected`

## Claude in Chrome (NOT WORKING on Brave — skip)

Claude in Chrome does not work on Brave due to a server-side feature flag (`chrome_ext_bridge_enabled`) that Anthropic only enables for Chrome and Edge. The extension installs fine but the WebSocket bridge to `bridge.claudeusercontent.com` never connects. Use marksnip instead for all web reading tasks.

## playwright-cli (fallback browser automation)

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

## Output discipline — `print` vs `log`/`log_error` (Jai, Odin, native projects)

The choice between `print` and `log`/`log_error` is decided by **suppressibility**, not by file
type ("library vs example" is just a frequent consequence):

- **`print`** — first-class / expected output: a human, or a log entry / enclosing script, will
  almost certainly consume it (a tool's results, a CLI's usage/progress, a test's pass/fail). Test:
  *if a no-op logger dropped this line, would the tool fail its contract or someone reasonably
  complain?* Yes → `print`.
- **`log`** — elective output a quiet logger could drop with nobody reasonably complaining (runtime
  diagnostics, debug dumps, status chatter). The only quietable tier is plain `log` (INFO).
- **`log_error`** — a **failure**, handed to the context's logger, which OWNS where it goes and how
  it is surfaced. **Never suppressed.** The logger is a build/context decision: in a dev build it may
  just hit stderr, but a release logger's contract is *the failure WILL reach the user* — log file,
  OS log, and, as the fallback that matters, an **emergency lowest-common-denominator GUI surface** (a
  message box). A GUI/game user never had a terminal open; a failed Vulkan init on release must TELL
  them, not die silently. The silent-failing Steam game is the anti-pattern we refuse. `.WARNING`
  likewise always emits; only INFO is quietable.

`print` and `log_error` both always reach a human, but are not interchangeable: `print` is the
intended deliverable (hardwired to stdout, no surfacing policy); `log_error` hands a failure to the
logger whose policy is "never silent." That is the whole reason errors route through `log_error`
rather than `print` or a raw write. Classify per the program's *contract*, not the message text —
CLI / CLI-GUI hybrids are print-dominant (most output is first-class); GUIs/games and libraries are
log-dominant. Mechanical exception: a `#c_call` / no-`context` callback can't reach `log*`, so
`print` there.

This serves a hard standard: **no silent failures, ever.**

**Testing corollary.** Because errors route through the pluggable context logger, a test is just
another logger-context: install an error-recording logger around the code under test and errors
become an assertable side-channel — testable even for **void functions** with no error return.

- *Positive test* (no error expected): record `.ERROR`; fail if any were logged. Make this the
  default harness behavior so 'no unexpected errors' is a free, suite-wide assertion; it also catches
  errors a function deliberately swallows-and-continues.
- *Negative test* (error expected): a spectrum, cheapest rung first — *an error fired*
  (`rec.errors.count > 0`) is the robust default (immune to message drift, but can false-green if an
  UNRELATED error masked the one you meant to test); climb to a STABLE handle
  (`Log_Info.user_flags` / `section` / `source_identifier`) when identity matters; message-string
  matching is the brittle last resort but still a usable hook. The discipline guarantees the hook
  exists for free; how tightly you grab it is a per-test dial.

Blind spot: the `#c_call` / no-`context` `print` exception bypasses the logger, so errors there are
not captured. Reference recorder (Jai; Odin's `context.logger` is analogous):

```jai
Error_Recorder :: struct { errors: [..] string; }

record_errors :: (message: string, data: *void, info: Log_Info) {
    if info.common_flags & .ERROR {
        rec := cast(*Error_Recorder) data;
        array_add(*rec.errors, copy_string(message));
    }
}

// around the code under test:
rec: Error_Recorder;
ctx := context;
ctx.logger      = record_errors;
ctx.logger_data = *rec;
push_context ctx {
    thing_under_test();           // even with no return value
}
assert(rec.errors.count == 0);    // positive test; invert the assertion for negative tests
```
