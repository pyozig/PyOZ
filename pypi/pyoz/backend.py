"""PEP 517 build backend for PyOZ projects.

This module implements the PEP 517 build backend interface so that
``pip install .`` works for projects using PyOZ. Set the following
in your ``pyproject.toml``:

.. code-block:: toml

    [build-system]
    requires = ["pyoz"]
    build-backend = "pyoz.backend"
"""

import os
import re
import shutil
import tarfile


def get_requires_for_build_wheel(config_settings=None):
    return []


def get_requires_for_build_sdist(config_settings=None):
    return []


def build_wheel(wheel_directory, config_settings=None, metadata_directory=None):
    from _pyoz import build

    release = True
    stubs = True
    if config_settings:
        release = config_settings.get("--release", "true").lower() != "false"
        stubs = config_settings.get("--stubs", "true").lower() != "false"

    wheel_path = build(release, stubs)
    filename = os.path.basename(wheel_path)
    dest = os.path.join(wheel_directory, filename)
    shutil.copy2(wheel_path, dest)
    return filename


def build_sdist(sdist_directory, config_settings=None):
    name = _get_project_field("name")
    version = _get_project_field("version")
    sdist_name = f"{name}-{version}"
    sdist_filename = f"{sdist_name}.tar.gz"
    sdist_path = os.path.join(sdist_directory, sdist_filename)

    with tarfile.open(sdist_path, "w:gz") as tar:
        for path in ["pyproject.toml", "build.zig", "build.zig.zon", "src"]:
            if os.path.exists(path):
                tar.add(path, arcname=os.path.join(sdist_name, path))
    return sdist_filename


def _get_project_field(field):
    try:
        with open("pyproject.toml") as f:
            for line in f:
                m = re.match(rf'^{field}\s*=\s*"(.+)"', line)
                if m:
                    return m.group(1)
    except FileNotFoundError:
        pass
    return "unknown" if field == "name" else "0.0.0"
