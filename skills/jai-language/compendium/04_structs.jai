// Compendium: Structs
// Jai Version: beta 0.2.026
// Platform: Linux x86-64
// Sources: how_to/070_structs.jai, how_to/080_using.jai
// Use-cases: basic struct, defaults, using, embedding, polymorphic struct,
//   struct literals, #place, struct modifiers

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
}
