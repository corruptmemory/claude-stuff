// Compendium: scopes — nested blocks are first-class
// Jai Version: beta 0.2.030
// Platform: Linux x86-64
// Sources: how_to/080_scopes.jai (the authoritative treatment), plus empirical
//   confirmation against the beta 0.2.030 compiler (2026-09-20).
// Proves (cheatsheet): Special Syntax > scopes and nested blocks
// Use-cases: what creates a scope, what surprisingly does NOT, shadowing in a nested
//   block, the implicit scopes that exist without braces, and the load-bearing case —
//   an IMPORT, which a bare block scopes and a `#if` does not.
//
// A bare `{ }` in Jai is a REAL SCOPE, not cosmetic grouping. That makes nested blocks
// a tool rather than decoration: they bound a name's lifetime, let you reuse a name for
// a different thing, and — see compendium/35 — they bound `defer` too, so a defer inside
// a block fires at the BLOCK's exit.
//
// WHAT CREATES A SCOPE
//   - a bare `{ }` block
//   - a procedure body
//   - the body of `if` / `for` / `while`, WITH OR WITHOUT braces
//   - every `case` arm of an `if x == { ... }`, automatically — no braces needed, which
//     is the thing C and C++ make you write out by hand
//
// WHAT DOES NOT CREATE A SCOPE
//   - `#if`, and NOT as an exception to the rule. `#if` is a COMPILE-TIME SPLICING
//     construct, in the lineage of the C preprocessor and Lisp macros — not a control
//     flow statement that happens to run early. Its braces delimit the text to splice,
//     they are not a block. Read that way, introducing no scope is the only sensible
//     behaviour: `#if` exists to put declarations INTO the surrounding scope, and a
//     scope of its own would defeat the entire feature.
//
//     The splice model is not a story; it makes a falsifiable prediction that a scope
//     model does not, and the prediction holds (all three verified below in comments,
//     since two of them are compile errors):
//         #if true  { x := 10; }   with an outer x  ->  "Error: Redeclaration of 'x'."
//         #if FALSE { x := 10; }   with an outer x  ->  COMPILES CLEAN
//     Under a scope model those two are identical — both would be scopes, neither would
//     collide. Under a splice model the false branch inserts NOTHING, so there is
//     nothing to collide with. Observed: the splice behaviour.
//
//     The SHARPEST demonstration is an IMPORT, and it is sharp precisely because Jai
//     scopes imports like any other declaration — these are NOT C #includes. The same
//     line is confined by a bare block and escapes a `#if` (all three run below or are
//     quoted from the compiler, beta 0.2.030):
//
//         #if true { using Math :: #import "Math"; }   Vector3 usable OUTSIDE   -> (A)
//         { using Math :: #import "Math"; }            Vector3 outside ->
//                                              "Error: Undeclared identifier 'Vector3'."
//         { using Math :: #import "Math"; ...inside }  compiles and runs        -> (C)
//
//     (C) is what closes the argument. The block form does not fail because a
//     block-local import is ILLEGAL — it fails because the import is SCOPED. So `#if`
//     declining to scope it is a real semantic, not an artefact of imports needing to
//     sit at file scope.
//
//     This is load-bearing in real code. A compile-time backend facade is written
//     exactly this way, and cannot be written any other way:
//
//         using Shared :: #import "Render/Shared";
//         #if GFX_BACKEND == .VULKAN { using Backend :: #import "Render/Vulkan"; }
//         else                       { using Backend :: #import "Render/None";  }
//
//     If `#if` opened a scope, the chosen backend would be trapped inside its branch,
//     the module would re-export nothing, and the pattern could not exist. Observed in
//     the wild: screen-killer's modules/Render/module.jai, where that IS the whole
//     facade — no hand-written forwarders, because a forwarder is a second place for
//     two backends to drift apart.
//
//   - the braces of a struct literal, `Vector3.{1, 2, 3}`. They echo C's syntax; no
//     declaration is legal inside one anyway.
//
// Jai also has "data scope" vs "imperative scope" (how_to/080): a data scope holds
// declarations with no notion of time and no ordering between them (file top level, a
// struct body); an imperative scope is code that runs in order. Statements that need a
// runtime moment are illegal in a data scope — you cannot call a procedure at file
// top level, because there would be no defined time to run it.
//
// There are no closures: a procedure nested inside another cannot see the outer
// procedure's locals, because it must be able to run standalone after the outer one has
// returned (how_to/080). Nesting a proc scopes its NAME, not its data.

#import "Basic";

thing: u8 = 1;

main :: () {
    x := 5;

    // A bare block is a real scope: the inner x is a different variable.
    {
        x := 10;
        assert(x == 10, "inside the block, the inner binding wins");
    }
    assert(x == 5, "and the outer binding is untouched afterwards");

    // Every case arm is its own scope, automatically. In C this needs explicit braces.
    if thing == {
      case 0;  x := 10;
      case 1;  x := 20;
      case;    x := 40;
    }
    assert(x == 5, "a case arm's declaration cannot leak into the enclosing scope");

    // Braces are optional on if/for/while, and the body is a scope either way.
    if true  x := 6;
    assert(x == 5, "a BRACELESS if body is still a scope");

    for 1..2  x := 7;
    assert(x == 5, "so is a braceless for body");

    n := 0;
    while n < 2 { x := 8; n += 1; }
    assert(x == 5, "and a while body");

    // #if SPLICES into the enclosing scope rather than opening one. The pair below is
    // the discriminating experiment: a scope model predicts these behave the same, a
    // splice model predicts they differ, and they differ.
    //
    //     #if true  { x := 10; }   // Error: Redeclaration of 'x'  -- the decl landed HERE
    //     #if false { x := 10; }   // compiles clean -- nothing was spliced at all
    //
    // The false form is legal, so it can be exercised for real:
    #if false { x := 10; }
    assert(x == 5, "a false #if spliced nothing; x is untouched and undisturbed");

    // ...and #if does not scope an IMPORT either — the case that matters in real code,
    // and one that is only MEANINGFUL because Jai does scope imports (see C).
    #if true {
        using Math :: #import "Math";
    }
    spliced := Vector3.{1, 2, 3};          // (A) resolves: the import was spliced HERE
    assert(spliced.x == 1, "a #if-spliced import is visible in the ENCLOSING scope");

    // (B) the same two lines with a bare block do NOT compile, so they stay quoted:
    //         { using Math :: #import "Math"; }
    //         v := Vector3.{1, 2, 3};
    //     -> Error: Undeclared identifier 'Vector3'.
    //
    // (C) yet the import is perfectly legal INSIDE that block — which is what proves
    // (B) is a SCOPING result and not "imports are illegal in an imperative scope":
    {
        using Block_Math :: #import "Math";
        inside := Vector3.{4, 5, 6};
        assert(inside.y == 5, "a block-local import is legal, and scoped to its block");
    }

    // Nested blocks let one name mean different things in sequence without inventing
    // x_pixels / x_logical / x_tmp. Each is dead at its block's closing brace.
    SAME_NAME_DIFFERENT_TYPE :: "a string this time, same name, different type";
    total := 0;
    {
        v := 3;                            // an int here ...
        total += v;
    }
    {
        v := SAME_NAME_DIFFERENT_TYPE;     // ... and a string there, same name
        total += v.count;
    }
    assert(total == 3 + SAME_NAME_DIFFERENT_TYPE.count, "each block's v is independent");

    print("PASS: scopes (bare blocks are real scopes and shadow; if/for/while bodies and\n");
    print("  every case arm are scopes with or without braces; #if and struct-literal\n");
    print("  braces are NOT scopes — including for IMPORTS, which a bare block DOES scope)\n");
}
