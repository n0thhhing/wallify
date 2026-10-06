#!/usr/bin/env python3
"""Small filesystem operations shared by build, packaging, and watch mode."""
import ctypes
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys


def write_changed(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    if not path.exists() or path.read_text() != content:
        temporary = path.with_suffix(path.suffix + ".tmp")
        temporary.write_text(content)
        temporary.replace(path)


def identity(root, mode, inspector, architecture):
    def git(*args):
        result = subprocess.run(["git", *args], capture_output=True, text=True)
        return result.stdout.strip() if result.returncode == 0 else ""

    commit = git("rev-parse", "--short=12", "HEAD") or "unknown"
    dirty = bool(git("status", "--porcelain", "--untracked-files=normal"))
    label = f"{mode} • {architecture} • {commit}{' (modified)' if dirty else ''} • Inspector {'on' if inspector == 'true' else 'off'}"
    info = dict(configuration=mode, inspector=inspector == "true", architecture=architecture,
                commit=commit, modified=dirty, label=label)
    write_changed(root / "build-info.json", json.dumps(info, indent=2) + "\n")
    write_changed(root / "BuildIdentity.swift", "enum WallifyBuildIdentity {\n    static let label = " + json.dumps(label, ensure_ascii=False) + "\n}\n")
    print(label)


def select(root):
    build = Path("build")
    temporary = build / ".current.tmp"
    temporary.unlink(missing_ok=True)
    temporary.symlink_to(root.relative_to(build))
    temporary.replace(build / "current")
    for name in ("bin", "lib", "resources"):
        link = build / name
        if link.is_symlink() and os.readlink(link) == f"current/{name}":
            continue
        # Migrate generated directories from the old shared-output layout.
        if link.is_dir() and not link.is_symlink():
            shutil.rmtree(link)
        else:
            link.unlink(missing_ok=True)
        link.symlink_to(f"current/{name}")


def watch_snapshot():
    # ponytail: metadata-only scan; hash contents if edits preserve size and mtime.
    files = [Path("run")]
    for directory in ("src", "assets", "config", "scripts", "tests"):
        files.extend(path for path in Path(directory).rglob("*") if path.is_file())
    digest = hashlib.sha256()
    for path in sorted(files):
        if path.name == ".DS_Store" or path.suffix in (".log", ".tmp", ".pyc") or "__pycache__" in path.parts:
            continue
        try:
            stat = path.stat()
        except FileNotFoundError:  # An editor can replace a file during a scan.
            continue
        digest.update(f"{path}:{stat.st_mtime_ns}:{stat.st_size}\n".encode())
    print(digest.hexdigest())


def digest_paths(paths):
    digest = hashlib.sha256()
    for path in sorted(paths):
        digest.update(str(path).encode() + b"\0")
        if path.is_symlink():
            digest.update(os.readlink(path).encode())
        elif path.is_file():
            digest.update(str(path.stat().st_mode & 0o777).encode())
            with path.open("rb") as stream:
                for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                    digest.update(chunk)
        else:
            digest.update(b"missing")
    return digest.hexdigest()


def bundle_digest(bundle):
    # Relative paths keep the digest stable when a staging directory is published.
    previous = Path.cwd()
    try:
        os.chdir(bundle)
        return digest_paths(path for path in Path(".").rglob("*") if not path.is_dir())
    finally:
        os.chdir(previous)


def package_signature(root):
    paths = [root / "bin/wallify", root / "bin/default.metallib",
             root / "lib/libmetadata_fetcher.dylib", root / "build-info.json",
             Path("scripts/package-app.sh"), Path("scripts/build-tools.py"),
             Path("scripts/Wallify.entitlements"), Path("config/widget-settings.conf"),
             Path("assets/AppIcon.icns"), Path("assets/spotify_icon.png"),
             Path(shutil.which("codesign") or "/usr/bin/codesign")]
    paths.extend(Path("assets/sprites/bin").glob("*.bin"))
    print(digest_paths(paths))


def cached(bundle, signature):
    try:
        saved = json.loads(bundle.with_suffix(".package-cache.json").read_text())
        return saved == {"input": signature, "output": bundle_digest(bundle)}
    except (OSError, ValueError):
        return False


def publish(staged, destination):
    if not destination.exists():
        staged.rename(destination)
        return
    # Darwin's RENAME_SWAP keeps the old bundle available until a single atomic
    # exchange. Unsupported filesystems fail safely, leaving the old app intact.
    libc = ctypes.CDLL(None, use_errno=True)
    rename = libc.renamex_np
    rename.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint]
    rename.restype = ctypes.c_int
    if rename(os.fsencode(staged), os.fsencode(destination), 0x00000002) != 0:
        error = ctypes.get_errno()
        raise OSError(error, os.strerror(error), str(destination))


if __name__ == "__main__":
    action, *args = sys.argv[1:]
    if action == "identity":
        identity(Path(args[0]), *args[1:])
    elif action == "select":
        select(Path(args[0]))
    elif action == "watch":
        watch_snapshot()
    elif action == "package-signature":
        package_signature(Path(args[0]))
    elif action == "cached":
        sys.exit(0 if cached(Path(args[0]), args[1]) else 1)
    elif action == "stamp":
        bundle = Path(args[0])
        write_changed(bundle.with_suffix(".package-cache.json"), json.dumps({"input": args[1], "output": bundle_digest(bundle)}) + "\n")
    elif action == "publish":
        publish(Path(args[0]), Path(args[1]))
    else:
        raise SystemExit(f"Unknown build operation: {action}")
