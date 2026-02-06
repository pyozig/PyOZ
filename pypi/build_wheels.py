#!/usr/bin/env python3
"""Build platform-specific wheels for the PyOZ native Python extension.

Usage:
    # Build wheel for current platform (requires: cd pypi && zig build)
    python build_wheels.py --current-only

    # Build wheels for all platforms (cross-compile)
    python build_wheels.py

The extension is built with 'zig build' in the pypi/ directory, producing
a _pyoz.so/.pyd native module that exposes the CLI as a Python library.
"""

import argparse
import hashlib
import os
import platform as plat
import re
import subprocess
import sys
import zipfile

# Map from (os, arch) to (zig target, wheel platform tag, extension)
TARGETS = [
    ("x86_64-linux-gnu", "manylinux2014_x86_64", ".so"),
    ("aarch64-linux-gnu", "manylinux2014_aarch64", ".so"),
    ("x86_64-macos", "macosx_11_0_x86_64", ".so"),
    ("aarch64-macos", "macosx_11_0_arm64", ".so"),
    ("x86_64-windows", "win_amd64", ".pyd"),
    ("aarch64-windows", "win_arm64", ".pyd"),
]


def get_version():
    """Read version from pyproject.toml."""
    pyproject = os.path.join(os.path.dirname(__file__), "pyproject.toml")
    with open(pyproject) as f:
        for line in f:
            m = re.match(r'^version\s*=\s*"(.+)"', line)
            if m:
                return m.group(1)
    raise RuntimeError("Could not find version in pyproject.toml")


def sha256_digest(data):
    """Compute SHA256 digest in urlsafe base64 (no padding)."""
    import base64

    h = hashlib.sha256(data).digest()
    return base64.urlsafe_b64encode(h).rstrip(b"=").decode("ascii")


def read_readme():
    """Read the README.md file for inclusion in wheel metadata."""
    readme_path = os.path.join(os.path.dirname(__file__), "README.md")
    with open(readme_path, "r") as f:
        return f.read()


def zig_build(target=None, release=True):
    """Run zig build in the pypi/ directory, optionally cross-compiling."""
    pypi_dir = os.path.dirname(os.path.abspath(__file__))
    cmd = ["zig", "build"]
    if release:
        cmd.append("-Doptimize=ReleaseFast")
    if target:
        cmd.extend([f"-Dtarget={target}"])
    print(f"  Building: {' '.join(cmd)}")
    result = subprocess.run(cmd, cwd=pypi_dir)
    if result.returncode != 0:
        print(f"  Error: zig build failed for target {target or 'native'}")
        return False
    return True


def find_extension(ext=".so"):
    """Find the built _pyoz extension in zig-out/lib/."""
    pypi_dir = os.path.dirname(os.path.abspath(__file__))
    path = os.path.join(pypi_dir, "zig-out", "lib", f"_pyoz{ext}")
    if os.path.isfile(path):
        return path
    return None


def build_wheel(extension_path, ext, platform_tag, version, dist_dir):
    """Build a single platform-specific wheel containing the native extension.

    Uses abi3 (Python Stable ABI) tags: cp38-abi3-{platform}
    This means a single wheel works for Python 3.8, 3.9, 3.10, 3.11, 3.12, 3.13+
    """
    wheel_name = f"pyoz-{version}-cp38-abi3-{platform_tag}.whl"
    wheel_path = os.path.join(dist_dir, wheel_name)

    dist_info = f"pyoz-{version}.dist-info"
    readme_content = read_readme()
    pypi_dir = os.path.dirname(os.path.abspath(__file__))

    with zipfile.ZipFile(wheel_path, "w", zipfile.ZIP_DEFLATED) as whl:
        # Add pyoz/__init__.py
        init_path = os.path.join(pypi_dir, "pyoz", "__init__.py")
        with open(init_path, "rb") as f:
            whl.writestr("pyoz/__init__.py", f.read())

        # Add pyoz/__main__.py
        main_path = os.path.join(pypi_dir, "pyoz", "__main__.py")
        with open(main_path, "rb") as f:
            whl.writestr("pyoz/__main__.py", f.read())

        # Add the native extension module
        with open(extension_path, "rb") as f:
            ext_data = f.read()
        ext_target = f"_pyoz{ext}"
        info = zipfile.ZipInfo(ext_target)
        info.external_attr = 0o755 << 16
        info.compress_type = zipfile.ZIP_DEFLATED
        whl.writestr(info, ext_data)

        # METADATA
        metadata = f"""Metadata-Version: 2.1
Name: pyoz
Version: {version}
Summary: Python extension modules in Zig, made easy
Home-page: https://pyoz.dev
Author: Daniele Linguaglossa
License: MIT
Requires-Python: >=3.8
Classifier: Development Status :: 4 - Beta
Classifier: Intended Audience :: Developers
Classifier: License :: OSI Approved :: MIT License
Classifier: Programming Language :: Python :: 3
Classifier: Topic :: Software Development :: Build Tools
Project-URL: Documentation, https://pyoz.dev
Project-URL: Source, https://github.com/pyozig/PyOZ
Project-URL: Changelog, https://pyoz.dev/changelog
Description-Content-Type: text/markdown

{readme_content}"""
        whl.writestr(f"{dist_info}/METADATA", metadata)

        # WHEEL
        wheel_meta = f"""Wheel-Version: 1.0
Generator: pyoz-build
Root-Is-Purelib: false
Tag: cp38-abi3-{platform_tag}
"""
        whl.writestr(f"{dist_info}/WHEEL", wheel_meta)

        # entry_points.txt
        entry_points = """[console_scripts]
pyoz = pyoz:main
"""
        whl.writestr(f"{dist_info}/entry_points.txt", entry_points)

        # top_level.txt
        whl.writestr(f"{dist_info}/top_level.txt", "pyoz\n_pyoz\n")

        # RECORD (must be last, lists all files with hashes)
        record_lines = []
        for item in whl.namelist():
            data = whl.read(item)
            digest = sha256_digest(data)
            size = len(data)
            record_lines.append(f"{item},sha256={digest},{size}")
        record_lines.append(f"{dist_info}/RECORD,,")
        whl.writestr(f"{dist_info}/RECORD", "\n".join(record_lines) + "\n")

    print(f"  Built: {wheel_name}")
    return wheel_path


def get_current_platform_info():
    """Get zig target, platform tag, and extension for the current platform."""
    system = plat.system().lower()
    machine = plat.machine().lower()

    if machine in ("x86_64", "amd64"):
        machine = "x86_64"
    elif machine in ("aarch64", "arm64"):
        machine = "aarch64"

    if system == "windows":
        return (
            f"{machine}-windows",
            f"win_{'amd64' if machine == 'x86_64' else 'arm64'}",
            ".pyd",
        )
    elif system == "darwin":
        return (
            f"{machine}-macos",
            f"macosx_11_0_{'x86_64' if machine == 'x86_64' else 'arm64'}",
            ".so",
        )
    else:
        return f"{machine}-linux-gnu", f"manylinux2014_{machine}", ".so"


def main():
    parser = argparse.ArgumentParser(description="Build PyOZ wheels")
    parser.add_argument(
        "--current-only",
        action="store_true",
        help="Build wheel for current platform only",
    )
    parser.add_argument(
        "--no-build",
        action="store_true",
        help="Skip zig build, use existing extension in zig-out/lib/",
    )
    parser.add_argument(
        "--dist-dir",
        default=os.path.join(os.path.dirname(__file__), "dist"),
        help="Output directory for wheels",
    )
    args = parser.parse_args()

    version = get_version()
    dist_dir = args.dist_dir
    os.makedirs(dist_dir, exist_ok=True)

    print(f"Building PyOZ v{version} wheels")
    print(f"Output: {dist_dir}")
    print()

    wheels_built = 0

    if args.current_only:
        zig_target, platform_tag, ext = get_current_platform_info()

        if not args.no_build:
            if not zig_build(release=True):
                sys.exit(1)

        extension_path = find_extension(ext)
        if not extension_path:
            print(f"Error: Extension not found at zig-out/lib/_pyoz{ext}")
            print("Run 'cd pypi && zig build -Doptimize=ReleaseFast' first.")
            sys.exit(1)

        build_wheel(extension_path, ext, platform_tag, version, dist_dir)
        wheels_built += 1
    else:
        for zig_target, platform_tag, ext in TARGETS:
            if not args.no_build:
                if not zig_build(target=zig_target, release=True):
                    print(f"  Skipping {zig_target} (build failed)")
                    continue

            extension_path = find_extension(ext)
            if not extension_path:
                print(f"  Skipping {zig_target} (extension not found)")
                continue

            build_wheel(extension_path, ext, platform_tag, version, dist_dir)
            wheels_built += 1

    print()
    print(f"Done! Built {wheels_built} wheel(s) in {dist_dir}")


if __name__ == "__main__":
    main()
