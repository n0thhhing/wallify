---
name: zig-build-checker
description: Procedures and verification steps for compiling, testing, and debugging Zig 0.16.0 code with macOS C framework interop.
---

# Zig 0.16.0 Build Checker Skill

Use this skill when compiling, running test suites, and verifying memory safety in `wallify`.

---

## 1. Fast Compilation & Build Checks

Run `zig build` or compile test suites:

```bash
# Build binary
zig build

# Run unit and integration tests
zig test src/metadata_fetcher_test.zig
```

---

## 2. Dynamic Library & Symbol Verification

When loading macOS private frameworks such as `MediaRemote`:
- Ensure `dlopen` paths are checked against standard macOS locations:
  `/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote`
- Test with simple standalone checks if `dlsym` handles symbols like `MRMediaRemoteGetNowPlayingInfo`.

---

## 3. Memory & Allocator Hygiene

- Prefer `std.heap.ArenaAllocator` for request/cycle scoped allocations.
- For tests, always use `std.testing.allocator` to catch memory leaks immediately.
- Clean up any allocated C strings or CoreFoundation references using `CFRelease`.
