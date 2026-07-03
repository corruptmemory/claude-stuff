// Compendium: Open-ended type parameters — structural acceptance + custom errors
// Jai Version: beta 0.2.030
// Platform: Linux x86-64
// Sources: how_to/160_type_restrictions.jai ($T/R + #as using), how_to/170_modify.jai,
//          modules/Compiler/Compiler.jai (compiler_report, Report),
//          modules/Preload.jai (Type_Info_Struct_Member.Flags: USING 0x4, AS 0x10)
// Use-cases: a module/layer takes an OPEN-ENDED type parameter (e.g. a program-wide
//            `Handler_Data: Type`, or GetRect's Type_Indicator) and wants to accept it
//            STRUCTURALLY — the exact type R, OR any struct that IS-A R (embeds it via
//            `#as using`) — instead of by exact identity. Three reusable pieces:
//              1. $T/R restriction — structural single-inheritance match, cast-free.
//              2. a compile-time type_info predicate "is *T assignable to *R?" — drives
//                 #if and lets you reject the rest with a precise message.
//              3. compiler_report — a clean, boilerplate-free compile diagnostic (vs #assert,
//                 which prepends "Compile-time assertion failed" and points a caret at the expr).
//
// MODULE-ANGLE NOTE: a program-wide `Type` parameter can only be SET by the main program
// (a library #import may NOT supply program parameters — see references/cheatsheet.md
// "Module Parameters"). The TYPE MACHINERY below is the transferable part and works
// single-file; the module wiring just hosts it.

#import "Basic";
Compiler :: #import "Compiler";

// The relation an open-ended parameter must satisfy (think: a library's Router, a renderer's Texture).
Base :: struct { id: int; }

// A consumer type that IS-A Base: `#as using` embeds it, so *App implicitly converts to *Base.
App :: struct {
    #as using base: Base;     // the #as is what grants the implicit *App -> *Base conversion
    name: string;
}

// Embeds Base WITHOUT #as: plain `using` promotes field access, but *Plain does NOT convert to *Base.
Plain :: struct {
    using base: Base;
    note: string;
}

Unrelated :: struct { x: float; }   // no relation to Base at all

// ---- (2) compile-time predicate: is *T assignable to *Base? --------------------------------
// True iff T is Base, or a struct with an `#as` member (flag AS, NOT plain USING) whose type is
// itself Base-assignable, recursively — exactly the relation that makes *T -> *Base implicit.
// It's an ordinary proc: usable in #if/#run at compile time AND callable at runtime (asserted below).
is_base_assignable :: (t: *Type_Info) -> bool {
    if t == type_info(Base)  return true;
    if t.type != .STRUCT     return false;
    s := cast(*Type_Info_Struct) t;
    for s.members {
        if !(it.flags & .AS)            continue;   // plain `using` (no #as) does NOT grant the conversion
        if is_base_assignable(it.type)  return true;
    }
    return false;
}

// ---- (1) $T/Base structural restriction: accepts Base or any #as-embedder, cast-free ------
take_base :: (x: *$T/Base) {
    b: *Base = x;             // *T -> *Base is implicit (the #as conversion) — no cast
    print("  take_base(): id=% via T=%\n", b.id, T);
}

// ---- (3) branch on the type property; reject incompatible T with a CUSTOM compile error ----
// Mirrors a router adapter reading context.handler_data whose type is an open-ended program param.
handle :: (x: *$T) {
    #if #run is_base_assignable(cast(*Type_Info) type_of(x.*)) {   // #if needs a constant -> #run the predicate
        b: *Base = x;
        print("  handle(): Base-assignable, id=%\n", b.id);
    } else {
        // compiler_report owns the ENTIRE message (no "assertion failed" prefix, no caret at an
        // opaque expr) — the clean way to reject a bad open-ended type. Default mode is ERROR, which
        // HALTS the build, so this branch only ever compiles for genuinely incompatible T. The
        // commented handle() calls in main would fire it; they stay commented so this file compiles.
        #run Compiler.compiler_report(tprint("handle: % is not Base-assignable; embed Base via `#as using`.", T));
    }
}

main :: () {
    print("Open-ended type parameters: structural acceptance.\n");

    app: App;   app.id = 7;   app.name = "demo";
    base: Base; base.id = 1;

    // (1) the structural restriction matches Base AND the #as-embedder, cast-free:
    take_base(*app);
    take_base(*base);

    // (3) the #if #run branch takes the Base-assignable path for both:
    handle(*app);
    handle(*base);

    // Incompatible types would hit the compiler_report ERROR branch — left commented so we compile:
    //   p: Plain;      handle(*p);     // plain `using` (no #as): rejected with the custom message
    //   u: Unrelated;  handle(*u);     // unrelated: rejected

    // (2) verify the assignability predicate directly (ordinary proc — call it at runtime):
    assert(is_base_assignable(type_info(Base))      == true,  "Base is trivially Base-assignable");
    assert(is_base_assignable(type_info(App))       == true,  "App #as-embeds Base -> assignable");
    assert(is_base_assignable(type_info(Plain))     == false, "Plain `using` without #as -> NOT assignable");
    assert(is_base_assignable(type_info(Unrelated)) == false, "Unrelated -> NOT assignable");

    print("PASS: $T/R structural match, type_info assignability predicate, compiler_report pattern.\n");
}

// compiler_report is exercised LIVE here in INFO mode (emits a compile-time note, does not fail the
// build). The default ERROR mode is the rejection tool shown in handle()'s else arm above.
#run Compiler.compiler_report("compendium/22: compiler_report INFO note (default mode is ERROR, used to reject bad open-ended types).", mode = .INFO);
