#!/usr/bin/env python3
"""Update the pinned Xray-core version and its SHA-256 checksums.

Used by .github/workflows/check-xray.yml. Single source of truth for the
version is xray.version; this script keeps Dockerfile, xray.version and
README.md in sync for a given release.

Usage:
  update-xray.py --version v26.12.1 --published 2026-12-01 \
    --amd64-sha <sha256 of Xray-linux-64.zip> \
    --arm64-sha <sha256 of Xray-linux-arm64-v8a.zip>
"""
import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--version", required=True, help="e.g. v26.12.1")
    p.add_argument("--published", required=True, help="e.g. 2026-12-01")
    p.add_argument("--amd64-sha", required=True)
    p.add_argument("--arm64-sha", required=True)
    args = p.parse_args()

    for sha, name in ((args.amd64_sha, "amd64"), (args.arm64_sha, "arm64")):
        if not re.fullmatch(r"[0-9a-f]{64}", sha):
            print(f"error: invalid {name} SHA-256: {sha}", file=sys.stderr)
            return 1

    # xray.version
    (ROOT / "xray.version").write_text(args.version + "\n", encoding="utf-8")

    # Dockerfile: ARG default + the two XRAY_SHA256 values, in order
    # (amd64 first, arm64 second, as written in the case statement).
    dockerfile = ROOT / "Dockerfile"
    text = dockerfile.read_text(encoding="utf-8")
    text, n = re.subn(
        r"^ARG XRAY_VERSION=v?[0-9.]+$",
        f"ARG XRAY_VERSION={args.version}",
        text,
        count=1,
        flags=re.MULTILINE,
    )
    if n != 1:
        print("error: ARG XRAY_VERSION line not found in Dockerfile", file=sys.stderr)
        return 1
    shas = iter([args.amd64_sha, args.arm64_sha])

    def _replace_sha(_m):
        return f'XRAY_SHA256="{next(shas)}"'

    text, n = re.subn(r'XRAY_SHA256="[0-9a-f]{64}"', _replace_sha, text, count=2)
    if n != 2:
        print(f"error: expected 2 SHA-256 lines in Dockerfile, found {n}", file=sys.stderr)
        return 1
    dockerfile.write_text(text, encoding="utf-8")

    # README.md: keep the version line in sync. Only the first
    # "Xray-core `v...`" occurrence is the version line.
    readme = ROOT / "README.md"
    if readme.exists():
        text = readme.read_text(encoding="utf-8")
        text, n = re.subn(
            r"Xray-core `v[0-9.]+`（[0-9-]+ 发布）",
            f"Xray-core `{args.version}`（{args.published} 发布）",
            text,
            count=1,
        )
        if n == 1:
            readme.write_text(text, encoding="utf-8")
        else:
            print("warning: README version line not found, skipping README update", file=sys.stderr)

    print(f"Updated Xray-core to {args.version} ({args.published})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
