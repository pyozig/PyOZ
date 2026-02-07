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
import io
import os
import platform as plat
import re
import shutil
import subprocess
import sys
import tarfile
import urllib.request
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


# CPython version to download headers from (abi3 headers are forward-compatible)
CPYTHON_VERSION = "3.13.1"
CPYTHON_URL = (
    f"https://www.python.org/ftp/python/{CPYTHON_VERSION}/Python-{CPYTHON_VERSION}.tgz"
)


def _generate_python3_def(headers_dir, toml_content):
    """Generate python3.def from stable_abi.toml for Windows import library.

    The .def file lists all symbols exported by python3.dll (the Stable ABI DLL).
    This is used by `zig dlltool` to generate python3.lib for cross-compilation.
    """
    try:
        import tomllib
    except ImportError:
        try:
            import tomli as tomllib
        except ImportError:
            print(
                "  Warning: no TOML parser available, skipping python3.def generation"
            )
            return

    data = tomllib.loads(toml_content)
    functions = []
    datas = []

    for category, entries in data.items():
        if not isinstance(entries, dict):
            continue
        for name, info in entries.items():
            if not isinstance(info, dict):
                continue
            if category == "function":
                functions.append(name)
            elif category == "data":
                datas.append(name)

    def_path = os.path.join(headers_dir, "windows", "python3.def")
    with open(def_path, "w") as f:
        f.write("LIBRARY python3\n")
        f.write("EXPORTS\n")
        for name in sorted(functions):
            f.write(f"    {name}\n")
        for name in sorted(datas):
            f.write(f"    {name} DATA\n")

    print(
        f"  Generated python3.def ({len(functions)} functions, {len(datas)} data symbols)"
    )


def ensure_python_headers(headers_dir):
    """Download CPython headers for cross-compilation if not already cached.

    Downloads the CPython source tarball and extracts:
    - Include/*.h and Include/cpython/*.h → headers_dir/ (platform-independent)
    - PC/pyconfig.h → headers_dir/windows/pyconfig.h (Windows-specific)
    - Host pyconfig.h → headers_dir/unix/pyconfig.h (for Linux/macOS cross-targets)
    """
    marker = os.path.join(headers_dir, ".cpython-version")
    if os.path.exists(marker):
        with open(marker) as f:
            if f.read().strip() == CPYTHON_VERSION:
                print(
                    f"  Using cached CPython {CPYTHON_VERSION} headers in {headers_dir}"
                )
                return

    print(f"  Downloading CPython {CPYTHON_VERSION} headers...")

    # Clean previous headers
    if os.path.exists(headers_dir):
        shutil.rmtree(headers_dir)

    os.makedirs(headers_dir, exist_ok=True)
    os.makedirs(os.path.join(headers_dir, "windows"), exist_ok=True)
    os.makedirs(os.path.join(headers_dir, "unix"), exist_ok=True)

    # Download and extract
    resp = urllib.request.urlopen(CPYTHON_URL)
    data = resp.read()
    print(f"  Downloaded {len(data) // (1024 * 1024)}MB")

    prefix = f"Python-{CPYTHON_VERSION}/"
    include_prefix = prefix + "Include/"
    # Windows pyconfig.h is named pyconfig.h.in in the source tree but is a
    # complete, manually-maintained header (no @VARIABLE@ substitution needed)
    pc_pyconfig = prefix + "PC/pyconfig.h.in"
    stable_abi_toml = prefix + "Misc/stable_abi.toml"

    with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as tar:
        for member in tar.getmembers():
            if not member.isfile():
                continue

            # Extract Include/ headers (platform-independent)
            if member.name.startswith(include_prefix):
                rel = member.name[len(include_prefix) :]
                if not rel:
                    continue
                dest = os.path.join(headers_dir, rel)
                os.makedirs(os.path.dirname(dest), exist_ok=True)
                src = tar.extractfile(member)
                if src is not None:
                    with open(dest, "wb") as dst:
                        dst.write(src.read())
                    src.close()

            # Extract PC/pyconfig.h for Windows
            elif member.name == pc_pyconfig:
                dest = os.path.join(headers_dir, "windows", "pyconfig.h")
                src = tar.extractfile(member)
                if src is not None:
                    with open(dest, "wb") as dst:
                        dst.write(src.read())
                    src.close()

            # Extract stable_abi.toml for generating python3.def
            elif member.name == stable_abi_toml:
                src = tar.extractfile(member)
                if src is not None:
                    toml_content = src.read().decode()
                    src.close()
                    _generate_python3_def(headers_dir, toml_content)

    # Copy host pyconfig.h for Unix cross-targets (Linux→macOS works because
    # both are LP64 with identical SIZEOF_* values: SIZEOF_LONG=8, SIZEOF_WCHAR_T=4)
    host_pyconfig = _find_host_pyconfig()
    if host_pyconfig:
        shutil.copy2(host_pyconfig, os.path.join(headers_dir, "unix", "pyconfig.h"))
        print(f"  Copied host pyconfig.h from {host_pyconfig}")
    else:
        print("  Warning: could not find host pyconfig.h for Unix cross-targets")

    # Write version marker for caching
    with open(marker, "w") as f:
        f.write(CPYTHON_VERSION)

    header_count = sum(
        1 for _, _, files in os.walk(headers_dir) for f in files if f.endswith(".h")
    )
    print(f"  Extracted {header_count} headers to {headers_dir}")


def _find_host_pyconfig():
    """Find the host Python's real pyconfig.h (not the multiarch dispatch stub).

    On Debian/Ubuntu, /usr/include/python3.X/pyconfig.h is a multiarch stub
    that dispatches via #ifdef __linux__ / __x86_64__ etc. We need the actual
    platform-specific pyconfig.h (e.g. /usr/include/x86_64-linux-gnu/python3.X/)
    which contains the real SIZEOF_* defines.
    """
    # First try: sysconfig platinclude (gives the real arch-specific path)
    try:
        result = subprocess.run(
            [
                "python3",
                "-c",
                "import sysconfig; print(sysconfig.get_path('platinclude'))",
            ],
            capture_output=True,
            text=True,
            check=True,
        )
        platinclude = result.stdout.strip()
        pyconfig = os.path.join(platinclude, "pyconfig.h")
        if os.path.isfile(pyconfig):
            # Verify it's the real pyconfig.h, not a multiarch stub
            with open(pyconfig) as f:
                content = f.read()
            if "unknown multiarch location" not in content:
                return pyconfig
    except (subprocess.CalledProcessError, FileNotFoundError):
        pass
    # Fallback: try multiarch-specific locations (Debian/Ubuntu layout)
    import struct

    arch = "x86_64" if struct.calcsize("P") == 8 else "i386"
    for ver in ["3.13", "3.12", "3.11", "3.10"]:
        path = f"/usr/include/{arch}-linux-gnu/python{ver}/pyconfig.h"
        if os.path.isfile(path):
            return path
    return None


def stage_pyconfig(headers_dir, zig_target):
    """Copy the correct platform-specific pyconfig.h into the headers directory.

    Python.h does #include "pyconfig.h" with quotes, so it must be in the
    same directory as Python.h for the compiler to find it.
    """
    if "windows" in zig_target:
        src = os.path.join(headers_dir, "windows", "pyconfig.h")
    else:
        src = os.path.join(headers_dir, "unix", "pyconfig.h")

    dst = os.path.join(headers_dir, "pyconfig.h")
    if os.path.isfile(src):
        shutil.copy2(src, dst)
    else:
        print(f"  Warning: pyconfig.h not found at {src}")


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


def zig_build(target=None, release=True, python_headers_dir=None):
    """Run zig build in the pypi/ directory, optionally cross-compiling."""
    pypi_dir = os.path.dirname(os.path.abspath(__file__))
    cmd = ["zig", "build"]
    if release:
        cmd.append("-Doptimize=ReleaseFast")
    if target:
        cmd.extend([f"-Dtarget={target}"])
    if python_headers_dir:
        cmd.append(f"-Dpython-headers-dir={python_headers_dir}")
    print(f"  Building: {' '.join(cmd)}")
    result = subprocess.run(cmd, cwd=pypi_dir)
    if result.returncode != 0:
        print(f"  Error: zig build failed for target {target or 'native'}")
        return False
    return True


def find_extension(ext=".so"):
    """Find the built _pyoz extension in zig-out/lib/ or zig-out/bin/ (Windows)."""
    pypi_dir = os.path.dirname(os.path.abspath(__file__))
    # Zig puts shared libraries in lib/ on Unix but DLLs in bin/ on Windows
    for subdir in ("lib", "bin"):
        path = os.path.join(pypi_dir, "zig-out", subdir, f"_pyoz{ext}")
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

    # Download bundled CPython headers for all targets (Zig's sysroot doesn't
    # include the host Python's multiarch headers, so we always need these)
    pypi_dir = os.path.dirname(os.path.abspath(__file__))
    headers_dir = os.path.join(pypi_dir, "python-headers")
    if not args.current_only and not args.no_build:
        ensure_python_headers(headers_dir)
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
                stage_pyconfig(headers_dir, zig_target)
                if not zig_build(
                    target=zig_target,
                    release=True,
                    python_headers_dir=headers_dir,
                ):
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
