#!/usr/bin/env python3
"""Одна локальная приёмка до коммита; без Studio, публикации и сетевых запросов."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]


def fingerprint(root):
    """Изменение проверяемого кода во время прогона делает результат устаревшим."""
    files = []
    for folder in ("src", "tests", "tools"):
        files.extend(p for p in (root / folder).rglob("*")
                     if p.is_file() and p.suffix in (".luau", ".lua", ".py", ".swift")
                     and "__pycache__" not in p.parts)
    for name in ("default.project.json", "foreman.toml", ".luaurc", "localization/en-ru.csv"):
        path = root / name
        if path.is_file():
            files.append(path)
    digest = hashlib.sha256()
    for path in sorted(files):
        digest.update(path.relative_to(root).as_posix().encode() + b"\0")
        digest.update(hashlib.sha256(path.read_bytes()).digest())
    return {"sha256": digest.hexdigest(), "files": len(files)}


def git_command(root):
    if (root / ".git-codex").is_dir():
        return ["git", "--git-dir=.git-codex", "--work-tree=."]
    return ["git"]


def plan(root, output):
    return [
        ("localization", ["lune", "run", "tools/export-localization", "--check"]),
        ("luau", ["lune", "run", "tests/run"]),
        ("python", [sys.executable, "-m", "unittest", "discover", "-s", "tests", "-p", "test_*.py"]),
        ("build", ["rojo", "build", "-o", str(output / "game.rbxlx")]),
        ("whitespace", git_command(root) + ["diff", "HEAD", "--check"]),
    ]


def run_checks(root, output, timeout=180, runner=subprocess.run):
    report = {"formatVersion": 1, "startedAt": datetime.now(timezone.utc).isoformat(),
              "root": str(root), "ok": False, "checks": [],
              "studioChecked": False, "published": False}
    try:
        report["inputsBefore"] = fingerprint(root)
        revision = runner(git_command(root) + ["rev-parse", "HEAD"], cwd=root,
                          capture_output=True, text=True, timeout=10, check=True)
        report["commit"] = revision.stdout.strip()
        for name, command in plan(root, output):
            started = time.monotonic()
            log_path = output / (name + ".log")
            step = {"name": name, "command": command, "log": str(log_path)}
            report["checks"].append(step)
            with log_path.open("wb") as log:
                try:
                    result = runner(command, cwd=root, stdout=log, stderr=subprocess.STDOUT,
                                    timeout=timeout, check=False)
                    step["exitCode"] = result.returncode
                except (OSError, subprocess.TimeoutExpired) as error:
                    step["error"] = str(error)
                    log.write((str(error) + "\n").encode())
                    step["exitCode"] = 1
            step["seconds"] = round(time.monotonic() - started, 3)
            print(f'{name}: {"OK" if step["exitCode"] == 0 else "FAIL"}', flush=True)
            if step["exitCode"] != 0:
                report["error"] = f"Проверка {name} не прошла. Подробности: {log_path}"
                break
        else:
            artifact = output / "game.rbxlx"
            if not artifact.is_file() or artifact.stat().st_size == 0:
                raise ValueError("Rojo не оставил непустую сборку")
            report["build"] = {"path": str(artifact), "bytes": artifact.stat().st_size,
                               "sha256": hashlib.sha256(artifact.read_bytes()).hexdigest()}
            report["inputsAfter"] = fingerprint(root)
            if report["inputsBefore"] != report["inputsAfter"]:
                raise ValueError("Исходники изменились во время проверки. Повторите прогон.")
            report["ok"] = True
    except KeyboardInterrupt:
        report["error"] = "Проверка прервана"
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        report["error"] = str(error)
    report_path = output / "report.json"
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Отчёт: {report_path}", flush=True)
    if not report["ok"]:
        print(report.get("error", "Проверка не завершена"), file=sys.stderr)
    return report


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, help="Новая папка для сборки, отчёта и логов")
    args = parser.parse_args(argv)
    if args.output_dir:
        output = args.output_dir.expanduser().resolve()
        if output.is_relative_to(ROOT / "src"):
            parser.error("Папка результатов должна быть вне src, чтобы не попасть в игровой place")
        try:
            output.mkdir(parents=True, exist_ok=False)
        except OSError as error:
            parser.error(f"Не удалось создать новую папку: {error}")
    else:
        output = Path(tempfile.mkdtemp(prefix="chocolatier-check-"))
    return 0 if run_checks(ROOT, output)["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
