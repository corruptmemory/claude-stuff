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
