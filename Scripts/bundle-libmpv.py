#!/usr/bin/env python3
"""Copy libmpv and its full dylib closure into an app bundle.

The Homebrew libmpv is linked against a deep tree of Homebrew dylibs under
absolute `/opt/homebrew/...` paths. Shipping only `libmpv.2.dylib` would still
require Homebrew at runtime, so this script:

  1. walks the transitive non-system dependency closure,
  2. copies each real file into `Contents/Frameworks`,
  3. rewrites every install name / dependency to `@rpath/<basename>`,
  4. adds an `@loader_path` rpath so siblings resolve next to each other,
  5. re-signs each dylib ad-hoc (the main bundle is signed afterwards).

Usage:
    Scripts/bundle-libmpv.py --app build/Tangent.app --prefix /opt/homebrew/opt/mpv
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from collections import OrderedDict

SYSTEM_PREFIXES = ("/System/", "/usr/lib/", "/Library/Apple/", "/usr/local/lib/system/")


def run(*args: str) -> str:
    return subprocess.run(args, check=True, capture_output=True, text=True).stdout


def otool_dependencies(path: str) -> list[str]:
    """Every install name in LC_LOAD_DYLIB, excluding the file's own id."""
    output = run("otool", "-L", path)
    deps = []
    for line in output.splitlines()[1:]:
        line = line.strip()
        if not line:
            continue
        deps.append(line.split(" (compatibility")[0].strip())
    return deps


def rpaths(path: str) -> list[str]:
    output = run("otool", "-l", path)
    result = []
    expecting = False
    for line in output.splitlines():
        stripped = line.strip()
        if stripped.startswith("cmd LC_RPATH"):
            expecting = True
            continue
        if expecting and stripped.startswith("path "):
            result.append(stripped.split("path ", 1)[1].split(" (offset", 1)[0])
            expecting = False
    return result


def resolve(dep: str, dependent: str, search_rpaths: list[str]) -> str | None:
    """Resolve @rpath/@loader_path/@executable_path, return a real absolute path."""
    if dep.startswith("@rpath/"):
        tail = dep[len("@rpath/"):]
        for rpath in search_rpaths:
            base = rpath
            if base.startswith("@loader_path"):
                base = os.path.dirname(dependent) + base[len("@loader_path"):]
            elif base.startswith("@executable_path"):
                # The bundler only ever runs on dylibs, where this is not used.
                continue
            candidate = os.path.join(base, tail)
            if os.path.exists(candidate):
                return os.path.realpath(candidate)
        return None
    if dep.startswith("@loader_path/"):
        candidate = os.path.join(os.path.dirname(dependent), dep[len("@loader_path/"):])
        return os.path.realpath(candidate) if os.path.exists(candidate) else None
    if dep.startswith("@"):
        return None
    return os.path.realpath(dep) if os.path.exists(dep) else None


def is_system(path: str) -> bool:
    return path.startswith(SYSTEM_PREFIXES)


def formula_license_dir(real_path: str) -> tuple[str, str] | None:
    """`.../Cellar/foo/1.2/lib/x.dylib` -> (`.../Cellar/foo/1.2`, `foo`)."""
    parts = real_path.split(os.sep)
    if "Cellar" not in parts:
        return None
    index = parts.index("Cellar")
    if len(parts) <= index + 3:
        return None
    root = os.sep.join(parts[: index + 3])
    return root, parts[index + 1]


def copy_license(source_dylib: str, resources: str) -> None:
    found = formula_license_dir(source_dylib)
    if not found:
        return
    root, name = found
    destination = os.path.join(resources, "Licenses", name)
    os.makedirs(destination, exist_ok=True)
    for entry in os.listdir(root):
        lowered = entry.lower()
        if lowered.startswith(("copying", "license", "copyright", "notice")):
            full = os.path.join(root, entry)
            if os.path.isfile(full):
                shutil.copy2(full, os.path.join(destination, entry))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", required=True)
    parser.add_argument("--prefix", default="/opt/homebrew/opt/mpv")
    parser.add_argument("--root-dylib", default="libmpv.2.dylib")
    parser.add_argument("--quiet", action="store_true")
    arguments = parser.parse_args()

    app = os.path.abspath(arguments.app)
    frameworks = os.path.join(app, "Contents", "Frameworks")
    resources = os.path.join(app, "Contents", "Resources")
    root_dylib = os.path.join(arguments.prefix, "lib", arguments.root_dylib)

    if not os.path.exists(root_dylib):
        print(f"error: {root_dylib} not found", file=sys.stderr)
        return 1

    # ---- Closure ---------------------------------------------------------
    # real path -> install names that referenced it (used for rewriting later)
    closure: "OrderedDict[str, str]" = OrderedDict()
    queue: list[str] = [os.path.realpath(root_dylib)]
    licenses: set[str] = set()

    while queue:
        real = queue.pop(0)
        if real in closure:
            continue
        closure[real] = os.path.basename(real)
        licenses.add(real)
        for dep in otool_dependencies(real):
            if is_system(dep):
                continue
            resolved = resolve(dep, real, rpaths(real))
            if resolved is None:
                print(f"warning: unresolved dependency {dep} of {real}", file=sys.stderr)
                continue
            if is_system(resolved):
                continue
            if resolved not in closure:
                queue.append(resolved)

    basenames: dict[str, str] = {}
    for real, base in closure.items():
        if base in basenames and basenames[base] != real:
            print(f"error: two dylibs share the name {base}", file=sys.stderr)
            return 1
        basenames[base] = real

    # ---- Copy ------------------------------------------------------------
    if os.path.isdir(frameworks):
        shutil.rmtree(frameworks)
    os.makedirs(frameworks, exist_ok=True)

    for real, base in closure.items():
        destination = os.path.join(frameworks, base)
        shutil.copy2(real, destination)
        os.chmod(destination, 0o755)
        copy_license(real, resources)

    # ---- Rewrite install names ------------------------------------------
    bundled = {real: base for real, base in closure.items()}
    by_old_name: dict[str, str] = {}
    for real, base in closure.items():
        by_old_name[os.path.basename(real)] = base

    for real, base in closure.items():
        target = os.path.join(frameworks, base)
        run("install_name_tool", "-id", f"@rpath/{base}", target)

        for dep in otool_dependencies(target):
            if is_system(dep):
                continue
            resolved = resolve(dep, real, rpaths(real))
            if resolved is None or resolved not in bundled:
                continue
            new = f"@rpath/{bundled[resolved]}"
            if dep != new:
                run("install_name_tool", "-change", dep, new, target)

        # Sibling lookup: every dylib finds the others in its own directory.
        existing = rpaths(target)
        if "@loader_path" not in existing:
            run("install_name_tool", "-add_rpath", "@loader_path", target)
        # Drop absolute Homebrew rpaths so nothing can silently mix in a
        # second copy of a library at runtime.
        for rpath in rpaths(target):
            if rpath.startswith("/opt/homebrew") or rpath.startswith("/usr/local"):
                run("install_name_tool", "-delete_rpath", rpath, target)

        # install_name_tool invalidates the signature; re-sign inside-out.
        run("codesign", "--force", "--sign", "-", target)

    total = sum(
        os.path.getsize(os.path.join(frameworks, base)) for base in closure.values()
    )
    if not arguments.quiet:
        print(f"bundled {len(closure)} dylibs ({total / 1e6:.1f} MB) into {frameworks}")
        for base in sorted(closure.values()):
            print(f"  {base}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
