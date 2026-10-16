---
name: go-web-scaffold
description: "Scaffold a new Go web application with single-binary architecture, templ HTML templates, htmx interactivity, chi router, vendored frontend assets, embedded static files, TOML config with reflection-based gen-config, and a central build.sh script. Use when the user wants to create a new Go web project, HTTP API, dashboard, or web application from scratch. Trigger phrases: 'new Go project', 'scaffold', 'start a new web app', 'create a Go web server'."
---

# Go Web Project Scaffold

Scaffold a new Go web project following a proven single-binary architecture with vendored assets, templ templates, and htmx.

## Scaffolding Process

1. Ask the user for: project name, Go module path, and a brief description of what the app will do
2. Run the scaffold script to generate the project skeleton
3. Customize the generated code for the user's specific needs
4. Run `./build.sh --generate --build` to verify the scaffold compiles

```bash
python3 scripts/scaffold.py <project-name> --module <module-path> --dir <output-directory>
```

## The build.sh Recipe: Parse Flags, Then Run Linearly

Every project's `build.sh` follows one recipe (Jim's; reference implementation `~/bhf/data-management-service/build.sh`):

1. **Parsing only records.** The argument loop sets `DO_*` variables and nothing else. It never builds, tests or downloads. Arguments that take the rest of the command line (`--test [go test args…]`, `--run [app args…]`) are captured into arrays and end the loop.
2. **Implied steps are flags too.** After parsing, one short block switches on what the requested steps need (`--develop` needs `--build`; a build with no generated templates needs `--generate`). A step function never calls another step's function.
3. **The steps run once each, in one fixed order**: clean → vendor refresh → generate → vet/test → build → package → long-running (`--develop` or `--run`, which never returns, always last). The order the user types flags in does not matter, and flags whose work overlaps never repeat a step.
4. **Preconditions of a late step are checked early.** If a late step needs a tool (docker, air, curl), check it before the slow steps run, so a host that cannot finish fails in seconds.

The generated `build.sh` follows this recipe; keep it that way as flags are added. Details and a skeleton are in the architecture reference.

## Architecture Reference

See [references/architecture.md](references/architecture.md) for the complete conventions: directory layout, build.sh structure, config pattern, route wiring, template structure, asset embedding, and CSS design tokens.

## After Scaffolding

The generated project is a working baseline. Customize by:
- Adding routes in `cmd/app/main.go`
- Adding handlers in `internal/web/handlers/`
- Adding templ pages in `internal/web/pages/`
- Adding domain logic under `internal/`
- Extending settings structs for new config fields (gen-config picks them up automatically)
- Running `./build.sh --generate` after editing `.templ` files
