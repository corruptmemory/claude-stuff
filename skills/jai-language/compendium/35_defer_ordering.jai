// Compendium: defer — ordering and scope
// Jai Version: beta 0.2.030
// Platform: Linux x86-64
// Sources: empirically established against the beta 0.2.030 compiler (2026-09-20).
//   The cheatsheet showed `defer` SYNTAX in several places but never stated its
//   ordering or its scope, and no compendium entry asserted either.
// Proves (cheatsheet): Special Syntax > defer ordering and scope
// Use-cases: what order multiple defers run in, what scope a defer belongs to, how
//   defers behave in a loop body and on an early return, and the practical rule for
//   getting teardown order right.
//
// THE RULES, all four verified by the asserts below:
//
//   1. LIFO within a scope. The LAST defer registered runs FIRST. (Same as Go, Zig,
//      Swift.) Reading top-to-bottom this feels inverted: a teardown written lower in
//      the file runs EARLIER than one written above it.
//   2. A defer belongs to its ENCLOSING BLOCK, not the function. A defer inside `{ }`
//      runs when that block exits, not at function exit.
//   3. A defer in a loop body runs once PER ITERATION, at the end of that iteration —
//      not once after the loop. (So `defer free(x)` in a loop frees each x, which is
//      usually what you want, and `defer` accumulating a lock is usually not.)
//   4. A defer runs on an early `return` as well as on falling off the end.
//   5. A defer CANNOT amend what the procedure returns. `return x;` snapshots x
//      BEFORE the defers run, so a defer that mutates that local changes nothing the
//      caller sees. And unlike Go, there is no named-return variable to assign to: a
//      return value's NAME is documentation only, not a variable in the body —
//      `f :: () -> status: int { status = 7; ... }` is
//          Error: Undeclared identifier 'status'.
//      (beta 0.2.030; the same error inside a defer). Names + DEFAULTS are still
//      functional: they let a bare `return;` fill every result in, which rule 5's
//      `defaults_fill_in` proves below. Go's `defer func(){ err = ... }()` idiom has
//      no Jai equivalent — a proc that must adjust its status on the way out has to
//      do it with an explicit statement before each return.
//
// THE PRACTICAL RULE that follows from (1):
//
//   Register each teardown IMMEDIATELY AFTER the acquisition it undoes, and the order
//   comes out right for free — B acquired after A is torn down before A, which is what
//   nesting requires. The bug is registering teardowns out of order relative to their
//   acquisitions; then LIFO faithfully unwinds them in the wrong order.
//
//   Worked example (screen-killer, src/app/module.jai): the display session is acquired
//   first and the renderer second, so
//       defer Input.shutdown();     // registered FIRST  -> runs LAST
//       defer Render.shutdown();    // registered SECOND -> runs FIRST
//   is correct: the renderer holds a surface belonging to the window the session owns,
//   so it must go first. Swapping the two lines compiles, reads fine, and tears the
//   session down underneath the renderer.

#import "Basic";

order: [..] string;
mark :: (s: string) { array_add(*order, s); }

// (1) LIFO within one scope.
three_defers :: () {
    defer mark("first-registered");
    defer mark("second-registered");
    defer mark("third-registered");
    mark("body");
}

// (2) A defer belongs to its enclosing BLOCK.
block_scoped :: () {
    mark("before-block");
    {
        defer mark("block-defer");
        mark("block-body");
    }
    mark("after-block");
}

// (3) Once per iteration, at the end of that iteration.
in_a_loop :: () {
    for 1..3 {
        defer mark(tprint("defer-%", it));
        mark(tprint("body-%", it));
    }
}

// (4) Runs on an early return too.
early_return :: (bail: bool) {
    defer mark("teardown");
    if bail {
        mark("bailing");
        return;
    }
    mark("fell-through");
}

// (5) A defer cannot amend the returned value: `return status` is evaluated before
// the defers run. `bump` mutates the local through a pointer — visible to anything
// still reading the local, invisible to the caller.
bump :: (p: *int) { p.* = 99; }

snapshot_before_defers :: () -> int {
    status := 3;
    defer bump(*status);
    return status;      // 3 reaches the caller; the defer's 99 lands after the copy
}

// ... and the other half of rule 5: a NAMED return value is not a variable, but its
// DEFAULT is real — a bare `return;` fills in every declared default.
Status :: enum { SUCCESS; FAIL; }

defaults_fill_in :: (fail: bool) -> code: int = -1, status := Status.SUCCESS {
    if fail  return 2, .FAIL;
    return;             // both defaults, no values named
}

// The acquisition/teardown pairing rule, modelled: `second` depends on `first`, so it
// must be released first. Registering each release right after its acquisition gets
// that ordering without anyone having to reason about it.
released: [..] string;

acquire_nested :: () {
    array_add(*released, "acquire-first");
    defer array_add(*released, "release-first");     // registered 1st -> runs LAST

    array_add(*released, "acquire-second");
    defer array_add(*released, "release-second");    // registered 2nd -> runs FIRST
}

main :: () {
    three_defers();
    assert(order[0] == "body",              "the body runs before any defer");
    assert(order[1] == "third-registered",  "LAST registered runs FIRST");
    assert(order[2] == "second-registered", "then the one before it");
    assert(order[3] == "first-registered",  "FIRST registered runs LAST");
    array_reset(*order);

    block_scoped();
    assert(order[2] == "block-defer", "a block defer runs at BLOCK exit ...");
    assert(order[3] == "after-block", "... NOT at function exit");
    array_reset(*order);

    in_a_loop();
    assert(order.count == 6,            "a loop-body defer runs once per iteration");
    assert(order[0] == "body-1",        "iteration 1 body");
    assert(order[1] == "defer-1",       "then iteration 1's defer, before iteration 2");
    assert(order[5] == "defer-3",       "and the last one closes the final iteration");
    array_reset(*order);

    early_return(true);
    assert(order[0] == "bailing",  "the early-return path ran");
    assert(order[1] == "teardown", "and the defer still fired");
    array_reset(*order);

    assert(snapshot_before_defers() == 3, "return snapshots the value BEFORE the defers run");

    c_default, s_default := defaults_fill_in(false);
    assert(c_default == -1,              "a bare return fills in a named result's default");
    assert(s_default == Status.SUCCESS,  "and the inferred-type default too");
    c_named, s_named := defaults_fill_in(true);
    assert(c_named == 2 && s_named == Status.FAIL, "naming both values still works");

    acquire_nested();
    assert(released[2] == "release-second", "the later acquisition is released FIRST");
    assert(released[3] == "release-first",  "and the earlier one LAST -- correct nesting");

    print("PASS: defer ordering and scope (LIFO within a scope; block-scoped, not\n");
    print("  function-scoped; once per loop iteration; fires on early return; cannot\n");
    print("  amend the returned value; and the register-next-to-the-acquisition rule\n");
    print("  yields correct teardown nesting)\n");
}
