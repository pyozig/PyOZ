"""PyOZ - Python extension modules in Zig, made easy."""

import os
import platform
import subprocess
import sys


def _get_binary_path():
    """Find the pyoz binary for the current platform."""
    system = platform.system().lower()
    machine = platform.machine().lower()

    # Normalize machine names
    if machine in ("x86_64", "amd64"):
        machine = "x86_64"
    elif machine in ("aarch64", "arm64"):
        machine = "aarch64"

    if system == "windows":
        name = f"pyoz-{machine}-windows.exe"
    elif system == "darwin":
        name = f"pyoz-{machine}-macos"
    else:
        name = f"pyoz-{machine}-linux"

    bin_dir = os.path.join(os.path.dirname(__file__), "bin")
    path = os.path.join(bin_dir, name)

    if not os.path.isfile(path):
        raise FileNotFoundError(
            f"PyOZ binary not found for {system} {machine}. Expected: {path}"
        )

    return path


def main():
    """Entry point for the pyoz CLI."""
    binary = _get_binary_path()

    # Ensure the binary is executable (pip doesn't always preserve permissions from wheels)
    if not os.access(binary, os.X_OK):
        os.chmod(binary, os.stat(binary).st_mode | 0o755)

    sys.exit(subprocess.call([binary] + sys.argv[1:]))
