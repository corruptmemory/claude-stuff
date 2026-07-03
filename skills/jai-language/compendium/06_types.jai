// Compendium: Types
// Jai Version: beta 0.2.030
// Platform: Linux x86-64
// Sources: how_to/010_calling_procedures.jai, how_to/015_array_literals.jai
// Use-cases: primitives, pointers, arrays, slices, dynamic arrays,
//   procedure types, type_of, size_of, type_info, cast, autocast

#import "Basic";

// Procedure type declaration
Comparator :: #type (int, int) -> bool;

// Distinct type (creates new type that is not interchangeable)
Meters :: #type,distinct float;

// Distinct integer newtype: same u32 layout, but will NOT implicitly cast to/from u32.
// Source: how_to/180_type_variants.jai
Handle :: #type,distinct u32;

// #type,isa subtype: Filename IS-A string — implicitly downcasts to string (one-way),
// so it can be passed anywhere a string is expected. Source: how_to/180_type_variants.jai
Filename :: #type,isa string;

// Interface struct: any struct sharing these members matches $T/interface Named_Colored.
// Source: how_to/160_type_restrictions.jai (interface_matching)
Named_Colored :: struct {
    name:  string;
    color: int;
}

// Widget shares Named_Colored's members (name/color) in a different order + extra fields,
// so it structurally matches the Named_Colored interface.
Widget :: struct {
    id:    int;
    color: int;
    name:  string;
    extra: float;
}

less_than :: (a: int, b: int) -> bool { return a < b; }

// Takes a plain string — used to prove Filename (#type,isa string) downcasts implicitly.
name_length :: (s: string) -> int { return s.count; }

// Interface-constrained polymorphic proc: T must expose Named_Colored's members.
describe :: (x: $T/interface Named_Colored) -> int { return x.color + x.name.count; }

main :: () {
    // Primitives
    a : int = 42;          // int = s64
    b : u8 = 255;
    c : float = 3.14;      // float = float32
    d : float64 = 3.14159;
    e : bool = true;
    f : string = "hello";

    print("int=% u8=% float=% float64=% bool=% string=%\n", a, b, c, d, e, f);

    // Pointer
    ptr : *int = *a;
    print("ptr.* = %\n", ptr.*);

    // Fixed array
    fixed : [3] int = .[10, 20, 30];
    print("fixed[1] = %\n", fixed[1]);

    // Dynamic array
    dyn : [..] int;
    array_add(*dyn, 100);
    array_add(*dyn, 200);
    print("dyn = %\n", dyn);

    // Slice (array view)
    slice : [] int = fixed;
    print("slice = %\n", slice);

    // Procedure type
    cmp : Comparator = less_than;
    print("less_than(3,5) = %\n", cmp(3, 5));

    // Bare procedure type (without #type)
    op : (int, int) -> bool = less_than;
    print("op(5,3) = %\n", op(5, 3));

    // type_of
    print("type_of(a) = %\n", type_of(a));

    // size_of
    print("size_of(int) = %\n", size_of(int));

    // type_info
    info := type_info(int);
    print("type_info(int) = %\n", info);

    // Cast
    x := 42;
    y := cast(float) x;
    print("cast(float) 42 = %\n", y);

    // Autocast (xx)
    small : u8 = 10;
    big : int = xx small;
    print("xx u8 = %\n", big);

    // Distinct type
    distance : Meters = 5.0;
    print("distance = %\n", distance);

    // Sized integer primitives (unsigned + signed) — each declared and asserted.
    u16v : u16 = 65535;
    u32v : u32 = 4294967295;
    u64v : u64 = 18446744073709551615;
    s8v  : s8  = -128;
    s16v : s16 = -32768;
    s32v : s32 = -2147483648;
    s64v : s64 = -9223372036854775807;      // -(2^63 - 1); literal-safe minimum
    assert(u16v == 65535);
    assert(u32v == 4294967295);
    assert(u64v == 18446744073709551615);
    assert(s8v  == -128);
    assert(s16v == -32768);
    assert(s32v == -2147483648);
    assert(s64v == -9223372036854775807);
    print("sized ints: u16=% u32=% u64=% s8=% s16=% s32=% s64=%\n",
          u16v, u32v, u64v, s8v, s16v, s32v, s64v);

    // #type,isa subtype: a Filename can be USED WHERE A STRING IS EXPECTED.
    fname : Filename = cast(Filename) "cake.txt";
    flen := name_length(fname);              // implicit downcast Filename -> string
    assert(flen == 8);
    print("Filename '%' used as string, length = %\n", fname, flen);

    // Richer #type,distinct: Handle is a u32 newtype that does NOT implicitly convert.
    h : Handle = 5;                          // integer literals implicitly cast, as with any numeric type
    h = h + 1;                               // built-in math works between the same distinct type
    raw : u32 = 40;
    // h = raw;                              // ERROR (no implicit u32 -> Handle) — that IS the point
    h2 : Handle = xx (raw + 2);              // autocast an explicit u32 expression into Handle
    assert(cast(u32) h  == 6);               // explicit cast required to read back as u32
    assert(cast(u32) h2 == 42);
    print("Handle math: h=% h2=% (viewed as u32)\n", cast(u32) h, cast(u32) h2);

    // $T/interface polymorphism: Widget structurally matches Named_Colored (name + color),
    // despite different member order and extra fields.
    w : Widget;
    w.name  = "ok";
    w.color = 5;
    desc := describe(w);                     // Widget accepted by the interface-constrained proc
    assert(desc == 7);                       // color(5) + name.count(2)
    print("interface describe(Widget) = %\n", desc);

    // void as zero Type (NEW in beta 0.2.029)
    // An uninitialized Type variable holds void (not undefined).
    // void evaluates as false in if-statements; all other Types are true.
    // void is always index 0 in the type table; Type is always index 1.
    t : Type;                              // zero-initialized → void
    if t  print("t is non-void\n");
    else  print("t is void (zero-initialized Type)\n");  // prints this

    t = int;
    if t  print("t = int (truthy)\n");    // prints this

    // void is index 0 in the runtime type table
    void_info := type_info(void);
    int_info   := type_info(int);
    print("void type_info: %\n", void_info);
    print("int  type_info: %\n", int_info);

    print("PASS: sized primitives (u16/u32/u64/s8/s16/s32/s64), #type,isa subtype (Filename->string), #type,distinct newtype (Handle: cast/xx/math), and $T/interface polymorphism (Widget matches Named_Colored) all verified\n");
}
