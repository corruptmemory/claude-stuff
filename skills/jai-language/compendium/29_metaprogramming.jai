// Compendium: Metaprogramming — Code -> AST, Code root type, #add_context
// Jai Version: beta 0.2.030
// Platform: Linux x86-64
// Sources: how_to/630_compiler_get_nodes.jai (compiler_get_nodes / compiler_get_code / #insert),
//          examples/code_type.jai (Code.type, get_root_type, #code,typed),
//          how_to/011_context.jai (#add_context), modules/Compiler/Compiler.jai
// Use-cases: turn a #code value into a syntax tree at compile time, inspect/mutate
//   nodes, re-emit + #insert; query the root-expression TYPE of a Code; extend the
//   implicit Context with a user field.
//
// NOTE: compiler_get_nodes / compiler_get_code / get_root_type are #compiler procs,
// so they run only during COMPILE-TIME execution (#run). This file self-contains —
// it is a normal program (no separate metaprogram workspace needed), exactly like the
// canonical how_to/630 and examples/code_type.jai, which also compile with plain jai.

#import "Basic";
#import "Compiler";   // Code_Node, compiler_get_nodes, compiler_get_code, get_root_type, Get_Root_Type_Status

// ============================================================================
// 1. compiler_get_nodes(code) — Code -> syntax tree, inspected at COMPILE TIME.
//    Proven two ways: a compile-time #assert on the root node kind, and an
//    #insert of a mutated-and-re-emitted tree whose runtime value we assert.
// ============================================================================

answer :: 42;   // a real identifier for the ,typed section below

// A declaration Code: `local := 1 + 2`. Its root node is a DECLARATION.
DECL_CODE :: #code local := 1 + 2;

// Compile-time helpers: convert the Code to nodes and report facts about the tree.
root_kind_of :: (code: Code) -> Code_Node.Kind {
    root, expressions := compiler_get_nodes(code);   // root expr + flat node list
    return root.kind;
}
node_count_of :: (code: Code) -> int {
    root, expressions := compiler_get_nodes(code);
    return expressions.count;                        // BINARY_OP + two LITERALs + the DECLARATION, etc.
}

// #run executes the #compiler calls at compile time; the results become constants.
ROOT_KIND  :: #run root_kind_of(DECL_CODE);
EXPR_COUNT :: #run node_count_of(DECL_CODE);

// Compile-time proof: the root of `local := 1 + 2` is a DECLARATION, and the tree
// flattened to more than one node. If either were false the BUILD fails here.
#assert ROOT_KIND == .DECLARATION;
#assert EXPR_COUNT > 1;

// --- AST round-trip: mutate literals in a fresh AST copy, re-emit with
//     compiler_get_code, then #insert the result (pattern from how_to/630). ---
shout_ascii :: (s: string) -> string {
    t := copy_string(s);
    for i: 0..t.count-1 {
        c := t[i];
        if (c >= #char "a") && (c <= #char "z")  t[i] = c - 32;  // ASCII toupper
    }
    return t;
}

uppercase_string_literals :: (code: Code) -> Code {
    root, expressions := compiler_get_nodes(code);   // FRESH copy — safe to mutate
    for expressions {
        if it.kind != .LITERAL continue;
        lit := cast(*Code_Literal) it;
        if lit.value_type != .STRING continue;
        lit._string = shout_ascii(lit._string);      // destructive edit, in-place
    }
    return compiler_get_code(root);                  // syntax tree -> Code again
}

// Compile-time: build the rewritten Code (a string-literal expression, uppercased).
SHOUT_CODE :: #run uppercase_string_literals(#code "hello sailor");

// ============================================================================
// 2. Code.type (constant Code) and get_root_type + #code,typed (any Code).
// ============================================================================

// Code.type: root-expression type of a CONSTANT Code ($c makes it constant).
constant_root_type :: ($c: Code) -> Type {
    return c.type;
}

// get_root_type: works on non-constant Code, but only resolves a real type when the
// Code was typechecked. A plain #code is NOT typechecked (-> NOT_TYPED); #code,typed
// resolves it in local scope (-> SUCCESS).
status_of :: (code: Code) -> Get_Root_Type_Status {
    status, type := get_root_type(code);
    return status;
}
type_of_code :: (code: Code) -> Type {
    status, type := get_root_type(code);
    return type;
}

// Compile-time proofs of the typed/untyped contrast on the SAME expression.
STATUS_UNTYPED :: #run status_of(#code       answer + 1);   // not typechecked
STATUS_TYPED   :: #run status_of(#code,typed answer + 1);   // typechecked in scope
TYPED_ROOT_T   :: #run type_of_code(#code,typed answer + 1);

#assert STATUS_UNTYPED == .NOT_TYPED;
#assert STATUS_TYPED   == .SUCCESS;
#assert TYPED_ROOT_T   == s64;          // `answer + 1` (int + int) is s64

// ============================================================================
// 3. #add_context — add a user field to the implicit Context.
//    The directive is followed by an ordinary declaration (with a default value).
// ============================================================================

#add_context demo_value: int = 33;

main :: () {
    // --- (1) #insert of the compile-time-rewritten AST yields the uppercased value ---
    shout := #insert SHOUT_CODE;
    assert(shout == "HELLO SAILOR");
    print("compiler_get_nodes: root kind = %, node count = %, rewritten = \"%\"\n",
          ROOT_KIND, EXPR_COUNT, shout);

    // --- (2) Code.type on a constant Code, runtime-usable Type value ---
    t := constant_root_type(answer + 1);   // arg auto-wrapped into a constant Code
    assert(t == s64);
    print("Code.type of (answer + 1)   = %\n", t);
    print("get_root_type untyped/typed = % / %  (typed root type = %)\n",
          STATUS_UNTYPED, STATUS_TYPED, TYPED_ROOT_T);

    // --- (3) #add_context field round-trips through push_context ---
    assert(context.demo_value == 33);          // default from the #add_context decl
    new_ctx := context;
    new_ctx.demo_value = 99;
    push_context new_ctx {
        assert(context.demo_value == 99);      // visible inside the pushed context
    }
    assert(context.demo_value == 33);          // restored after the block pops
    print("#add_context demo_value: default 33 -> pushed 99 -> restored 33\n");

    print("PASS: 29_metaprogramming\n");
}
