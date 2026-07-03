// Compendium: Structs
// Jai Version: beta 0.2.030
// Platform: Linux x86-64
// Sources: how_to/070_structs.jai, how_to/080_using.jai,
//   how_to/044_using_advanced/main.jai (using,only/except/map),
//   how_to/008_types.jai (#as using base), how_to/170_modify.jai (#modify on struct),
//   how_to/935_type_info_reduction.jai (#type_info_* modifiers)
// Use-cases: basic struct, defaults, using, embedding, polymorphic struct,
//   struct literals, struct modifiers (#place REMOVED in 0.2.027, use #overlay),
//   filtered using (,only / ,except / ,map), #as using (implicit *Derived->*Base),
//   #type_info_none / #type_info_procedures_are_void_pointers / #type_info_no_size_complaint,
//   #modify on an instantiated polymorphic struct, uninitialized field (= ---),
//   in-body field override of an embedded struct

#import "Basic";

// Basic struct
Vector2 :: struct {
    x: float;
    y: float;
}

// Struct with defaults
Config :: struct {
    name: string;
    count := 0;              // := default
    enabled := true;
}

// Embedding with using
Entity :: struct {
    id: int;
    name: string;
}

Player :: struct {
    using base: Entity;      // fields of Entity promoted
    score: int;
}

// Polymorphic struct
Pair :: struct (T: Type) {
    first: T;
    second: T;
}

// Struct with #no_padding (goes AFTER closing brace)
PackedData :: struct {
    a: u8;
    b: u32;
} #no_padding

// --- Filtered 'using' on a struct field (how_to/044_using_advanced) ---
// The plain 'using' promotes ALL fields; the modifiers filter which names leak.
Inner :: struct {
    alpha: int;
    beta:  int;
}

// ,except takes an identifier-ref to a constant array of names to SKIP.
EXCLUDE_NAMES :: string.["beta"];

// ,map takes a compile-time proc that rewrites the promoted names in place.
prefix_field_names :: (names: [] string) {
    for * names  it.* = tprint("m_%", it.*);   // alpha -> m_alpha, beta -> m_beta
}

Only_Holder :: struct {
    using,only(alpha) inner: Inner;            // ONLY 'alpha' is promoted
}

Except_Holder :: struct {
    using,except EXCLUDE_NAMES inner: Inner;   // everything EXCEPT names in EXCLUDE_NAMES
}

Map_Holder :: struct {
    using,map(prefix_field_names) inner: Inner; // promoted under rewritten names
}

// --- #as using: embed a base AND grant implicit Derived->Base conversion ---
Doc_Base :: struct {
    tag: int;
}

Doc_Derived :: struct {
    #as using base: Doc_Base;   // promotes base's fields AND makes Doc_Derived act-as Doc_Base
    extra: int;
}

read_tag_by_pointer :: (b: *Doc_Base) -> int { return b.tag; }  // *Doc_Derived converts to *Doc_Base
read_tag_by_value   :: (b:  Doc_Base) -> int { return b.tag; }  // Doc_Derived converts to Doc_Base

// --- In-body field override of an embedded struct (how_to/008_types) ---
// A derived struct can set a default for an embedded base field right in its body.
Doc_Executable :: struct {
    #as using base: Doc_Base;
    base.tag = 99;              // default override: every Doc_Executable starts with tag 99
    is_rootkit := false;
}

// --- #type_info_* reduction modifiers (how_to/935_type_info_reduction) ---
// #type_info_none strips runtime members from the baked Type_Info.
Hidden_Fields :: struct #type_info_none {
    a, b, c: float;
}

// #type_info_procedures_are_void_pointers reports proc members as *void in Type_Info.
Procs_As_Void :: struct #type_info_procedures_are_void_pointers {
    value: int;
    fn: (x: int) -> int;
}

// #type_info_no_size_complaint suppresses the big-struct Type_Info size warning.
Quiet_Big :: struct #type_info_no_size_complaint {
    data: [4] int;
}

// --- #modify on a polymorphic struct: validate/adjust the polymorph params ---
// N is clamped up to a floor of 8 when the struct is instantiated.
Min_Array :: struct (N: int, T: Type)
#modify { if N < 8  N = 8;  return true; }
{
    values: [N] T;
}

// --- Uninitialized field (= ---): skip default-init for this member ---
Scratch_Buf :: struct {
    ready:   bool;
    scratch: [3] int = ---;    // deliberately uninitialized storage
}

main :: () {
    // Struct literal (named fields)
    v := Vector2.{x = 3.0, y = 4.0};
    print("v = (%, %)\n", v.x, v.y);

    // Struct literal (positional)
    v2 := Vector2.{1.0, 2.0};
    print("v2 = (%, %)\n", v2.x, v2.y);

    // Type-inferred literal
    v3 : Vector2 = .{5.0, 6.0};
    print("v3 = (%, %)\n", v3.x, v3.y);

    // Config with defaults
    cfg := Config.{name = "test"};
    print("cfg: name=% count=% enabled=%\n", cfg.name, cfg.count, cfg.enabled);

    // Using (promoted fields)
    p := Player.{base = .{id = 1, name = "Hero"}, score = 100};
    print("player: id=% name=% score=%\n", p.id, p.name, p.score);

    // Polymorphic struct
    pair := Pair(int).{first = 10, second = 20};
    print("pair: % %\n", pair.first, pair.second);

    // Array literal
    arr := int.[1, 2, 3, 4, 5];
    for arr  print("  arr[%] = %\n", it_index, it);

    // --- Filtered 'using' (,only / ,except / ,map) ---
    oh: Only_Holder;
    oh.alpha = 1;              // 'alpha' promoted
    oh.inner.beta = 2;         // 'beta' NOT promoted -> must dereference
    assert(oh.alpha == 1 && oh.inner.beta == 2);

    eh: Except_Holder;
    eh.alpha = 3;              // 'alpha' promoted
    eh.inner.beta = 4;         // 'beta' excluded -> must dereference
    assert(eh.alpha == 3 && eh.inner.beta == 4);

    mh: Map_Holder;
    mh.m_alpha = 5;            // promoted under the rewritten name
    mh.m_beta  = 6;
    assert(mh.inner.alpha == 5 && mh.inner.beta == 6);
    print("filtered using: only=%, except=%, map=(%, %)\n",
          oh.alpha, eh.alpha, mh.m_alpha, mh.m_beta);

    // --- #as using: implicit Derived->Base conversion ---
    d: Doc_Derived;
    d.tag = 42;                // 'tag' promoted from the embedded base
    d.extra = 7;
    assert(read_tag_by_pointer(*d) == 42);   // *Doc_Derived -> *Doc_Base
    assert(read_tag_by_value(d)    == 42);    //  Doc_Derived ->  Doc_Base
    print("#as using: tag via pointer=%, via value=%\n",
          read_tag_by_pointer(*d), read_tag_by_value(d));

    // --- In-body field override of an embedded base ---
    exe: Doc_Executable;       // default-initialized
    assert(exe.tag == 99);     // the in-body 'base.tag = 99' took effect
    print("in-body override: exe.tag=%\n", exe.tag);

    // --- #type_info_none: members stripped from Type_Info ---
    assert(type_info(Hidden_Fields).members.count == 0);

    // --- #type_info_procedures_are_void_pointers: proc member reads as *void ---
    fn_is_void_ptr := false;
    for type_info(Procs_As_Void).members {
        if it.name == "fn" {
            assert(it.type.type == .POINTER);
            assert((cast(*Type_Info_Pointer) it.type).pointer_to.type == .VOID);
            fn_is_void_ptr = true;
        }
    }
    assert(fn_is_void_ptr);
    print("type_info reductions: none.members=%, fn-as-void-ptr=%\n",
          type_info(Hidden_Fields).members.count, fn_is_void_ptr);

    // --- #type_info_no_size_complaint: compiles + instantiates cleanly ---
    qb: Quiet_Big;
    qb.data[0] = 7;
    assert(qb.data[0] == 7);

    // --- #modify on an instantiated polymorphic struct ---
    small: Min_Array(3, float);     // asked for 3; #modify clamps N up to 8
    big:   Min_Array(16, float);    // 16 >= 8, left alone
    assert(small.N == 8 && small.values.count == 8);
    assert(big.N == 16);
    print("#modify clamp: requested 3 -> N=%, values.count=%\n",
          small.N, small.values.count);

    // --- Uninitialized field (= ---) ---
    sb: Scratch_Buf;
    sb.ready = true;
    sb.scratch[0] = 11;             // storage exists; we assign then read it back
    assert(sb.ready && sb.scratch[0] == 11);
    print("uninit field: ready=%, scratch[0]=%\n", sb.ready, sb.scratch[0]);

    print("PASS: structs (literals, using, embedding, polymorph, filtered-using, #as using, #type_info_*, #modify, = ---)\n");
}
