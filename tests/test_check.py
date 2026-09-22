"""Локальная приёмка не выдаёт успешный отчёт по упавшим или устаревшим проверкам."""
import contextlib
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("local_check", ROOT / "tools/check.py")
check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check)


class LocalCheckTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "project with spaces"
        (self.root / "src").mkdir(parents=True)
        (self.root / ".git-codex").mkdir()
        (self.root / "src/main.luau").write_text("return 1\n")
        self.output = Path(self.temp.name) / "results"
        self.output.mkdir()
        self.calls = []

    def runner(self, command, **kwargs):
        self.calls.append(command)
        self.assertEqual(kwargs["cwd"], self.root)
        self.assertNotIn("shell", kwargs)
        if "rev-parse" in command:
            return subprocess.CompletedProcess(command, 0, stdout="abc123\n")
        if command[0] == "rojo":
            Path(command[-1]).write_bytes(b"<roblox/>")
        return subprocess.CompletedProcess(command, 0)

    def run_check(self, runner=None):
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            result = check.run_checks(self.root, self.output, runner=runner or self.runner)
        self.assertEqual(json.loads((self.output / "report.json").read_text()), result)
        return result

    def test_success_records_exact_build_without_claiming_studio_or_release(self):
        result = self.run_check()
        self.assertTrue(result["ok"])
        self.assertEqual(result["commit"], "abc123")
        self.assertEqual(result["build"]["sha256"], hashlib.sha256(b"<roblox/>").hexdigest())
        self.assertEqual(len(result["checks"]), 5)
        self.assertFalse(result["studioChecked"])
        self.assertFalse(result["published"])
        self.assertIn("--git-dir=.git-codex", self.calls[0])
        self.assertIn("HEAD", self.calls[-1])
        self.assertEqual(result["inputsBefore"], result["inputsAfter"])

    def test_failure_stops_before_build_and_retains_log(self):
        def run(command, **kwargs):
            if command[:3] == ["lune", "run", "tests/run"]:
                kwargs["stdout"].write(b"test failed\n")
                return subprocess.CompletedProcess(command, 3)
            return self.runner(command, **kwargs)
        result = self.run_check(run)
        self.assertFalse(result["ok"])
        self.assertEqual(result["checks"][-1]["exitCode"], 3)
        self.assertEqual(len(result["checks"]), 2)
        self.assertEqual((self.output / "luau.log").read_text(), "test failed\n")
        self.assertFalse((self.output / "game.rbxlx").exists())

    def test_new_source_during_build_invalidates_green_checks(self):
        def run(command, **kwargs):
            result = self.runner(command, **kwargs)
            if command[0] == "rojo":
                (self.root / "src/new.luau").write_text("return 2\n")
            return result
        result = self.run_check(run)
        self.assertFalse(result["ok"])
        self.assertNotEqual(result["inputsBefore"], result["inputsAfter"])
        self.assertIn("изменились", result["error"])

    def test_missing_tool_timeout_and_interruption_leave_failed_report(self):
        for error in (FileNotFoundError("lune missing"), subprocess.TimeoutExpired("lune", 180), KeyboardInterrupt()):
            def run(command, **kwargs):
                if command[0] == "lune":
                    raise error
                return self.runner(command, **kwargs)
            result = self.run_check(run)
            self.assertFalse(result["ok"])
            self.assertIn("error", result)

    def test_successful_command_without_build_is_not_success(self):
        def run(command, **kwargs):
            if command[0] == "rojo":
                return subprocess.CompletedProcess(command, 0)
            return self.runner(command, **kwargs)
        self.assertFalse(self.run_check(run)["ok"])

    def test_existing_output_is_never_overwritten(self):
        marker = self.output / "report.json"
        marker.write_text("keep")
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as error:
            check.main(["--output-dir", str(self.output)])
        self.assertEqual(error.exception.code, 2)
        self.assertEqual(marker.read_text(), "keep")

    def test_output_cannot_become_part_of_the_game(self):
        output = ROOT / "src" / ("qa-output-" + self.root.parent.name)
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as error:
            check.main(["--output-dir", str(output)])
        self.assertEqual(error.exception.code, 2)
        self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
