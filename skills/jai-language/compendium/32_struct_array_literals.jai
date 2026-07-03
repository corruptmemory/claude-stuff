// Compendium: Struct/Array Literals
// Proves (cheatsheet): ## Struct/Array Literals
// Jai Version: beta 0.2.030
// Platform: Linux x86-64
// Sources: how_to/007_struct_literals.jai:136 (mixed named + indexed; positional; type-inferred),
//   modules/Android/Toolchain/manifest.jai (~L213: dotted subfield initializer .{ns.index = v, ...}),
//   modules/Overwriting_Allocator/module.jai:52 (non-dot return { proc, u }),
//   CHANGELOG.txt beta 0.2.022 (non-'.' struct literals: {3, 4}, return {}, .[{..},{..}])
//     + beta 0.2.023 note L480 ("if x == {}" parser special case: does NOT parse as a switch)
// Use-cases: indexed field initializer, mixed named + indexed, dotted subfield initializer,
//   bare type-inferred .[...] array literal, non-dot {..} literal (call arg / typed target /
//   assignment / return / nested inside an array literal), the "if x == {}" special case.
//
// This file proves ONLY the forms the cheatsheet lists that 04_structs.jai does not already
// exercise. The plain named (Type.{f = v}), positional (Type.{a, b}), and type-inferred (.{a, b})
// forms are proven in 04_structs.jai and are not repeated here.

#import "Basic";

// --- Structs used below ---

// Array-typed field, for indexed initializers.
Triple :: struct {
    values: [3] int;
}

// Mirrors how_to/007_struct_literals.jai's Body: a named default + an array field.
Body :: struct {
    name     := "Fred";
    values:   [3] int;
}

// Nested structs, for the dotted-subfield initializer (Android manifest shape).
Ref :: struct {
    index: int;
}
Typed_Value :: struct {
    data: int;
}
Manifest_Attr :: struct {
    ns:          Ref;
    name:        Ref;
    typed_value: Typed_Value;
}

// Simple struct + operator== so "if x == {}" typechecks as a real comparison.
// (Jai has NO built-in struct equality; without this operator, "x == {}" fails to resolve.)
Vec2 :: struct {
    x: int;
    y: int;
}
operator == :: (a: Vec2, b: Vec2) -> bool {
    return a.x == b.x && a.y == b.y;
}

// For the nested-non-dot-inside-array-literal form.
Pair :: struct {
    n: int;
    s: string;
}

// Non-dot struct literal as a CALL ARGUMENT: length({3, 4}) instead of length(.{3, 4}).
sum_vec :: (v: Vec2) -> int {
    return v.x + v.y;
}

// Non-dot struct literals in RETURN position (struct return type).
make_default_vec :: () -> Vec2 { return {};      }   // empty non-dot literal  (vs return .{})
make_vec         :: () -> Vec2 { return {5, 6};  }   // positional non-dot literal

main :: () {
    // --- Indexed field initializer: Type.{ field[0] = v, field[1] = w } ---
    // Initialize an array-typed field element-by-element, by index.
    t := Triple.{values[0] = 10, values[1] = 20, values[2] = 30};
    assert(t.values[0] == 10 && t.values[1] == 20 && t.values[2] == 30);
    print("indexed field init: t.values = %\n", t.values);

    // --- Mixed named + indexed: Type.{ name = v, values[1] = 7 } ---
    // Straight from how_to/007_struct_literals.jai:136. Unmentioned fields keep their defaults.
    body := Body.{name = "Ginger", values[1] = 7};
    assert(body.name == "Ginger" && body.values[1] == 7 && body.values[0] == 0);
    print("mixed named+indexed: name=% values=%\n", body.name, body.values);

    // --- Dotted subfield initializer: .{ ns.index = v, name.index = w, ... } ---
    // Sets members of sub-structs directly in one literal (Android manifest ~L213 pattern);
    // the type-inferred form (leading '.') is used because the target type is already known.
    // 'typed_value = .{data = ...}' shows a nested type-inferred literal alongside the dotted keys.
    attr: Manifest_Attr = .{ns.index = 5, name.index = 9, typed_value = .{data = 42}};
    assert(attr.ns.index == 5 && attr.name.index == 9 && attr.typed_value.data == 42);
    print("dotted subfield init: ns.index=% name.index=% typed_value.data=%\n",
          attr.ns.index, attr.name.index, attr.typed_value.data);

    // --- Bare type-inferred array literal: .[1, 2, 3] (element type inferred from the target) ---
    nums: [3] int = .[1, 2, 3];
    assert(nums[0] == 1 && nums[1] == 2 && nums[2] == 3);
    print("bare .[...] array literal: nums = %\n", nums);

    // --- Non-dot struct literal {3, 4} as a CALL ARGUMENT ---
    assert(sum_vec({3, 4}) == 7);

    // --- Non-dot struct literal against a typed declaration / assignment target ---
    p: Vec2 = {3, 4};          // in the type slot of a declaration
    assert(p.x == 3 && p.y == 4);
    p = {7, 8};                // as an assignment RHS (type known from p)
    assert(p.x == 7 && p.y == 8);
    print("non-dot literal (call/decl/assign): sum=% p=%\n", sum_vec(.{3, 4}), p);

    // --- Non-dot 'return {};' / 'return { a, b };' from a struct-returning proc ---
    d := make_default_vec();
    assert(d.x == 0 && d.y == 0);
    m := make_vec();
    assert(m.x == 5 && m.y == 6);
    print("non-dot return: default=% valued=%\n", d, m);

    // --- Nested non-dot struct literals inside an array literal: X.[ {..}, {..} ] ---
    // CHANGELOG beta 0.2.022: a = .[{3, "Yes"}, {2, "No"}] instead of a = .[.{...}, .{...}].
    pairs := Pair.[{3, "Yes"}, {2, "No"}];
    assert(pairs[0].n == 3 && pairs[0].s == "Yes" && pairs[1].n == 2 && pairs[1].s == "No");
    print("nested non-dot in array literal: pairs = %\n", pairs);

    // --- The "if x == {}" special case (parser: NOT a switch statement) ---
    // beta 0.2.023 added a parser special case so 'if x == {}' compares x to the empty struct
    // literal instead of parsing as 'if x == { case ...; }'. The empty {} infers x's type.
    z: Vec2;                          // zero-initialized
    matched_empty := false;
    if z == {}  matched_empty = true; // real comparison via our operator==, not a switch
    assert(matched_empty);

    // A NON-empty comparison still needs a type designator (the special case covers only "{}"):
    assert(p == Vec2.{7, 8});
    print("if x == {} special case: matched_empty=%\n", matched_empty);

    print("PASS: struct/array literals (indexed, mixed named+indexed, dotted subfield, bare .[...], non-dot {} call/decl/assign/return, nested non-dot in array, if x == {})\n");
}
