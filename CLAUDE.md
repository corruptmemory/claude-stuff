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

## Platform: Arch Linux with Brave Origin

This machine runs Arch Linux. Chrome is **not installed**. The browser is **Brave Origin** at `/usr/bin/brave-origin` (the older Brave at `/usr/bin/brave` was removed in the 2026-06 Brave → Brave Origin migration).

**Playwright MCP setup:** The Playwright plugin must use Brave Origin instead of Chrome. Configure by editing the plugin's `.mcp.json`:

```bash
# Find the plugin config (hash changes on updates):
find ~/.claude/plugins/cache -path '*/playwright/*/.mcp.json'

# It should contain:
```
```json
{
  "playwright": {
    "command": "npx",
    "args": ["@playwright/mcp@latest", "--executable-path", "/usr/bin/brave-origin"]
  }
}
```

**If Playwright fails with "Chromium distribution 'chrome' is not found":**
1. Find the `.mcp.json` with the command above
2. Add `"--executable-path", "/usr/bin/brave-origin"` to the args array
3. Restart Claude Code (the MCP server caches the old config)

**Never** run `npx playwright install` — it tries to install Chrome and fails on Arch. The `--executable-path` flag is discovered via `npx @playwright/mcp@latest --help`.

## chrome-devtools-mcp + WebMCP — install on every Brave Origin machine

> ✅ Brave → Brave Origin migration (2026-06): paths below point at `Brave-Origin`.
> WebMCP IS supported in Brave Origin and is PROVEN working end-to-end — **re-verified
> on Brave Origin 152.1.94.117 (Chromium 152), 2026-08-28**: both
> `chrome://flags#enable-webmcp-testing` and `chrome://flags#devtools-webmcp-support`
> are present and Enabled, and a self-registered demo page's tools were discovered and
> executed over CDP. The *stripped* Origin build keeps WebMCP.
>
> ⚠️ **API RENAME (Chrome 150): the page entry point is now `document.modelContext`, NOT
> `navigator.modelContext`.** On Chromium 152 `navigator.modelContext` and
> `navigator.modelContextTesting` are GONE; the interface `window.ModelContext` remains, and
> the working entry point is `document.modelContext` (methods `registerTool`, `getTools`,
> `executeTool`, `ontoolchange`). Agent-side consumption = `document.modelContext.getTools()` /
> `.executeTool(tool, jsonArgs)` over CDP — the `modelContextTesting` harness is gone and is NOT
> restorable by any flag (tested `--enable-blink-test-features`, `--enable-experimental-web-platform-features`,
> `--enable-features=WebMCP`, `--enable-blink-features=WebMCP`; none bring it back). All probes/examples
> below were updated `navigator.` → `document.`.
>
> ⚠️ **Ignore any "Brave Origin strips WebMCP" claim** (e.g. a Google AI Overview): it conflates
> **Brave Leo** (an AI assistant Origin *does* strip) with **WebMCP** (an upstream Chromium web
> API Origin *keeps*). Ground truth: `document.modelContext` is live in Origin — the claim is wrong.

Brave Origin ships the WebMCP browser API (page entry point `document.modelContext` — renamed from `navigator.modelContext` in Chrome 150; see the ⚠️ note above) behind two `chrome://flags` toggles — `#enable-webmcp-testing` (the API + testing interfaces) and `#devtools-webmcp-support` (the DevTools WebMCP category). To let Claude Code drive a WebMCP-aware page through that Brave, you need three pieces wired together: Brave running with the flag on and `--remote-debugging-port=9222`, the `chrome-devtools-mcp` plugin installed, and the plugin's cached manifest hand-patched to point at your Brave on that port. **The patch matters** — by default the plugin spawns its own Puppeteer-managed Chrome that does NOT have the WebMCP flag, so without step 4 below you get generic devtools against a throwaway browser instead of WebMCP against your actual Brave.

### Bootstrap order (per machine)

```bash
# 1. Enable the chrome://flags toggles (once). Brave Origin 152 exposes BOTH:
#      chrome://flags#enable-webmcp-testing   → Enabled  (WebMCP API + testing)
#      chrome://flags#devtools-webmcp-support → Enabled  (DevTools WebMCP category)
#    Then Relaunch. Verify (Brave can be running):
jq -r '.browser.enabled_labs_experiments[]' \
    ~/.config/BraveSoftware/Brave-Origin/Local\ State | grep webmcp
# expect: devtools-webmcp-support@1  and  enable-webmcp-testing@1

# 2. Make sure Brave is launched with --remote-debugging-port=9222.
#    Typically baked into your launcher .desktop file or window-manager config.
#    Verify:
curl -s http://127.0.0.1:9222/json/version | jq -r .Browser
# expect: Chrome/152.x.x.x (or newer)

# 3. Install the plugin (user-scope auto-applied).
claude plugin install chrome-devtools-mcp

# 4. Hand-patch the cached manifests to point at the running Brave.
#    The upstream plugin manifest in claude-plugins-official 1.0.1 dropped the
#    default --browserUrl arg, so without this patch the plugin spawns its own
#    (flagless) Puppeteer Chrome.  Idempotent — safe to re-run after updates.
for DIR in ~/.claude/plugins/cache/claude-plugins-official/chrome-devtools-mcp/*/; do
    for f in "${DIR}.mcp.json" "${DIR}.claude-plugin/plugin.json"; do
        [ -f "$f" ] || continue   # layout is version-pinned .claude-plugin/plugin.json; no top-level .mcp.json
        jq '.mcpServers["chrome-devtools"].args |=
            (. - ["--browserUrl", "http://127.0.0.1:9222", "--categoryExperimentalWebmcp"])
            + ["--browserUrl", "http://127.0.0.1:9222", "--categoryExperimentalWebmcp"]' \
            "$f" > "$f.new" && mv "$f.new" "$f"
    done
done

# 5. Restart any running Claude Code session — MCP servers are launched once
#    per session and won't pick up the new args until relaunch.

# 6. Verify the plugin connects through to your Brave (not its own Chrome).
claude mcp list | grep chrome-devtools
# expect: plugin:chrome-devtools-mcp:chrome-devtools: npx chrome-devtools-mcp@latest --browserUrl http://127.0.0.1:9222 --categoryExperimentalWebmcp - ✓ Connected
```

### Verify WebMCP is actually exposed in Brave

Direct CDP probe via Node's built-in `WebSocket` (Node 21+, no npm deps). Open any real (non-`chrome://`) page in Brave first. **On Chromium 150+ the entry point is `document.modelContext`** — the old `navigator.modelContext` / `navigator.modelContextTesting` were removed:

```bash
node -e '
(async () => {
  const targets = (await (await fetch("http://127.0.0.1:9222/json")).json())
    .filter(t => t.type === "page" && !t.url.startsWith("chrome://") && t.webSocketDebuggerUrl);
  if (!targets.length) { console.log("Open a real page in Brave first."); return; }
  const ws = new WebSocket(targets[0].webSocketDebuggerUrl);
  await new Promise(r => ws.addEventListener("open", r, {once: true}));
  ws.send(JSON.stringify({id: 1, method: "Runtime.evaluate", params: {
    expression: "JSON.stringify({dm: typeof document.modelContext, nav: typeof navigator.modelContext})",
    returnByValue: true,
  }}));
  const msg = await new Promise(r => ws.addEventListener("message", e => r(JSON.parse(e.data)), {once: true}));
  console.log(msg.result.result.value);
  ws.close();
})();
'
# expect (Chromium 152+): {"dm":"object","nav":"undefined"}  — the page API is document.modelContext now.
#   (Old Brave 149: navigator.modelContext/…Testing → {"mc":"object","mct":"object"}.)
```

### Consume a WebMCP page's tools as the agent (PROVEN 2026-08-28, Brave Origin 152)

A WebMCP-aware page registers tools with `document.modelContext.registerTool({name, description,
inputSchema, execute})`. Acting as the agent over CDP, discover + invoke them (async → `awaitPromise: true`):

```js
// inside Runtime.evaluate on the target page: awaitPromise:true, returnByValue:true
(async () => {
  const tools = await document.modelContext.getTools();                 // discover
  const t = tools.find(x => x.name === "add_numbers");
  return await document.modelContext.executeTool(t, JSON.stringify({a:2, b:40}));  // invoke
})()
// Proven end-to-end: a localhost demo registered add_numbers/reverse_text; getTools() found both,
// executeTool() returned "The sum of 2 and 40 is 42." and the reversed string. No modelContextTesting
// harness needed — that surface is gone on 152; the direct-CDP / DevTools path replaced it.
```

### Gotchas

- **The cache patch is fragile.** `claude plugin update chrome-devtools-mcp` will overwrite both `.mcp.json` and `.claude-plugin/plugin.json` from upstream. Re-run step 4 after every plugin update. Long-term fix: either the upstream marketplace pin needs to restore the `--browserUrl` default, or the plugin manifest needs a `userConfig` section so `settings.json -> pluginConfigs.chrome-devtools-mcp@claude-plugins-official.mcpServers.chrome-devtools` can override the args durably. Worth a PR upstream when motivated.
- **`--categoryExperimentalWebmcp` on Brave Origin 152.** This arg enables a dedicated WebMCP tool category inside chrome-devtools-mcp; it requires Chromium 149+ AND the `DevToolsWebMCPSupport` feature flag — both satisfied by Brave Origin 152 (`#devtools-webmcp-support` present and Enabled). Add it to the plugin args (alongside `--browserUrl` in step 4) to get the dedicated category. NOTE (2026-08-28): the underlying WebMCP is proven working end-to-end via raw CDP (`document.modelContext.getTools/executeTool`), but the *plugin* category is currently untested because the plugin lost its `--browserUrl` patch and spawns its own (missing) Chrome — re-apply step 4 + restart the session before relying on the category.
- **Direct CDP eval is the reliable path on Brave Origin 152.** Anything you can do via direct CDP JS eval against `document.modelContext` (`getTools()` / `executeTool()`), the plugin can do via its `evaluate_script` tool — a solid fallback even if `--categoryExperimentalWebmcp` isn't wired up. This is exactly how the end-to-end proof ran (raw Node `WebSocket` → `Runtime.evaluate`), independent of the plugin.
- **Permissions:** Don't forget to add the **chrome-devtools-mcp block** to `.claude/settings.local.json` per project — see the next section.

## MCP Plugin Permissions (stop the prompting)

The `mcp__*` wildcard in global `settings.json` does NOT actually suppress prompts for MCP tools. You must enumerate every tool explicitly in `.claude/settings.local.json` per project.

**Setup procedure for a new project (`just installed Claude Code here` / `first time in this dir`):**

1. Run `claude mcp list` to see which MCP servers are connected on this machine.
2. Always include the **Base plugins block** below (playwright + context7). (Serena was fully uninstalled 2026-08-01 — usage analysis showed 5 calls in two months against a 33-line permissions block per project. Do not re-add its entries.)
3. **ALWAYS** check for `open-brain` in `claude mcp list`. If present (expected on every machine — see the "Open Brain" section), add the **open-brain block**. If it's *missing*, stop and bootstrap open-brain before continuing — a machine without open-brain is amnesiac relative to the rest of the fleet.
4. Check for `perplexity` in `claude mcp list`. If present, add the **perplexity block**.
5. Check for `plugin:chrome-devtools-mcp:chrome-devtools` in `claude mcp list`. If present (expected on every machine with a debug-enabled Brave — see the "chrome-devtools-mcp + WebMCP" section above), add the **chrome-devtools-mcp block**.
6. Check for the claude.ai **Google Workspace** connectors — `claude.ai Gmail`, `claude.ai Google Drive`, `claude.ai Google Calendar` — in `claude mcp list`. If present and `✔ Connected`, add the **Google Workspace block**. These are OAuth *cloud connectors managed by claude.ai* (enabled/authed from the `/plugin` → connectors UI or claude.ai), **not** `claude mcp add` and **not** plugins — so their tool names use the `mcp__claude_ai_<Server>__<tool>` shape (a `claude_ai_` prefix, no `plugin_` infix). Verified `✔ Connected` on `godlike-artix` 2026-08-01. Note: the older Anthropic-hosted Google connectors (`gmail.mcp.claude.com`, `gcal.mcp.claude.com`) are deprecated and sit in a local blocked-hosts flag; the *current* ones are Google-hosted (`gmailmcp.googleapis.com`, `calendarmcp.googleapis.com`, `drivemcp.googleapis.com`) and are unaffected by that flag.
7. If any other MCP server shows up that prompts during use, enumerate its tools the same way and consider whether it's worth adding to this recipe for future projects.

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

### Google Workspace block (add when `claude.ai Gmail` / `claude.ai Google Drive` / `claude.ai Google Calendar` are `✔ Connected` in `claude mcp list`)

These are claude.ai OAuth cloud connectors — `mcp__claude_ai_<Server>__<tool>` (a `claude_ai_` prefix, no `plugin_` infix). Gmail deliberately has **no send tool** — only `create_draft`/`update_draft` — so auto-allowing these cannot send mail on your behalf. The write/mutate tools ARE included below (Calendar `create`/`update`/`delete_event`, Drive `create_file`/`copy_file`, Gmail label + draft edits); trim to the read-only subset (`search_*`, `list_*`, `get_*`, `read_file_content`, `download_file_content`) if you'd rather be prompted before any mutation.

```json
"mcp__claude_ai_Gmail__apply_sensitive_message_label",
"mcp__claude_ai_Gmail__apply_sensitive_thread_label",
"mcp__claude_ai_Gmail__create_draft",
"mcp__claude_ai_Gmail__create_label",
"mcp__claude_ai_Gmail__delete_label",
"mcp__claude_ai_Gmail__get_message",
"mcp__claude_ai_Gmail__get_thread",
"mcp__claude_ai_Gmail__label_message",
"mcp__claude_ai_Gmail__label_thread",
"mcp__claude_ai_Gmail__list_drafts",
"mcp__claude_ai_Gmail__list_labels",
"mcp__claude_ai_Gmail__search_threads",
"mcp__claude_ai_Gmail__unlabel_message",
"mcp__claude_ai_Gmail__unlabel_thread",
"mcp__claude_ai_Gmail__update_draft",
"mcp__claude_ai_Gmail__update_label",
"mcp__claude_ai_Google_Calendar__create_event",
"mcp__claude_ai_Google_Calendar__delete_event",
"mcp__claude_ai_Google_Calendar__get_event",
"mcp__claude_ai_Google_Calendar__list_calendars",
"mcp__claude_ai_Google_Calendar__list_events",
"mcp__claude_ai_Google_Calendar__respond_to_event",
"mcp__claude_ai_Google_Calendar__search_events",
"mcp__claude_ai_Google_Calendar__suggest_time",
"mcp__claude_ai_Google_Calendar__update_event",
"mcp__claude_ai_Google_Drive__copy_file",
"mcp__claude_ai_Google_Drive__create_file",
"mcp__claude_ai_Google_Drive__download_file_content",
"mcp__claude_ai_Google_Drive__get_file_metadata",
"mcp__claude_ai_Google_Drive__get_file_permissions",
"mcp__claude_ai_Google_Drive__list_recent_files",
"mcp__claude_ai_Google_Drive__read_file_content",
"mcp__claude_ai_Google_Drive__search_files"
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

> **Always use the `glab` CLI for GitLab — never the GitLab MCP plugin/server.**
> The official GitLab MCP server (`https://gitlab.com/api/v4/mcp`) is
> **OAuth-DCR-only**: its required `mcp` token scope is **not creatable as a PAT
> scope** (gitlab-org/gitlab#554826), so there is no `Authorization: Bearer <PAT>`
> workaround, and Claude Code's OAuth handshake to GitLab fails (browser consent
> completes but no token ever persists — most likely GitLab advertising only
> `plain` PKCE, which strict MCP OAuth clients reject). The
> `gitlab@claude-plugins-official` plugin was uninstalled and fully purged
> (plugin cache, `mcpServers`, `enabledPlugins`, `pluginUsage`) on `godlike-artix`
> **2026-08-01**; **do not reinstall it.** `glab` is already authenticated
> (`corruptmemory`) and covers MRs, issues, pipelines, and repos. (The
> `claude-plugins-official` marketplace still *lists* gitlab as installable — that
> is the catalog, not residue, and it regenerates on marketplace refresh; leave
> it be.)

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

## Internet-access & research lanes — use them to their fullest

**Principle — this is an ENABLING instruction, not a restriction:** your answers are only as good as
the information you can reach, and Jim, as a human, can reach more of the web than a default agent can
(logged-in pages, paywalls, sites that block bots). Close that gap. Reach for these lanes aggressively
instead of settling for a model-only answer or a bot-blockable fetch. **Level the playing field.**

Four lanes, best used in combination. Match the lane to the job; cross-check load-bearing facts across
at least two lanes, and land anything that matters on a primary source. The ground-truth check beats the
confident summary — on 2026-08-28 a Google AI Overview got WebMCP flatly wrong while a browser probe was right.

### 1. Jim's real browser (his authenticated Brave) — strongest lane for ACCESS
His logged-in, human-reputation Brave defeats paywalls, logins, and bot/agent blocks that stop fetch
tools cold. Prefer it for reading real pages (details in the marksnip and "chrome-devtools-mcp + WebMCP" sections).
- **Read a page:** `marksnip` — clean Markdown from his live/authenticated tab.
- **Drive / run JS / read JS-heavy or gated pages:** raw CDP on `127.0.0.1:9222` (Brave launched with
  `--remote-debugging-port=9222`) — `curl http://127.0.0.1:9222/json` to list tabs, then a Node 21+
  `WebSocket` to a target's `webSocketDebuggerUrl` + `Runtime.evaluate`. Works even when the
  chrome-devtools-mcp plugin is mis-patched (spawns its own Chrome) — the raw path needs no plugin.
- **Interactive (click/type/forms):** `playwright-cli open --extension`, or the chrome-devtools-mcp plugin.
- **WebMCP:** on cooperating pages, consume structured tools via `document.modelContext.getTools()` /
  `.executeTool()` over CDP (proven end-to-end 2026-08-28).
- **Boundary:** treat his email/banking/personal tabs as off-limits unless he assigns a task there.

### 2. Perplexity (MCP, `✔ Connected`) — discovery + web-grounded synthesis with citations
`perplexity_search` (find URLs/facts/recent news), `perplexity_ask` (cited answers, fast),
`perplexity_research` (deep, slow), `perplexity_reason` (step-by-step). Great for mapping terrain and
finding authoritative URLs — then read the load-bearing sources through his browser (lane 1). The
citations are checkable; check them.

### 3. `codex` CLI — a second, independent AI-agent lane
OpenAI's Codex CLI (`codex-cli`, native install at `~/.local/bin/codex`). Non-interactive:
**`codex exec "<prompt>"`** (alias `codex e`); `codex review` for non-interactive code review. Use it as a
parallel/independent worker — a separate research pass, an API-hitting task, or a cross-check against my
own conclusion (it has its own model + tool access). Verify its output like any agent's; it can be
confidently wrong.

### 4. `agy` CLI — Google-grounded breadth lane (⚠️ caveated)
**`agy --print "<prompt>"`** (`-p`; `--output-format text|json|stream-json`, `--json-schema` for structured
output, `--model`, `--effort low|medium|high`). Google-grounded, so good for BREADTH and leads.
**⚠️ agy FABRICATES specifics** — in the 2026-08-10 AUR supply-chain assessment its lane invented details;
nothing it returns is load-bearing. Use it ONLY for discovery/leads, and confirm every concrete claim
(dates, versions, quotes, URLs) against a primary source or lane 1/2 before relying on it.

### Combining the lanes
- Breadth / discovery: perplexity + agy (agy strictly for leads).
- Read the real / authoritative / gated content: his browser (lane 1).
- Independent second opinion or parallel grind: codex.
- Always: cross-check load-bearing facts across ≥2 lanes and settle them on a primary source.

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
      "executablePath": "/usr/bin/brave-origin",
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
- **Git forges — first-party CLIs, never forge MCP plugins.** Whatever git forge is in play, reach for its **first-party CLI**: `gh` for GitHub, `glab` for GitLab, and whatever the forge itself ships for anything else. This is the default **unless a specific repo says otherwise** — that exception exists in principle (a repo needing some "extra sauce" only an MCP/plugin provides) but in practice is vanishingly rare, so treat "find and use the forge's own CLI" as the standing rule and only deviate on an explicit, per-repo basis. Do **not** install or use forge *MCP plugins*: the GitLab MCP plugin's OAuth handshake is broken with Claude Code (details in the `glab` section above) and the GitKraken plugin is a paid, redundant forge-unifier. Both were uninstalled and fully purged on `godlike-artix` **2026-08-01**; do not reinstall either.
- Keep things simple — no over-abstraction, no unnecessary dependencies
- Tests should be straightforward table-driven or sequential, using `t.TempDir()` for isolation
- **Package installs — AUR is hostile-by-default (post-2026 Atomic incident).** Six-rung decision procedure lives in `~/projects/i3-screen-manager/docs/install-paths-cheatsheet.md`: (1) Artix/Arch repos, (2) vendor's own native installer with auto-update, (3) `pipx` for Python tools, (4) `docker run` for occasional-use, (5) local PKGBUILD fork (the Odin trick, see Odin section below), (6) AUR direct after `aur-malware-check`. Worked examples: Claude Code / Codex / Brave Origin all took rung 2; Odin is rung 5. When suggesting an install path or when the user asks where to get something new, consult that doc rather than defaulting to `yay -S`. The doc also lists the trap classes (`sudo pip install`, `sudo npm install -g`, random Docker Hub images) that look like a rung but aren't.

## Odin — install from the private `odin-git-local` fork (both machines)

**Odin is installed from a private fork of the AUR `odin-git` PKGBUILD, NOT from
the AUR directly.** This keeps the AUR out of the trust path (fits the AUR
off-limits posture): `makepkg` reads the forked recipe and fetches only its
`source=` (the official `github.com/odin-lang/odin.git`); the AUR is never
contacted, but full pacman integration is kept (`/usr/bin/odin`, `pacman -Q`,
clean `pacman -R odin-git-local`).

- **Repo:** `github.com/corruptmemory/odin-git-local` (PRIVATE, GitHub / `gh`).
- **Install on a machine:**
  ```bash
  git clone git@github.com:corruptmemory/odin-git-local.git
  cd odin-git-local && makepkg -si
  ```
- **pkgname** is `odin-git-local`, `provides/conflicts=(odin odin-git)` — cannot
  coexist with AUR `odin-git`, still satisfies `odin` deps.

**Why the fork exists:** the AUR `odin-git` `check()` went stale against upstream
(broken since ~`2026-07-14`). Two causes: (1) upstream PR #7034 (commit
`f308d92`) replaced the vendor Makefiles (`vendor/{stb,cgltf,miniaudio}/src/`)
with `build_*.sh` scripts, so `make -C vendor/stb/src` fails ("No targets
specified and no makefile found", exit 4); (2) `examples/all` now also imports
the `kb_text_shape` vendor lib the recipe never built. Our `check()` mirrors
upstream `.github/workflows/ci.yml` (build the 4 vendor libs the CI way, then
`odin check examples/all -strict-style`) and drops the four heavy `odin test`
suites. Full rationale in the repo's `README.md`.

**Maintenance:** it is a `-git` package (always builds master), so `check()` can
break again whenever upstream changes its build/test layout. On a `check()`
failure: diff upstream `ci.yml` vs our `check()`, re-sync, bump `pkgrel`,
`makepkg --printsrcinfo > .SRCINFO`, commit, push, then `git pull && makepkg -si`
on both machines. (Desktop `godlike-artix` done `2026-08-03`; laptop
`nomad-artix` done `2026-08-11` — installed at `r18504.5f321d687-1`, verified
compile+run smoke test.)

## Jai Language Skill — a compile-verified reference (`~/.claude/skills/jai-language/`)

Jai is not in wide use, so model training data on it is sparse and badly out of date. The
`jai-language` skill exists to be a *reliable enough* reference that first-pass Jai codegen at
least compiles. It is not a hand-written cheat sheet you trust on faith — it is **proof-backed**.
Invoke the skill (and read its `SKILL.md`) before writing Jai; the full process lives there. The
model in brief:

- **The compendium is a "known-good" corpus.** `compendium/` holds ~33 `.jai` entries that each
  **compile AND run clean** against the pinned Jai version (currently beta 0.2.030). Compiling
  proves signatures; running proves behavior — do BOTH (the 0.2.030 pass found a type-info field
  that only *ran* wrong and a soft-deprecation only visible by *reading* the module).
- **Cheatsheet banners state trust level + version, three tiers:**
  - `compile-verified: beta X | compendium/NN` — the section's constructs are exercised by that
    compendium entry (compiles+runs). Trust these for codegen. Linkage is bidirectional: the entry
    carries a `// Proves (cheatsheet):` header.
  - `distribution-example-verified` — a construct we can't show single-file (needs a metaprogram /
    companion / external lib) but a Jai `how_to/`/`examples/` file demonstrates; we CONFIRM that
    example compiles against the current version (shipped ≠ clean — a distro example was found
    compiling with a deprecation warning).
  - `inspection-only: beta X` — read-checked against the distribution, not compiled. The backlog.
- **On every new Jai release:** bump version stamps, reconcile the CHANGELOG, re-run the whole
  corpus (compile+run) + re-compile the cited distribution examples + spot-re-audit. The corpus
  doubles as a **drift-detector** — the 0.2.030 pass caught 3 real cheatsheet errors and 2 compiler
  behavior changes. This is the "good kind of lazy": one expensive proof pass amortizes across every
  future version bump.
- Verify examples in **scratch copies** — never litter or git-touch the `~/jai/jai` distribution
  (its `.git` is a throwaway for Emacs `project`, no upstream — do not treat it as a real repo).

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
