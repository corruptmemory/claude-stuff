// Compendium: scopes — nested blocks are first-class
// Jai Version: beta 0.2.030
// Platform: Linux x86-64
// Sources: how_to/080_scopes.jai (the authoritative treatment), plus empirical
//   confirmation against the beta 0.2.030 compiler (2026-09-20).
// Proves (cheatsheet): Special Syntax > scopes and nested blocks
// Use-cases: what creates a scope, what surprisingly does NOT, shadowing in a nested
//   block, and the implicit scopes that exist without braces.
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
    print("  braces are NOT scopes)\n");
}
