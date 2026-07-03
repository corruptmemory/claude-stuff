// Compendium: Struct Field Directives (#align, #overlay, anonymous types)
// Jai Version: beta 0.2.030
// Platform: Linux x86-64
// Sources: modules/Float16.jai, modules/Runtime_Support.jai, modules/Pool.jai,
//          modules/Android/native_app.jai, modules/File_Async/module.jai
// Use-cases: #align on struct fields, #overlay for field aliasing,
//   anonymous struct/enum/union as field types
// Compiled: yes (jai-linux, 2026-02-13)

#import "Basic";

// === #overlay — alias a field over another's memory ===
// Source: modules/Float16.jai line 27
Matrix2 :: struct {
    _11, _12: float;
    _21, _22: float;

    #overlay (_11) floats: [4] float;  // overlays _11's memory location
}

// === #align — field alignment directive ===
// Source: modules/Runtime_Support.jai line 384
// Syntax: field_name: Type #align N;  (N is alignment in bytes)
AlignedData :: struct {
    x: u8;
    data: [64] u8 #align 16;       // aligned to 16-byte boundary
    y: u32 #align 4;               // aligned to 4 bytes
}

// === Anonymous struct/enum/union as field types ===
// Source: modules/Pool.jai line 96, modules/File_Async/module.jai line 111
Options :: struct {
    // Anonymous enum as field type
    code: enum { NONE; SUCCESS; FAILURE; };

    // Anonymous enum_flags with :: constant values
    flags: enum_flags u32 {
        READ   :: 0x1;
        WRITE  :: 0x2;
        EXEC   :: 0x4;
    };

    // Anonymous struct as field type
    inner: struct {
        x: int;
        y: int;
    };

    // Anonymous union as field type
    value: union {
        as_int: int;
        as_float: float64;
    };
}

main :: () {
    // #overlay demo
    m := Matrix2.{1.0, 2.0, 3.0, 4.0};
    print("m.floats[2] = % (should be 3.0)\n", m.floats[2]);

    // #align demo
    print("AlignedData size = %\n", size_of(AlignedData));

    // Anonymous types demo
    o: Options;
    print("Options size = %\n", size_of(Options));
}
