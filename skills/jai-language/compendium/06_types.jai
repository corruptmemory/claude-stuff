// Compendium: Types
// Jai Version: beta 0.2.028
// Platform: Linux x86-64
// Sources: how_to/010_calling_procedures.jai, how_to/015_array_literals.jai
// Use-cases: primitives, pointers, arrays, slices, dynamic arrays,
//   procedure types, type_of, size_of, type_info, cast, autocast

#import "Basic";

// Procedure type declaration
Comparator :: #type (int, int) -> bool;

// Distinct type (creates new type that is not interchangeable)
Meters :: #type,distinct float;

less_than :: (a: int, b: int) -> bool { return a < b; }

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
}
