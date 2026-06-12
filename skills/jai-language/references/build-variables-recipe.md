# Custom build variables (compile-time knobs) — the canonical recipe

**Tested against: Jai beta 0.2.029 (2026-06-11).** Re-verify on compiler upgrades — this
recipe leans on metaprogram/scoping behavior that has changed across betas (see Provenance);
the failure mode of the anti-pattern below may be fixed or shifted in later versions.

## Problem

A build metaprogram (driven by `jai first.jai - <args>`) wants to define compile-time
constants — `BUILD_MODE`, `GFX_BACKEND`, `PROFILING_ENABLED`, … — that target code can
reference like any constant, **including in `#if KNOB #load "file.jai";`** (conditionally
compiling whole files). Module parameters don't fit (per-import instances, not global), and
program-global `add_build_string` doesn't reach module scopes.

## The recipe (three pieces)

### 1. A knobs module declares the names as `#placeholder`s

`modules/Build_Knobs/module.jai` (any name; the project that produced this recipe calls it
`Local_Preload`):

```jai
Build_Mode :: enum { DEVELOPMENT; RELEASE; }   // the TYPES live here too

#placeholder BUILD_MODE;    // : Build_Mode — filled by the metaprogram
```

The `#placeholder` is the load-bearing piece: it is the **synchronization contract**. The
compiler stalls anything that depends on the name — `#if` evaluation, `#load` gating, body
typechecking — until the metaprogram fills it. (See `modules/Metaprogram_Plugins.jai` for the
stall semantics described in comments, and how_to/460/470 for the placeholder workflow.)

### 2. The metaprogram fills them ONCE, scoped to the module's import message

In the metaprogram's `compiler_wait_for_message` loop:

```jai
knobs_inject := tprint("BUILD_MODE :: Build_Mode.%;\n", build_mode_value);
injected := false;
while true {
    message := compiler_wait_for_message();
    if message.kind == {
      case .IMPORT;
        mi := cast(*Message_Import) message;
        if mi.module_name == "Build_Knobs" && !injected {
            injected = true;   // imports dedup by name -> one module instance -> one fill
            add_build_string(knobs_inject, w, message);
        }
      case .COMPLETE;
        // ... check error_code, break.
    }
}
```

`add_build_string(s, w, message)` scoping rules (CHANGELOG beta 0.1.066; demonstrated in
`~/jai/jai/examples/add_build_string_into_specific_scope`):
- `*Message_Import` → that module's **module scope**  ← what you want for knobs
- `*Message_File`   → that file's **file scope**
- `null`            → the program's **global scope** (does NOT reach module scopes)

Targets that never import the knobs module simply never trigger the fill — unreferenced
unfilled placeholders are legal (the metaprogram's own import of the module for the enum
types is exactly this case).

### 3. Consumers opt in explicitly

```jai
#import "Build_Knobs";

#if BUILD_MODE == .DEVELOPMENT  #load "dev_only_stuff.jai";   // SAFE with this recipe
```

## The anti-pattern (and the bug it hits in beta 0.2.029)

**Do not blanket-inject file-scoped knob copies** — i.e. `add_build_string(knobs, w, msg)`
for every `.FILE` message under your source tree, with no `#placeholder` anywhere. It
*appears* to work (plain references stall politely), but there is no synchronization
contract, and in beta 0.2.029 it breaks on exactly the gated-`#load` case:

- `#if KNOB #load "x.jai";` where KNOB is a file-scope-injected constant → the late-firing
  `#load` poisons identifier resolution **module-wide**: the module's OTHER injected strings
  fail to resolve their own `#import`s, and the module's normal imports stop resolving
  (errors point at `.added_strings_w*.jai` and unrelated sibling files).
- Adding `#placeholder KNOB;` does NOT fix it under per-file injection.
- Excluding the late-loaded file from injection does NOT fix it (the trigger is the late
  `#load` itself, not the injection into that file).
- Same bug family as the beta 0.0.065 fix ("identifiers being not-yet-declared in module
  imports with some combinations of #if and #load"); this combination is unfixed as of
  0.2.029. Reportable: minimal repro = per-FILE injection + `#if INJECTED_KNOB #load`.

The recipe above sidesteps the bug entirely (verified: the same gated `#load` compiles and
runs in both knob values).

## Provenance

- `~/jai/jai/examples/add_build_string_into_specific_scope` — the authoritative demo:
  per-module + per-file injection, **every receiving scope declares `#placeholder`**, strings
  added at `TYPECHECKED_ALL_WE_CAN`.
- `~/jai/jai/how_to/460_code_browsing_and_generation`, `470_running_hooks_in_the_target_workspace`
  — `#placeholder` + global-scope `add_build_string` for generated declarations.
- `~/jai/jai/how_to/420_command_line.jai` — the `jai first.jai - <args>` convention for
  feeding the metaprogram its knob values.
- CHANGELOG: beta 0.1.066 (message-scoped `add_build_string` overload), beta 0.1.091
  (`#exists`'s sync parameter; recommends `#placeholder` for "#iffed in later" declarations),
  beta 0.0.065 (the `#if`+`#load` not-yet-declared fix that removed a `#placeholder`
  workaround from Simp).
- Field experience: the game-bootstrap project's knob migration (2026-06-11) — see its
  `modules/Local_Preload` + `first.jai` for a live instance of this recipe.

## Re-verification checklist (on a new Jai version)

1. Compile a project using the recipe under both knob values; confirm a knob-gated `#load`
   compiles and the loaded code runs.
2. Re-test the anti-pattern's minimal repro — if it now compiles, the 0.2.029 bug is fixed
   and this note should record the version that fixed it (the recipe remains preferable:
   it is the documented pattern).
3. Update the "Tested against" line.
