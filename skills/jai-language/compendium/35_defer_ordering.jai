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

    acquire_nested();
    assert(released[2] == "release-second", "the later acquisition is released FIRST");
    assert(released[3] == "release-first",  "and the earlier one LAST -- correct nesting");

    print("PASS: defer ordering and scope (LIFO within a scope; block-scoped, not\n");
    print("  function-scoped; once per loop iteration; fires on early return; and the\n");
    print("  register-next-to-the-acquisition rule yields correct teardown nesting)\n");
}
