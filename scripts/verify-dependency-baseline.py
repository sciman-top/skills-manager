#!/usr/bin/env python3
"""
Verify target-repository dependency baseline metadata.

This validator checks that a target repo carries a baseline manifest at:
  .governed-ai/dependency-baseline.json

It intentionally validates baseline contract metadata only.
Actual dependency vulnerability scanning is expected to run in separate tooling.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import sys
from pathlib import Path
from typing import Any


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Verify dependency baseline contract metadata.")
    parser.add_argument(
        "--target-repo-root",
        required=True,
        help="Path to the target repository root.",
    )
    parser.add_argument(
        "--baseline-relpath",
        default=".governed-ai/dependency-baseline.json",
        help="Baseline file relative path under target repo root.",
    )
    parser.add_argument(
        "--require-target-repo-baseline",
        action="store_true",
        help="Fail when the baseline file is missing.",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Print machine-readable summary JSON.",
    )
    return parser.parse_args()


def _parse_iso8601(value: str) -> dt.datetime:
    text = value.strip()
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    return dt.datetime.fromisoformat(text)


def _emit(args: argparse.Namespace, payload: dict[str, Any]) -> None:
    if args.json:
        print(json.dumps(payload, ensure_ascii=False, indent=2))
        return
    if payload.get("ok"):
        print(payload.get("message", "dependency baseline verification passed"))
        return
    print(payload.get("message", "dependency baseline verification failed"), file=sys.stderr)
    for item in payload.get("errors", []):
        print(f"- {item}", file=sys.stderr)


def verify(args: argparse.Namespace) -> int:
    repo_root = Path(args.target_repo_root).resolve()
    baseline_path = repo_root / args.baseline_relpath

    if not baseline_path.exists():
        if args.require_target_repo_baseline:
            _emit(
                args,
                {
                    "ok": False,
                    "message": f"dependency baseline missing: {baseline_path}",
                    "errors": ["required baseline file was not found"],
                    "target_repo_root": str(repo_root),
                    "baseline_path": str(baseline_path),
                },
            )
            return 2
        _emit(
            args,
            {
                "ok": True,
                "message": f"dependency baseline not found, skipped: {baseline_path}",
                "target_repo_root": str(repo_root),
                "baseline_path": str(baseline_path),
                "skipped": True,
            },
        )
        return 0

    try:
        raw = baseline_path.read_text(encoding="utf-8")
    except OSError as exc:
        _emit(
            args,
            {
                "ok": False,
                "message": "failed to read dependency baseline file",
                "errors": [str(exc)],
                "target_repo_root": str(repo_root),
                "baseline_path": str(baseline_path),
            },
        )
        return 1

    try:
        data = json.loads(raw)
    except json.JSONDecodeError as exc:
        _emit(
            args,
            {
                "ok": False,
                "message": "dependency baseline is not valid JSON",
                "errors": [str(exc)],
                "target_repo_root": str(repo_root),
                "baseline_path": str(baseline_path),
            },
        )
        return 1

    if not isinstance(data, dict):
        _emit(
            args,
            {
                "ok": False,
                "message": "dependency baseline must be a JSON object",
                "errors": [f"unexpected root type: {type(data).__name__}"],
                "target_repo_root": str(repo_root),
                "baseline_path": str(baseline_path),
            },
        )
        return 1

    errors: list[str] = []

    required_fields = [
        "baseline_kind",
        "generated_at",
        "owner_runtime",
        "repo_id",
        "schema_version",
        "verify_command",
    ]
    for field in required_fields:
        value = data.get(field)
        if value is None or str(value).strip() == "":
            errors.append(f"missing required field: {field}")

    kind = str(data.get("baseline_kind", "")).strip()
    if kind and kind != "target_repo_dependency_baseline":
        errors.append(
            "baseline_kind must be target_repo_dependency_baseline "
            f"(actual: {kind})"
        )

    generated_at = str(data.get("generated_at", "")).strip()
    if generated_at:
        try:
            _parse_iso8601(generated_at)
        except ValueError:
            errors.append(f"generated_at is not ISO-8601: {generated_at}")

    verify_command = str(data.get("verify_command", "")).strip()
    if verify_command:
        if "scripts/verify-dependency-baseline.py" not in verify_command:
            errors.append(
                "verify_command must reference scripts/verify-dependency-baseline.py"
            )
        if "<target-repo-root>" not in verify_command:
            errors.append(
                "verify_command should include <target-repo-root> placeholder"
            )

    repo_id = str(data.get("repo_id", "")).strip()
    expected_repo_id = repo_root.name.strip()
    if repo_id and expected_repo_id and repo_id != expected_repo_id:
        errors.append(
            f"repo_id mismatch: baseline={repo_id}, expected={expected_repo_id}"
        )

    if errors:
        _emit(
            args,
            {
                "ok": False,
                "message": "dependency baseline verification failed",
                "errors": errors,
                "target_repo_root": str(repo_root),
                "baseline_path": str(baseline_path),
            },
        )
        return 1

    _emit(
        args,
        {
            "ok": True,
            "message": f"dependency baseline verified: {baseline_path}",
            "target_repo_root": str(repo_root),
            "baseline_path": str(baseline_path),
            "repo_id": repo_id,
            "generated_at": generated_at,
            "schema_version": str(data.get("schema_version", "")).strip(),
        },
    )
    return 0


def main() -> int:
    args = parse_args()
    return verify(args)


if __name__ == "__main__":
    raise SystemExit(main())
