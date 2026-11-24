"""Repository checks run by .github/workflows/validate.yml (and runnable locally).

1. Every JSON / Power BI project file (.json, .pbip, .pbir, .pbism) parses.
2. Files that must never be committed are absent (Power BI cache/local settings, private keys, .env).
3. No hard-coded secrets in scripts (passwords, storage keys, private-key blocks).
   Templated placeholders such as PASSWORD = '<% svc_password %>' are allowed.

Usage:  python scripts/validate_repo.py      (from the repo root; exit code 1 on any error)
"""
import json
import re
import subprocess
import sys
from pathlib import Path

JSON_SUFFIXES = {".json", ".pbip", ".pbir", ".pbism"}
FORBIDDEN_NAMES = {"cache.abf", "localSettings.json", ".env"}
FORBIDDEN_SUFFIXES = {".pem", ".p8", ".key", ".pfx"}
TEXT_SUFFIXES = {".sql", ".md", ".json", ".apex", ".py", ".yml", ".yaml", ".tmdl", ".ps1"}

SECRET_PATTERNS = [
    # PASSWORD = '...' unless the value is a template placeholder like '<% name %>' or '…'
    ("hard-coded password", re.compile(r"""(?i)\bpassword\s*=\s*'(?!<%)(?!…')(?!\.\.\.')[^'\s]{6,}'""")),
    ("storage account key", re.compile(r"AccountKey=[A-Za-z0-9+/=]{20,}")),
    ("private key block", re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----")),
    ("client secret value", re.compile(r"""(?i)"clientSecret"\s*:\s*"[^"<]{8,}""")),
]


def tracked_files() -> list[Path]:
    """Files git tracks (falls back to a directory walk outside a git checkout)."""
    try:
        out = subprocess.run(["git", "ls-files", "-z"], check=True, capture_output=True).stdout
        return [Path(p) for p in out.decode("utf-8").split("\0") if p]
    except (OSError, subprocess.CalledProcessError):
        return [p for p in Path(".").rglob("*") if p.is_file() and ".git" not in p.parts]


def main() -> int:
    files = tracked_files()
    errors: list[str] = []
    checked_json = 0

    for path in files:
        if path.name in FORBIDDEN_NAMES or path.suffix.lower() in FORBIDDEN_SUFFIXES:
            errors.append(f"{path}: must not be committed (local cache, settings or key file)")
            continue

        if path.suffix.lower() in JSON_SUFFIXES:
            checked_json += 1
            try:
                json.loads(path.read_text(encoding="utf-8-sig"))
            except (ValueError, UnicodeDecodeError) as exc:
                errors.append(f"{path}: invalid JSON ({exc})")

        if path.suffix.lower() in TEXT_SUFFIXES and path.name != "validate_repo.py":
            try:
                lines = path.read_text(encoding="utf-8-sig").splitlines()
            except UnicodeDecodeError:
                continue
            for lineno, line in enumerate(lines, 1):
                for label, pattern in SECRET_PATTERNS:
                    if pattern.search(line):
                        errors.append(f"{path}:{lineno}: possible {label}")

    print(f"Checked {len(files)} tracked files ({checked_json} JSON / Power BI project files).")
    if errors:
        print(f"FAILED with {len(errors)} problem(s):")
        for err in errors:
            print(f"  - {err}")
        return 1
    print("All repository checks passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
