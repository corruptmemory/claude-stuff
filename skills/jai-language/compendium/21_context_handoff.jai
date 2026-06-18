// Compendium: Context handoff across thread / non-Jai boundaries
// Jai Version: beta 0.2.029
// Platform: Linux x86-64
// Sources: modules/Thread/primitives.jai (starting_context), how_to/011_context.jai
// Use-cases: hand-rolling a context across a boundary where Jai's implicit
//            `context` does NOT propagate — a new thread, or a #c_call callback
//            invoked by a C library (libwayland-style listener + void* user_data).
//
// The implicit `context` is passed only between ordinary Jai procedures. It does
// NOT cross a thread boundary, and a #c_call proc (the shape a C library calls
// back into) gets NO context at all. To do context-dependent work there — allocate,
// log / log_error, tprint, or call any context-taking proc — hand-roll the handoff,
// the standard library's own idiom (modules/Thread/primitives.jai, starting_context):
//
//   1. CAPTURE the safe ingredient fields from the LIVE context into a #Context
//      template (a plain variable), on the source thread, in normal context.
//   2. CARRY *template across the boundary through the available channel — a field
//      on a Thread-like struct, or a C API's void* user_data (the reason such APIs
//      almost always hand you one).
//   3. REBUILD + push_context on the far side (a #c_call has no implicit context).
//
// Two load-bearing subtleties, both demonstrated below:
//   - temporary_storage: a CONCURRENT thread needs its OWN arena (two bump
//     allocators sharing one arena is silent corruption) — Thread allocates a fresh
//     buffer. A SYNCHRONOUS nested callback (the C lib calls you back on your own
//     thread, then returns) BORROWS the caller's, exactly as any nested call does —
//     just copy context.temporary_storage.
//   - REFRESH, don't snapshot: re-run the capture before every hand-off, not once
//     at init. A stale snapshot pins callbacks to the init-time logger/allocator, so
//     a callback's log_error bypasses a logger installed later (a test's recorder) —
//     defeating the error-as-signal discipline. Demo B proves the refresh matters.

#import "Basic";

// ============================================================================
// A custom logger that records what it receives. Makes "did the callback's log
// reach me through the handed-through context?" an assertable fact (the
// error-recording-logger discipline).
// ============================================================================
Recorder :: struct {
    count: int;
    last:  string;
}

recording_logger :: (message: string, data: *void, info: Log_Info) {
    rec := cast(*Recorder) data;
    rec.count += 1;
    rec.last   = message;
}

// ============================================================================
// The #Context TEMPLATE — the analogue of Thread's `starting_context`. A plain
// variable, NOT the live context. capture_dispatch_context() refreshes its safe
// ingredient fields from whatever context is live when it is called.
// ============================================================================
dispatch_template: #Context;

capture_dispatch_context :: () {
    dispatch_template.allocator         = context.allocator;
    dispatch_template.logger            = context.logger;
    dispatch_template.logger_data       = context.logger_data;
    dispatch_template.assertion_failed  = context.assertion_failed;
    // SYNCHRONOUS nested callback: borrow the caller's temp arena. (A concurrent
    // Thread would instead OWN a freshly-allocated one — see the header note.)
    dispatch_template.temporary_storage = context.temporary_storage;
}

// ============================================================================
// The non-Jai side, modeled: a C library stores a callback function pointer plus
// an opaque user_data, and invokes the callback with no Jai context in sight.
// ============================================================================
Foreign_Listener :: struct {
    callback: (data: *void) #c_call;   // C calling convention => NO implicit context
    data:     *void;                   // the user_data channel we ride for the handoff
}

// Stand-in for the C library's own dispatch — itself #c_call (no Jai context).
foreign_dispatch :: (listener: *Foreign_Listener) #c_call {
    listener.callback(listener.data);
}

// THE CALLBACK Jai registers with the C library. Because it is #c_call, `context`
// is unavailable until we rebuild one from the carried template and push it.
on_event :: (data: *void) #c_call {
    new_ctx := (cast(*#Context) data).*;   // rebuild — the #c_call analogue of
                                           // `new_context := thread.starting_context`
    push_context new_ctx {
        // `context` is valid in here: tprint (temp storage) + log (logger) both use
        // the handed-through context, so this routes to whoever captured it.
        log("handled: %", tprint("temp-allocated %", 6 * 7));
    }
}

main :: () {
    // ---- Demo A: hand the live context to a C callback through user_data -----
    rec_a: Recorder;
    ctx_a := context;
    ctx_a.logger      = recording_logger;
    ctx_a.logger_data = *rec_a;

    push_context ctx_a {
        capture_dispatch_context();                  // refresh template from THIS live context
        listener := Foreign_Listener.{ callback = on_event, data = *dispatch_template };
        foreign_dispatch(*listener);                 // C calls back into Jai; no context crosses
    }
    assert(rec_a.count == 1, "the callback's log reached the captured logger");
    print("Demo A — handoff worked: count=%, msg=\"%\"\n", rec_a.count, rec_a.last);

    // ---- Demo B: REFRESH, don't snapshot -------------------------------------
    // Install a DIFFERENT logger, RE-capture, dispatch again. A correct refresh
    // routes to rec_b; a stale init-time snapshot would wrongly still hit rec_a.
    rec_b: Recorder;
    ctx_b := context;
    ctx_b.logger      = recording_logger;
    ctx_b.logger_data = *rec_b;

    push_context ctx_b {
        capture_dispatch_context();                  // RE-capture against the new live context
        listener := Foreign_Listener.{ callback = on_event, data = *dispatch_template };
        foreign_dispatch(*listener);
    }
    assert(rec_b.count == 1, "the re-captured logger received the second dispatch");
    assert(rec_a.count == 1, "the first logger did NOT receive the second dispatch (no staleness)");
    print("Demo B — refresh works: rec_b=%, rec_a still % (no stale snapshot)\n", rec_b.count, rec_a.count);

    print("PASS: context handoff across the #c_call boundary, with live refresh.\n");
}
