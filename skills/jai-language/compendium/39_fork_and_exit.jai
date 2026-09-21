// Compendium: fork / _exit, and why Jai's print survives both
// Jai Version: beta 0.2.030
// Platform: Linux x86-64
// Sources: empirically established against the beta 0.2.030 compiler (2026-09-20),
//   while building screen-killer's LINGER step (a screenshot tool that forks a child
//   to keep serving the Wayland clipboard after the foreground process exits).
//   modules/POSIX/bindings/linux/base.jai supplies fork/_exit/waitpid/dup2/pipe2;
//   modules/Runtime_Support.jai:307-320 is the write path this file measures.
// Proves (cheatsheet): File I/O and String Formatting > POSIX Process Control
//   (`#import "POSIX"`) -- fork / _exit / waitpid, and print's unbuffered write(2)
// Use-cases: daemonising or backgrounding from a Jai program; anything that must
//   outlive its parent (clipboard owners, servers); knowing whether buffered output
//   can be lost or duplicated across a fork.
//
// WHAT THIS ESTABLISHES, all asserted below:
//
//   1. `fork` and `_exit` are ordinary POSIX bindings and work from Jai:
//      `fork :: () -> s32 #foreign libc` returns 0 in the child and the child's pid
//      in the parent; `_exit :: (s32) -> void #foreign libc` ends the child without
//      running atexit handlers. `waitpid` reports the child's status in the usual
//      encoded form (exit code in bits 8-15, hence `(status >> 8) & 0xFF`).
//
//   2. Memory is copy-on-write, as POSIX says: everything written before the fork is
//      visible to the child, and everything the child writes afterwards is invisible
//      to the parent. Proven through a pipe rather than by assertion-in-the-child,
//      because an assert in a forked child is reported by nobody.
//
//   3. **Jai's `print` / `log` are UNBUFFERED on Unix.** Runtime_Support's
//      `write_string_unsynchronized` loops on a raw `write(2)` to fd 1 — there is no
//      stdio buffer anywhere in the path. This is the fact that makes fork safe here,
//      and it is NOT the C behaviour a reader would assume: in C, stdout is
//      line-buffered to a tty and fully buffered to a pipe, so a `printf` before a
//      fork sits in a buffer that BOTH processes inherit and BOTH flush — the classic
//      duplicated-output bug — and a parent that then calls `_exit` loses its own copy
//      entirely. Neither can happen in Jai: the bytes are already in the kernel.
//      Measured here by reading them back off a non-blocking pipe IMMEDIATELY after
//      the print, with the process still running.
//
// WHY IT MATTERS: "fork, parent _exits, child keeps serving" is only correct if the
// parent has nothing buffered to lose and the child nothing to duplicate. In Jai that
// is free. Anything the program buffers ITSELF (a String_Builder, a file you opened)
// is of course still yours to flush before forking.

#import "Basic";
POSIX :: #import "POSIX";

MARKER :: "unbuffered-marker\n";

main :: () {
    // ── (3) print writes straight through to the fd ─────────────────────────────
    // Redirect fd 1 to a pipe, print, and read it back before anything exits. A
    // buffered implementation would have nothing for us to read yet.
    saved_stdout := POSIX.dup(1);
    assert(saved_stdout >= 0, "dup(1) failed");

    out: [2] s32;
    assert(POSIX.pipe2(*out, POSIX.O_NONBLOCK) == 0, "pipe2 failed");

    assert(POSIX.dup2(out[1], 1) >= 0, "dup2 onto stdout failed");
    print(MARKER);
    n := POSIX.read(out[0], captured.data, cast(u64) captured.count);
    assert(POSIX.dup2(saved_stdout, 1) >= 0, "restoring stdout failed");   // from here, print is visible again
    POSIX.close(saved_stdout);
    POSIX.close(out[1]);
    POSIX.close(out[0]);

    assert(n == MARKER.count, tprint("expected % bytes back from the pipe with the process still alive, got % (a negative count means EAGAIN: buffered)", MARKER.count, n));
    read_back: string = ---;
    read_back.data  = captured.data;
    read_back.count = n;
    assert(read_back == MARKER, "the bytes read back are the ones print wrote");

    // ── (1) + (2) fork, copy-on-write, _exit, waitpid ───────────────────────────
    // The child reports what it saw through a pipe; the parent checks that the
    // child's later writes did not reach it.
    shared := 11;                      // written BEFORE the fork: the child must see 11

    chan: [2] s32;
    assert(POSIX.pipe2(*chan, 0) == 0, "pipe2 for the child channel failed");

    CHILD_EXIT_CODE :: 7;

    pid := POSIX.fork();
    assert(pid >= 0, "fork failed");

    if pid == 0 {
        // THE CHILD. It has its own copy of everything, including `shared` and the
        // fd table. Report what it inherited, mutate it, then leave by _exit — no
        // atexit handlers, no teardown of state the parent still owns.
        POSIX.close(chan[0]);
        seen := shared;
        shared = 22;                   // invisible to the parent: copy-on-write
        POSIX.write(chan[1], *seen, cast(u64) size_of(int));
        POSIX.close(chan[1]);
        POSIX._exit(CHILD_EXIT_CODE);
    }

    // THE PARENT.
    POSIX.close(chan[1]);
    child_saw: int = -1;
    got := POSIX.read(chan[0], *child_saw, cast(u64) size_of(int));
    POSIX.close(chan[0]);
    assert(got == size_of(int), "the child's report did not arrive whole");
    assert(child_saw == 11, "the child inherited the value written before the fork");
    assert(shared == 11, "the child's later write did NOT reach the parent (copy-on-write)");

    status: s32;
    reaped := POSIX.waitpid(pid, *status, 0);
    assert(reaped == pid, "waitpid returned another pid");
    exit_code := (status >> 8) & 0xFF;
    assert(exit_code == CHILD_EXIT_CODE, tprint("the child's _exit status reached waitpid: wanted %, got %", CHILD_EXIT_CODE, exit_code));

    print("PASS: fork/_exit (fork returns 0 in the child and the pid in the parent;\n");
    print("  _exit's status reaches waitpid as (status >> 8) & 0xFF; memory is\n");
    print("  copy-on-write; and Jai's print is an unbuffered write(2) on Unix, so a\n");
    print("  fork can neither lose it nor duplicate it)\n");
}

// File-scope so the redirect window above stays free of allocations — nothing in it
// can touch the temporary allocator while stdout is pointed at a pipe.
captured: [256] u8;
