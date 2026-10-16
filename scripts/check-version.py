#!/usr/bin/env python3
"""Validate the release version and optionally require a bump over a Git base."""

import argparse
import plistlib
import re
import subprocess
import sys
from pathlib import Path


def read_version(data):
    version = plistlib.loads(data)["CFBundleShortVersionString"]
    if not isinstance(version, str) or not re.fullmatch(
        r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)", version
    ):
        raise ValueError(f"Invalid CFBundleShortVersionString: {version!r}; expected X.Y.Z")
    return version


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", help="Git commit containing the previous version")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    version = read_version((root / "Resources/Info.plist").read_bytes())
    if args.base:
        previous = read_version(subprocess.check_output(
            ["git", "show", f"{args.base}:Resources/Info.plist"], cwd=root
        ))
        if tuple(map(int, version.split("."))) <= tuple(map(int, previous.split("."))):
            raise ValueError(
                f"Release version {version} must be greater than PR base {previous}. "
                "Update CFBundleShortVersionString in Resources/Info.plist."
            )
    print(version)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, subprocess.CalledProcessError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
