// The metaprogram half of compendium/38. It exists for one reason: the behaviour
// the entry proves is INVISIBLE under the default build.
//
// Build_Options.arithmetic_overflow_check is `.OFF` by default
// (modules/Compiler/Compiler.jai:124), and set_optimization leaves it there for
// every level — Compiler.jai:1755 carries the .VERY_DEBUG line commented out and
// 1760 forces .OFF. There is no command-line flag for it (`jai -help` mentions
// neither "overflow" nor "aoc" at beta 0.2.030). So a plain
// `jai-linux program.jai` would run the file clean whether #no_aoc did anything
// or not, and the entry would be a lie that compiles.
//
// With .FATAL set here, program.jai's asserts become load-bearing: if #no_aoc
// ever stopped suppressing the check, the RUN panics instead of passing.
//
// Build + run:
//   ~/jai/jai/bin/jai-linux build.jai
//   ./no_aoc_proof

#import "Compiler";
#import "Basic";

#run {
    w := compiler_create_workspace("no_aoc_proof");

    opts := get_build_options(w);
    opts.arithmetic_overflow_check = .FATAL;    // the whole point of this file
    opts.output_executable_name    = "no_aoc_proof";
    set_build_options(opts, w);

    // #filepath, so the build works from any working directory.
    add_build_file(tprint("%program.jai", #filepath), w);

    set_build_options_dc(.{ do_output = false });   // this metaprogram emits no binary of its own
}
