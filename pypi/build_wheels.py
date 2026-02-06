#!/usr/bin/env python3
"""Build platform-specific wheels for the PyOZ CLI.

Usage:
    # Build wheels for all platforms (requires zig build release to have run first)
    python build_wheels.py

    # Build wheel for current platform only
    python build_wheels.py --current-only

The script expects pre-built binaries in ../zig-out/release/ (from zig build release)
or ../zig-out/bin/pyoz for current-platform-only builds.
"""

import argparse
import hashlib
import os
import re
import sys
import zipfile

# Map from zig target naming to wheel platform tags
PLATFORM_MAP = {
    "pyoz-x86_64-linux": "manylinux2014_x86_64",
    "pyoz-aarch64-linux": "manylinux2014_aarch64",
    "pyoz-x86_64-macos": "macosx_11_0_x86_64",
    "pyoz-aarch64-macos": "macosx_11_0_arm64",
    "pyoz-x86_64-windows.exe": "win_amd64",
    "pyoz-aarch64-windows.exe": "win_arm64",
}


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


def build_wheel(binary_path, binary_name, platform_tag, version, dist_dir):
    """Build a single platform-specific wheel."""
    wheel_name = f"pyoz-{version}-py3-none-{platform_tag}.whl"
    wheel_path = os.path.join(dist_dir, wheel_name)

    dist_info = f"pyoz-{version}.dist-info"

    with zipfile.ZipFile(wheel_path, "w", zipfile.ZIP_DEFLATED) as whl:
        # Add __init__.py
        init_path = os.path.join(os.path.dirname(__file__), "pyoz", "__init__.py")
        with open(init_path, "rb") as f:
            init_data = f.read()
        whl.writestr("pyoz/__init__.py", init_data)

        # Add __main__.py
        main_path = os.path.join(os.path.dirname(__file__), "pyoz", "__main__.py")
        with open(main_path, "rb") as f:
            main_data = f.read()
        whl.writestr("pyoz/__main__.py", main_data)

        # Add the binary
        with open(binary_path, "rb") as f:
            binary_data = f.read()
        bin_target = f"pyoz/bin/{binary_name}"
        info = zipfile.ZipInfo(bin_target)
        # Set executable permission
        info.external_attr = 0o755 << 16
        info.compress_type = zipfile.ZIP_DEFLATED
        whl.writestr(info, binary_data)

        # METADATA
        metadata = f"""Metadata-Version: 2.1
Name: pyoz
Version: {version}
Summary: Python extension modules in Zig, made easy
Home-page: https://github.com/pyozig/PyOZ
Author: Daniele Linguaglossa
License: MIT
Requires-Python: >=3.8
Classifier: Development Status :: 4 - Beta
Classifier: Intended Audience :: Developers
Classifier: License :: OSI Approved :: MIT License
Classifier: Programming Language :: Python :: 3
Classifier: Topic :: Software Development :: Build Tools
"""
        whl.writestr(f"{dist_info}/METADATA", metadata)

        # WHEEL
        wheel_meta = f"""Wheel-Version: 1.0
Generator: pyoz-build
Root-Is-Purelib: false
Tag: py3-none-{platform_tag}
"""
        whl.writestr(f"{dist_info}/WHEEL", wheel_meta)

        # entry_points.txt
        entry_points = """[console_scripts]
pyoz = pyoz:main
"""
        whl.writestr(f"{dist_info}/entry_points.txt", entry_points)

        # top_level.txt
        whl.writestr(f"{dist_info}/top_level.txt", "pyoz\n")

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


def main():
    parser = argparse.ArgumentParser(description="Build PyOZ wheels")
    parser.add_argument(
        "--current-only",
        action="store_true",
        help="Build wheel for current platform only",
    )
    parser.add_argument(
        "--dist-dir",
        default=os.path.join(os.path.dirname(__file__), "dist"),
        help="Output directory for wheels",
    )
    args = parser.parse_args()

    version = get_version()
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    release_dir = os.path.join(repo_root, "zig-out", "release")
    dist_dir = args.dist_dir

    os.makedirs(dist_dir, exist_ok=True)

    print(f"Building PyOZ v{version} wheels")
    print(f"Output: {dist_dir}")
    print()

    wheels_built = 0

    if args.current_only:
        # Use the binary from zig-out/bin/
        import platform as plat

        system = plat.system().lower()
        machine = plat.machine().lower()

        if machine in ("x86_64", "amd64"):
            machine = "x86_64"
        elif machine in ("aarch64", "arm64"):
            machine = "aarch64"

        if system == "windows":
            binary_name = f"pyoz-{machine}-windows.exe"
            bin_path = os.path.join(repo_root, "zig-out", "bin", "pyoz.exe")
        elif system == "darwin":
            binary_name = f"pyoz-{machine}-macos"
            bin_path = os.path.join(repo_root, "zig-out", "bin", "pyoz")
        else:
            binary_name = f"pyoz-{machine}-linux"
            bin_path = os.path.join(repo_root, "zig-out", "bin", "pyoz")

        if not os.path.isfile(bin_path):
            print(f"Error: Binary not found at {bin_path}")
            print("Run 'zig build cli' first.")
            sys.exit(1)

        platform_tag = PLATFORM_MAP.get(binary_name)
        if not platform_tag:
            # Fallback for musl linux
            platform_tag = f"linux_{machine}"

        build_wheel(bin_path, binary_name, platform_tag, version, dist_dir)
        wheels_built += 1
    else:
        # Build wheels for all platforms from zig-out/release/
        if not os.path.isdir(release_dir):
            print(f"Error: Release directory not found at {release_dir}")
            print("Run 'zig build release' first.")
            sys.exit(1)

        for binary_name, platform_tag in PLATFORM_MAP.items():
            binary_path = os.path.join(release_dir, binary_name)
            if not os.path.isfile(binary_path):
                print(f"  Skipping {binary_name} (not found)")
                continue

            build_wheel(binary_path, binary_name, platform_tag, version, dist_dir)
            wheels_built += 1

    print()
    print(f"Done! Built {wheels_built} wheel(s) in {dist_dir}")


if __name__ == "__main__":
    main()
