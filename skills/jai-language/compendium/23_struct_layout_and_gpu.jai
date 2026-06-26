// Compendium: Struct memory layout & GPU std140/std430 padding
// Jai Version: beta 0.2.029
// Platform: Linux x86-64
// Sources: how_to/ (struct layout), modules/Math (Vector3/Vector4),
//          modules/Float16.jai (#overlay), modules/Runtime_Support.jai (#align)
// Use-cases: matching a Jai struct to a GPU buffer layout (push constants, UBO/SSBO
//            under std140/std430) — and knowing exactly what #align can and cannot do.
//
// FOUR RULES, each verified by an assert below:
//
//  1. Jai struct layout is C-style NATURAL alignment: each field sits at its type's
//     alignment, struct alignment = max member alignment, size rounds up to that.
//     (#no_padding opts out.) Math.Vector3 is 12 bytes / align 4 — it is NOT
//     SIMD-16-aligned. So {Vector3; Vector3; Vector4} is offsets 0/12/24, size 40.
//     (Don't GUESS this per language — many ABIs 16-align vector types. Jai doesn't.)
//
//  2. `#align N` is a field-START operator: it rounds where a field BEGINS up to the
//     power-of-2 N and raises the struct's alignment to >= N. It does NOT change
//     layout INSIDE a field's type, so it cannot create array element stride or
//     matrix-column padding. `[4] float #align 16` is 16 bytes, NOT std140's 64.
//
//  3. std140/std430 demand padding INSIDE aggregates: in std140 every array element
//     rounds to a 16-byte STRIDE; in std430 vec3/struct/matrix-column elements round
//     to 16; a mat3 is 3 columns each padded vec3 -> vec4 (48 bytes). Reproducing
//     that needs a layout-correct ELEMENT TYPE, not `#align` on the array field.
//
//  4. GOTCHA: `#overlay` aliases memory but does NOT propagate the overlaid member's
//     alignment to the struct. An overlay over [S]u8 has alignment 1 — so an array of
//     it is not 16-aligned. Bake alignment in with `#align S` on the storage.
//
// The codegen lesson: an emitter that pads to EXACT reflected byte offsets reproduces
// any std140/std430 layout; `#align` only reaches layouts whose offsets happen to be
// power-of-2 boundaries (true for scalar/vec/mat4 field starts, false for the strides
// in rule 3). The `Fatty($S,$T)` primitive at the bottom is the composable "give a
// type a GPU stride" building block #align alone can't express.

#import "Basic";
#import "Math";   // Vector3 (12 bytes, align 4), Vector4 (16 bytes)

// ── Rule 1: natural alignment ──────────────────────────────────────────────────
#assert size_of(Vector3) == 12;            // packed 3 floats, align 4 (NOT 16)
#assert size_of(Vector4) == 16;
Natural :: struct { a: Vector3; b: Vector3; c: Vector4; }
#assert size_of(Natural) == 40;            // 0 / 12 / 24 — NOT std430's 0/16/32 size 48

// std430 wants 0/16/32 size 48 — reach it by padding to the EXACT reflected offsets:
Std430 :: struct {
    center: Vector3;  _pad12: [4] u8;      // -> scale begins at 16
    scale:  Vector3;  _pad28: [4] u8;      // -> color begins at 32
    color:  Vector4;
}
#assert size_of(Std430) == 48;

// ── Rule 2: #align positions the field START, never the element stride ─────────
Arr_Aligned :: struct { data: [4] float #align 16; }
#assert size_of(Arr_Aligned) == 16;        // NOT 64: the START is 16-aligned, the
                                           // 4-byte element stride is untouched.

// ── Rule 4 (the gotcha), shown by contrast against Rule 3's fix ────────────────
// An overlay over [16]u8 WITHOUT #align: stride is right (16) but alignment is 1.
Bare_Overlay :: struct {
    _pad: [16] u8;
    #overlay (_pad) using ff: struct { v: float; }
}
#assert size_of(Bare_Overlay) == 16;
Bare_Probe :: struct { x: u8; arr: [2] Bare_Overlay; }   // arr lands at offset 1 (!)

// ── Rule 3: a layout-correct element TYPE carries the stride: Fatty($S,$T) ──────
// "Spread T across an S-byte stride." `#assert size_of(T) <= S` is a per-instantiation
// correctness gate. `#align S` on the storage makes the type self-describe BOTH the
// stride (its size) AND the alignment — fixing the rule-4 gotcha at the type level.
Fatty :: struct ($S: int, $T: Type) {
    #assert size_of(T) <= S;
    _pad: [S] u8 #align S;
    #overlay (_pad) using ff: struct { v: T; }
}

Fat_Float :: Fatty(16, float);
#assert size_of(Fat_Float) == 16;

// std140 `float[4]` = 64 bytes with a 16-byte element stride — now expressible:
Std140_Float_Array :: struct { data: [4] Fat_Float; }
#assert size_of(Std140_Float_Array) == 64;

// The SAME primitive expresses a std430 vec3[] element and a mat3 column:
Vec3_16 :: Fatty(16, Vector3);             // size_of(Vector3)=12 <= 16, gate passes
#assert size_of(Vec3_16) == 16;
Mat3_std140 :: struct { cols: [3] Vec3_16; }  // 3 columns, each vec3 padded to 16
#assert size_of(Mat3_std140) == 48;

Fat_Probe :: struct { x: u8; arr: [2] Fat_Float; }   // arr lands at 16 (baked #align S)

main :: () {
    // Rule 4 vs its fix, via member offsets (the alignment difference #assert can't see
    // through size_of alone — Bare and Fatty are both 16 bytes, but align 1 vs 16):
    bare := cast(*Type_Info_Struct) type_info(Bare_Probe);
    assert(bare.members[1].offset_in_bytes == 1,
        "overlay-over-[S]u8 has alignment 1; arr should land at 1, got %", bare.members[1].offset_in_bytes);

    fat := cast(*Type_Info_Struct) type_info(Fat_Probe);
    assert(fat.members[1].offset_in_bytes == 16,
        "Fatty carries 16-byte alignment via `#align S`; arr should land at 16, got %", fat.members[1].offset_in_bytes);

    print("PASS: natural alignment (Vector3=12); #align is field-start-only; #overlay does not propagate alignment; Fatty($S,$T) gives a type a GPU stride+align.\n");
}
