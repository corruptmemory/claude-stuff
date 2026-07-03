// Proves (cheatsheet): ### Metaprogramming Directives (#poke_name)
// Jai Version: beta 0.2.030
// Platform: Linux x86-64
// Sources: modules/Iprof/instrument.jai (canonical use), modules/Iprof/runtime.jai
//   (the receiving #placeholder), CHANGELOG.txt beta 0.1.063 ("#poke_name has been
//   changed to put things into the module scope instead of the import scope, so that
//   #placeholders in the module can be correctly filled").
// Use-cases: #poke_name
//
// WHAT IT DOES
//   `#poke_name <TargetModule> <DeclName>;` takes a declaration that ALREADY EXISTS in
//   the current scope and injects it into another module's *module scope*. The name is
//   thereafter visible through that module's namespace (Target.<DeclName>) AND still
//   visible locally (it is shared into the target, not moved out of the current scope).
//
//   Because it lands in module scope (not merely the import scope), a `#poke_name` can
//   satisfy a `#placeholder` declared inside the target module -- that is the whole
//   point of the beta 0.1.063 change.
//
// CONTEXT IT REQUIRES
//   None special: it is an ordinary compile-time directive, resolved during type-
//   checking of a PLAIN executable's single-workspace build. It does NOT require a
//   #run, a macro, or a build-driver metaprogram. Its only requirement is a *target
//   module* to poke into -- named by its import name (or an alias). Any imported module
//   works; here we poke into the stdlib `Math` module purely to have a second scope to
//   observe. `<DeclName>` must be declared before the poke, or you get an
//   "Undeclared identifier" build error.
//
// THE CANONICAL USE (why the directive exists -- shown here as reference, not run)
//   A metaprogram emits source with `add_build_string` that both declares a value and
//   pokes it into a client module to fill that module's `#placeholder`. modules/Iprof
//   does exactly this:
//       // metaprogram side (instrument.jai), added to the target workspace:
//       //     AUTO_INSTRUMENT_ZONE_COUNT :: <tally>;
//       //     #poke_name __Iprof AUTO_INSTRUMENT_ZONE_COUNT;
//       // module side (runtime.jai):
//       //     #scope_module
//       //     #placeholder AUTO_INSTRUMENT_ZONE_COUNT;
//   That full pattern needs a *separate* module to hold the `#placeholder`, so it can't
//   be shown in one file -- but the underlying operation (inject a declaration into
//   another module's scope, observable through that module) is exactly what this file
//   proves below, single-file.

#import "Basic";                 // unqualified: print / assert used directly.
Target :: #import "Math";        // an alias to some OTHER module -- our poke target.

// Declare a constant locally, then poke it into Target's (Math's) module scope.
POKED_VALUE :: 1234;
#poke_name Target POKED_VALUE;

main :: () {
    // Observable outcome: the declaration is reachable through the target module's
    // namespace -- proof that it really landed in Math's module scope, not just here.
    print("Target.POKED_VALUE = %\n", Target.POKED_VALUE);
    assert(Target.POKED_VALUE == 1234);

    // And it remains visible in the current scope too (poke shares, it does not move).
    assert(POKED_VALUE == 1234);

    print("PASS: 33_poke_name (#poke_name injected a declaration into another module's scope)\n");
}
