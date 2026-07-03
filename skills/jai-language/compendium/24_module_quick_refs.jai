// Compendium: Standard-module quick references (File / File_Utilities / Basic formatting)
// Jai Version: beta 0.2.030
// Platform: Linux x86-64
// Proves (cheatsheet): ## File I/O and String Formatting
//   -> ### File Module, ### File_Utilities Module, ### String Formatting
// Sources: modules/File/module.jai, modules/File_Utilities/module.jai,
//          modules/Basic/String_Builder.jai, modules/Basic/Print.jai
// Use-cases: the module APIs the cheatsheet quick-references — read/write files, walk a
//   directory, build strings, and format ints/floats. Module signatures drift independently
//   of language syntax (beta 0.2.030 alone changed Thread/NewArray/File), so unlike the pure
//   syntax entries these are proven by CALLING the real APIs — a signature change breaks the
//   build. This file both COMPILES (proves signatures) and RUNS (proves behavior) clean.

#import "Basic";
#import "File";
#import "File_Utilities";

Counter :: struct { count: int; saw_hello: bool; }

main :: () {
    // ── ### File Module (#import "File") ────────────────────────────────────────
    dir  := "/tmp/jai_compendium_24_probe";
    path := tprint("%/hello.txt", dir);

    // make_directory_if_it_does_not_exist RETURNS bool (directory_now_exists) + has a
    // `recursive` param — both omitted by the old cheatsheet entry.
    made := make_directory_if_it_does_not_exist(dir, recursive = true);
    assert(made, "make_directory_if_it_does_not_exist should report the dir now exists");

    // write_entire_file (string overload) -> bool; read_entire_file -> string, bool.
    payload := "round-trip payload\n";
    wrote := write_entire_file(path, payload);
    assert(wrote, "write_entire_file(string) should succeed");
    contents, ok := read_entire_file(path);
    assert(ok, "read_entire_file should succeed for a file we just wrote");
    assert(contents == payload, "round-trip mismatch: wrote '%', read '%'", payload, contents);

    // ── ### File_Utilities Module (#import "File_Utilities") ─────────────────────
    // visit_files(dir, recursive: bool, user_data: $T, proc: (info, user_data: T)) -> bool.
    // The proc is a BARE proc (no capture) — accumulate through the user_data pointer.
    counter: Counter;
    visit_files(dir, false, *counter, (info: *File_Visit_Info, ud: *Counter) {
        ud.count += 1;
        if info.short_name == "hello.txt"  ud.saw_hello = true;
    });
    assert(counter.count >= 1 && counter.saw_hello,
        "visit_files should have seen hello.txt (count=%, saw=%)", counter.count, counter.saw_hello);

    // teardown (file_delete -> bool; delete_directory -> bool)
    file_delete(path);
    delete_directory(dir);

    // ── ### String Formatting (#import "Basic") ─────────────────────────────────
    // tprint — temp-allocated sprintf.
    name := tprint("%_%", "pre", "post");
    assert(name == "pre_post", "tprint join mismatch: %", name);

    // String_Builder: append(builder, string) + print_to_builder(builder, fmt, args)
    // -> builder_to_string(builder) (do_reset defaults true).
    sb: String_Builder;
    append(*sb, "x");
    print_to_builder(*sb, "=%", 42);
    built := builder_to_string(*sb);
    assert(built == "x=42", "String_Builder mismatch: %", built);

    // formatInt / formatFloat: BOTH the helper-function form AND the struct-literal form
    // work. The functions carry a (currently commented) #deprecated pointing at the struct
    // form `FormatInt.{value=..., ...}` — but the how_to/ teaching files still use the
    // function form, so it is not going away imminently. The value lives in the embedded
    // Formatter (`value: Any`), so the struct form spells it `.{value=X, ...}`.
    assert(tprint("%", formatInt(255, base = 16)) == "ff",
        "formatInt(255, base=16) should be ff");
    assert(tprint("%", FormatInt.{value = 255, base = 16}) == "ff",
        "FormatInt.{value=255, base=16} should be ff");
    assert(tprint("%", formatInt(42, minimum_digits = 5)) == "00042",
        "formatInt(42, minimum_digits=5) should be 00042");
    assert(tprint("%", formatInt(1000, digits_per_comma = 3, comma_string = ",")) == "1,000",
        "formatInt with commas should be 1,000");

    assert(tprint("%", formatFloat(3.14, trailing_width = 2)) == "3.14",
        "formatFloat(3.14, trailing_width=2) should be 3.14");
    assert(tprint("%", FormatFloat.{value = 3.14, trailing_width = 2}) == "3.14",
        "FormatFloat.{value=3.14, trailing_width=2} should be 3.14");

    print("PASS: File read/write/mkdir + File_Utilities.visit_files + Basic String_Builder & tprint & formatInt/formatFloat (function AND struct-literal forms) all verified against beta 0.2.030.\n");
}
