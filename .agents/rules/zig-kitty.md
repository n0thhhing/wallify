# Workspace Rules: Zig & Kitty Development

## Core Tech Stack
- **Zig Version:** 0.16.0
- **Terminal:** Kitty
- **Primary Tooling:** Zed + Antigravity + MCP-enabled context servers.
- **Language Server:** ZLS via `mcpls`.
- **Documentation:** `zig-docs` and `kitty-docs`.

## Development Mandates

### 1. Zig Development Standards

- **Zig Version:** Always target Zig 0.16.0. Do not assume APIs from other Zig versions.
- **Standard Library & Builtins:** Always use the `zig-docs` MCP server to verify Zig standard-library APIs, builtin functions, types, and behavior when relevant.
- **LSP / ZLS Context:** Use the `mcpls` MCP server to obtain semantic information from ZLS, including types, definitions, references, symbols, diagnostics, and other LSP information.
- **Build Verification:** Prefer verifying changes with the project's actual Zig compiler and `zig build` when possible.
- **Anti-Hallucination:** Do not rely on model memory for Zig APIs when `zig-docs` or ZLS can provide authoritative information.

### 2. Kitty as the Primary Terminal Environment

Kitty is not merely an optional terminal. Treat Kitty as an integral part of the development environment.

When writing, debugging, or designing terminal-related code, consider Kitty's actual capabilities and behavior.

Use the `kitty-docs` MCP server whenever Kitty-specific behavior, capabilities, configuration, or protocols are relevant.

### 3. Kitty Documentation Standards

Prefer the official Kitty documentation:

https://sw.kovidgoyal.net/kitty/

Use `kitty-docs` to verify information involving:

- Kitty graphics protocol
- Kitty keyboard protocol
- Escape sequences
- Kitty terminal capabilities
- `kitty.conf`
- Kitty configuration options
- Kittens
- Custom kittens
- `kitten @` and remote-control functionality
- Terminal layouts
- Windows, tabs, and OS windows
- Sessions
- Launch behavior
- Environment variables
- Clipboard functionality
- Notifications
- Font and rendering behavior
- Mouse handling
- Input handling
- Unicode handling
- Images and image placement
- Terminal querying
- Shell integration
- Terminal state
- Scrollback
- Marks
- Hints
- Watchers
- Signals and terminal events
- Kitty-specific keyboard shortcuts
- Kitty-specific escape codes
- Kitty-specific environment variables
- Kitty APIs and Python kitten APIs

### 4. Kitty-Aware Implementation

When implementing terminal UI, terminal graphics, input handling, mouse interaction, keyboard handling, or terminal communication:

1. Determine whether the behavior is Kitty-specific.
2. Consult `kitty-docs` when Kitty-specific behavior is involved.
3. Prefer Kitty's documented protocols and capabilities over generic terminal assumptions.
4. Do not implement a generic terminal workaround if Kitty provides a documented mechanism that is appropriate for the project.
5. When using escape sequences or terminal protocols, verify the exact syntax, parameters, and semantics against the official Kitty documentation.
6. When implementing Kitty graphics, verify the graphics protocol rather than relying on remembered escape sequences.
7. When implementing keyboard or mouse behavior, verify Kitty's documented input protocols and terminal capabilities.

### 5. Terminal Compatibility

Do not assume Kitty behavior is identical to Ghostty, iTerm2, xterm, or other terminals.

When terminal-specific behavior matters:

- Identify the terminal protocol being used.
- Determine whether it is a standard terminal behavior or Kitty-specific.
- Use `kitty-docs` when Kitty-specific behavior is involved.
- Keep terminal-specific code isolated when practical so it can be extended to other terminals later.

### 6. Research & Verification Priority

For technical questions, prefer information sources in this order:

1. **Actual project source code**
2. **ZLS via `mcpls`**
3. **Official Zig documentation via `zig-docs`**
4. **Official Kitty documentation via `kitty-docs`**
5. Other authoritative documentation
6. Model knowledge

Do not confidently invent APIs, protocol parameters, escape sequences, configuration options, or terminal behavior when they can be verified through the available MCP tools.

### 7. Existing Project Conventions

Before introducing a new abstraction or dependency:

- Inspect the existing project structure.
- Follow existing coding conventions.
- Reuse existing utilities when appropriate.
- Check the relevant MCP documentation before implementing unfamiliar Zig or Kitty functionality.
- Avoid unnecessarily replacing working code with a different approach.

### 8. Error Investigation

When encountering a compiler, runtime, LSP, or terminal-protocol error:

- Inspect the actual error first.
- Use ZLS through `mcpls` when semantic information is useful.
- Use `zig-docs` for Zig API questions.
- Use `kitty-docs` for Kitty-specific behavior.
- Prefer reproducing the issue locally over guessing.
- Verify the proposed fix against Zig 0.16.0 and the actual Kitty environment.

### 9. Important Rule

**If a question involves something that Kitty can do, first consider whether Kitty has a documented native mechanism for it before proposing a generic workaround.**

The goal is to make implementations genuinely Kitty-aware rather than merely terminal-compatible.
