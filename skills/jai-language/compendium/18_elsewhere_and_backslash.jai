// Compendium entry 18: #elsewhere Directive and Backslash Identifiers
// Jai Compiler Version: beta 0.2.030 (2 July 2026)
// Platform: Linux x86-64
// Sources: examples/dll/main.jai, modules/macOS/bindings/core_foundation.jai,
//          modules/POSIX/bindings/linux/stdio.jai, modules/POSIX/bindings/linux/base.jai,
//          modules/Bindings_Generator/tests/linux.jai,
//          modules/Objective_C/AppKit.jai, modules/Objective_C/GameController.jai,
//          modules/Compiler/Compiler.jai,
//          modules/Simp/shader.jai, modules/Window_Creation/windows.jai,
//          modules/GetRect/widgets/text_input.jai, modules/Gamepad/Gamepad.jai
//
// Use-cases demonstrated:
//   - #elsewhere for global variables in external libraries
//   - #elsewhere with custom link name (C++ mangled, ObjC symbols)
//   - #elsewhere bare form (no library specified)
//   - #elsewhere on procedures (with other modifiers)
//   - Backslash identifiers (visual break in identifier names)
//   - Named return capture in assignment context (name:, var = func())
//
// NOTE: #elsewhere and backslash identifiers cannot be demonstrated in
// a self-contained compilable example because they depend on external
// libraries and are syntactic features that the compiler handles
// transparently. This file documents the syntax patterns.

#import "Basic";

// ============================================================================
// #elsewhere — External Symbol Declarations
// ============================================================================
// #elsewhere is like #foreign but for VARIABLES (not procedures).
// For procedures, #foreign is used; for global variables, #elsewhere is used.
//
// FORM 1: name: Type #elsewhere lib;
//   Declares a variable whose storage lives in the named library.
//   Example from modules/POSIX/bindings/linux/stdio.jai:
//     stdin:  *_IO_FILE #elsewhere libc;
//     stdout: *_IO_FILE #elsewhere libc;
//     stderr: *_IO_FILE #elsewhere libc;
//
// FORM 2: name: Type #elsewhere lib "custom_link_name";
//   Like Form 1 but with a custom link name string (for C++ mangled names, etc.)
//   Example from modules/POSIX/bindings/macos/x64/stdio.jai:
//     stdin:  *FILE #elsewhere libc "__stdinp";
//     stdout: *FILE #elsewhere libc "__stdoutp";
//   Example from modules/Bindings_Generator/tests/windows.jai:
//     DefaultOutside: ConstStuff #elsewhere cpp_library "?DefaultOutside@@3UConstStuff@@A";
//   Example from modules/Objective_C/LightweightRenderingView/module.jai:
//     __view_class_object: *void #elsewhere library "OBJC_CLASS_$_LightweightOpenGLView";
//
// FORM 3: name: Type #elsewhere;
//   No library specified — the symbol is provided by the binary itself.
//   Example from modules/Compiler/Compiler.jai:
//     __runtime_info: Runtime_Info #elsewhere;
//   Example from modules/Objective_C/GameController.jai:
//     GCControllerDidConnectNotification: *NSString #elsewhere;
//   Example from modules/Objective_C/AppKit.jai:
//     NSApp: *NSApplication #elsewhere;
//
// FORM 4: On procedures (combined with #foreign-like behavior)
//   Example from examples/dll/main.jai:
//     Helper :: #library,no_static_library "helper";
//     do_something_simple :: () #no_context #elsewhere Helper;
//     get_value :: () -> string #elsewhere Helper;
//   #elsewhere goes AFTER return type and modifiers, before semicolon
//
// GRAMMAR IMPLICATIONS:
// For tree-sitter, #elsewhere needs to be recognized in two contexts:
//   1. As a declaration suffix: name: Type #elsewhere [lib] ["link_name"];
//   2. As a procedure modifier: proc :: () -> T #modifier #elsewhere [lib];
// The optional library identifier and optional link name string are the tricky parts.

// ============================================================================
// Backslash Identifiers
// ============================================================================
// In Jai, a backslash (\) can appear inside an identifier as a "visual break."
// The compiler STRIPS the backslash (and any following whitespace), treating
// the identifier as if neither were there.
// So `left\_margin` is the SAME identifier as `left_margin`.
//
// TWO FORMS discovered (Pass 9):
//   Form 1 (no whitespace): name\_continuation
//     - The backslash immediately followed by the next identifier character
//     - Most common form (~130 of 136 uses)
//
//   Form 2 (whitespace continuation): name\      _continuation
//     - The backslash followed by SPACES/TABS then the next identifier character
//     - Used for COLUMN ALIGNMENT in formatted code
//     - The compiler strips both the `\` AND the whitespace
//     - Source: modules/Basic/Apollo_Time.jai line 260:
//         month\      _starting_at_0 : u8;
//         day\        _starting_at_1 : u8;
//     - Source: modules/GetRect/system/active_widgets.jai:
//         deactivate\         _proc
//
// Total: 136 uses across 33 files
//
// This is used to avoid triggering certain compiler behaviors related to
// underscore-separated words, or simply as a visual hint/alignment tool.
//
// Examples from the distribution:
//   shader_sprite_left\_handed    (modules/Simp/shader.jai)
//   local\_rect                   (modules/Window_Creation/windows.jai)
//   move_cursor_left\_by_word     (modules/GetRect/widgets/text_input.jai)
//   LEFT\_SHOULDER                (modules/Gamepad/Gamepad.jai)
//   left\_arrow_tip               (modules/GetRect/widgets/color_picker.jai)
//   a.end\ _string                (examples/dll/main.jai — note: space after backslash)
//   first_\background             (modules/GetRect/examples/example.jai)
//   month\      _starting_at_0   (modules/Basic/Apollo_Time.jai — whitespace form)
//
// GRAMMAR IMPLICATIONS:
// For tree-sitter, identifiers need to allow `\` + optional whitespace between
// characters. This requires modifying the external scanner to handle backslash
// (and optional whitespace) within identifier tokens.
// Current grammar does NOT support this; ~33 files fail because of it.

// ============================================================================
// Mixed Declaration/Assignment in Multi-Return Capture
// ============================================================================
// When capturing multiple return values, each capture target is POSITIONAL
// and can independently be a declaration or an assignment:
//   `name:,` declares a NEW variable at that position (the `:` means "declare")
//   bare `name,` in `=` context assigns to an EXISTING variable
//   `_:,` declares and discards the return at that position
//
// IMPORTANT: The `name:` does NOT target returns by name -- it is purely
// positional. The `:` is a declaration operator, not a name-matching operator.
// The caller chooses whatever variable name they want.
//
// In DECLARATION context (`:=` at end, all unadorned names are new declarations):
//   val, ok, msg := get_result();            // all three declared positionally
//
// In ASSIGNMENT context (`=` at end, unadorned names assign to existing vars):
//   success:, module_index = table_find(*indices, key);
//     // ^^ declares 'success' (pos 1), assigns to existing 'module_index' (pos 2)
//   found, file_line:, remainder = split_from_left(line, #char " ");
//     // ^^ assigns 'found' (pos 1), declares 'file_line' (pos 2), assigns 'remainder' (pos 3)
//   _:, remainder = split_from_left(r, " ");
//     // ^^ declares+discards (pos 1), assigns 'remainder' (pos 2)
//
// Examples from the distribution:
//   success:, module_index = table_find(...)    (modules/Codex/write.jai)
//   name:, remainder = break_by_spaces(...)     (modules/Subtitles.jai)
//   declaration:, offset, success = parse_declaration(...)  (modules/debug_info/dwarf/dwarf.jai)
//   found, _:, remainder = split_from_left(...)  (modules/Android/Toolchain/android_helper.jai)
//   view:, result = make_image_view(...)         (examples/VR/modules/Vulkan_Render/module.jai)
//   length:, success = file_length(file)         (modules/Android/examples/files.jai)
//
// ~30+ uses across the distribution, both in `:=` and `=` contexts.

// ============================================================================
// Demonstration (compilable subset)
// ============================================================================
// We can demonstrate named return capture since that works in regular code.

get_pair :: () -> first: string, second: string {
    return "hello", "world";
}

get_status :: () -> ok: bool, value: int {
    return true, 42;
}

main :: () {
    // Standard positional capture (all declared via :=)
    a, b := get_pair();
    print("Positional: a=%, b=%\n", a, b);

    // Mixed capture in declaration context (:= at end)
    // `first:,` declares 'first' at position 1, `s` declared at position 2
    first:, s := get_pair();
    print("Named declare: first=%, s=%\n", first, s);

    // Mixed capture in assignment context (= at end)
    // `success:,` DECLARES 'success' (pos 1, gets ok: bool)
    // `existing_val` ASSIGNS to existing var (pos 2, gets value: int)
    existing_val := 0;
    success:, existing_val = get_status();
    print("Mixed assign: success=%, existing_val=%\n", success, existing_val);

    // Discard with _:, (declares and discards at that position)
    _:, remainder := get_pair();
    print("Discard: remainder=%\n", remainder);
}
