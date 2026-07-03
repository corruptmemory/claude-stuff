// Compendium: Comments
// Jai Version: beta 0.2.030
// Platform: Linux x86-64
// Proves (cheatsheet): ## Comments
// Sources: cheatsheet.md ## Comments (line comments, block comments, arbitrary nesting,
//   the Tree-Sitter `//`-in-string-literals note); modules/String/module.jai (contains)
// Use-cases: `//` line comments, `/* */` block comments wrapping out code, NESTED block
//   comments (`/* outer /* inner */ still outer */` — the key claim: real, executable code
//   sits immediately after the OUTERMOST closing `*/`, so if nesting did NOT hold — i.e. the
//   FIRST `*/` closed the whole comment, C-style — the leftover ` still outer */` text would
//   be left as bare source with no compiled meaning, and the file would fail to compile rather
//   than merely misbehave), and a string literal containing `//` (a URL) proving `//` inside a
//   string is NOT parsed as a comment start.

#import "Basic";
#import "String";  // contains()

main :: () {
    // Line comments (trivial): this whole line is ignored by the compiler.
    x := 10;  // trailing line comment — also ignored
    assert(x == 10);

    // Block comment wrapping out code. If the assignment below were live (i.e. block comments
    // did not work), x would become 999 and the assert right after would fail.
    /*
    x = 999;
    */
    assert(x == 10);

    // NESTED block comment — the key claim under test. If `/* ... */` did NOT nest arbitrarily
    // (C-style: the FIRST `*/` always closes the comment), the line below would parse as:
    //   comment: `/* outer /* inner */`   (closes at the first `*/`)
    //   bare source left over: ` still outer */`
    // — two adjacent identifiers (`still`, `outer`) with no operator between them, followed by
    // a stray `*/`, which is a syntax error. So this file compiling at all is direct proof that
    // nesting works — it isn't just described, it's load-bearing: `ran_after_nested = true;`
    // below only ever runs if the ENTIRE construct nested correctly into one comment.
    ran_after_nested := false;
    /* outer /* inner */ still outer */
    ran_after_nested = true;
    assert(ran_after_nested);

    // A string literal containing `//` — proves `//` inside a string is NOT treated as a
    // comment start (the cheatsheet's Tree-Sitter note: a lexer operating below the grammar
    // could mistake this for a line comment and truncate the string early).
    url := "https://example.com";
    print("url = %\n", url);

    found, remainder := contains(url, "//");
    assert(found);
    assert(remainder == "example.com");  // proves the bytes AFTER the "//" survived intact

    // Byte-level check too: walk the raw string and confirm two adjacent '/' characters are
    // really there (i.e. nothing truncated or reinterpreted the "//" as a comment).
    saw_double_slash := false;
    for i: 0..url.count - 2 {
        if url[i] == #char "/" && url[i + 1] == #char "/" {
            saw_double_slash = true;
            break;
        }
    }
    assert(saw_double_slash);

    print("PASS: comments (line / block / nested block / `//`-in-string) all behave correctly\n");
}
