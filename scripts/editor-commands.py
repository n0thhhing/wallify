#!/usr/bin/env python3
"""Expose Swift and native compiler invocations to SourceKit-LSP and clangd."""
import json
from pathlib import Path
import sys

commands = [[]]
for argument in sys.argv[1:]:
    if argument == "--":
        commands.append([])
    else:
        commands[-1].append(argument)

entries = {}
for command in commands:
    assert command[0] == "xcrun" and Path(command[1]).name in ("swiftc", "clang++"), command
    arguments = command[1:]
    for source in arguments:
        if source.endswith((".swift", ".cpp", ".mm", ".h")) and not source.startswith("-"):
            # A Swift bridging header is an option value, not a separate input.
            if arguments[0] == "swiftc" and not source.endswith(".swift"):
                continue
            # App settings win for shared sources; tests keep their own callbacks
            # and @main entry point instead of importing the application's ones.
            entries.setdefault(source, {"directory": str(Path.cwd()), "file": source,
                                        "arguments": arguments})

destination = Path("compile_commands.json")
content = json.dumps(list(entries.values()), indent=2) + "\n"
if not destination.exists() or destination.read_text() != content:
    destination.write_text(content)
