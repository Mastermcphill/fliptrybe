#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import pathlib
import re
import shutil
import subprocess
import sys


def read_baseline(path: pathlib.Path) -> int:
    if not path.exists():
        raise ValueError(f"Baseline file not found: {path}")
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        try:
            return int(line)
        except ValueError as exc:
            raise ValueError(
                f"Invalid baseline value in {path}: {line!r}"
            ) from exc
    raise ValueError(f"No numeric baseline value found in {path}")


def parse_issue_count(output: str) -> int:
    summary = re.search(r"(\d+)\s+issues found\.", output)
    if summary:
        return int(summary.group(1))
    if "No issues found!" in output:
        return 0
    diagnostic_lines = re.findall(
        r"^\s*(info|warning|error)\s+-\s+",
        output,
        flags=re.MULTILINE,
    )
    if diagnostic_lines:
        return len(diagnostic_lines)
    raise ValueError("Unable to parse analyze issue count.")


def parse_error_count(output: str) -> int:
    return len(
        re.findall(
            r"^\s*error\s+-\s+",
            output,
            flags=re.MULTILINE,
        )
    )


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Run flutter analyze and fail if issue count exceeds configured "
            "baseline."
        )
    )
    parser.add_argument(
        "--baseline-file",
        default="tool/analyze_baseline.txt",
        help="Path to file containing the allowed issue-count baseline.",
    )
    parser.add_argument(
        "--baseline",
        type=int,
        default=None,
        help="Override baseline issue count directly.",
    )
    parser.add_argument(
        "--allow-analyzer-errors",
        action="store_true",
        help="Allow analyzer error diagnostics as long as count is <= baseline.",
    )
    args = parser.parse_args()

    baseline = (
        args.baseline
        if args.baseline is not None
        else read_baseline(pathlib.Path(args.baseline_file))
    )

    flutter_executable = (
        shutil.which("flutter")
        or shutil.which("flutter.bat")
        or ("flutter.bat" if os.name == "nt" else "flutter")
    )
    command = [flutter_executable, "analyze"]
    print(f"Running: {' '.join(command)}")
    process = subprocess.run(
        command,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )

    if process.stdout:
        print(process.stdout, end="")
    if process.stderr:
        print(process.stderr, file=sys.stderr, end="")

    combined_output = f"{process.stdout}\n{process.stderr}"
    if process.returncode not in (0, 1):
        print(
            f"Analyzer failed with unexpected exit code: {process.returncode}",
            file=sys.stderr,
        )
        return 2

    try:
        issue_count = parse_issue_count(combined_output)
    except ValueError as exc:
        print(str(exc), file=sys.stderr)
        return 2

    error_count = parse_error_count(combined_output)
    print(
        f"\nAnalyze issue count: {issue_count} | baseline: {baseline} | "
        f"errors: {error_count}"
    )

    if not args.allow_analyzer_errors and error_count > 0:
        print(
            "Analyzer reported one or more error diagnostics.",
            file=sys.stderr,
        )
        return 1

    if issue_count > baseline:
        print(
            "Analyzer issue count exceeded baseline "
            f"({issue_count} > {baseline}).",
            file=sys.stderr,
        )
        return 1

    print("Analyzer baseline guard passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
