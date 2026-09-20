#!/usr/bin/env python3
"""Локальные проверки через встроенный Studio MCP без управления окнами."""

import argparse
import fcntl
import hashlib
import json
import math
from pathlib import Path
import queue
import signal
import subprocess
import sys
import tempfile
import threading
import time

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MCP = "/Applications/RobloxStudio.app/Contents/MacOS/StudioMCP"
DEFAULT_PLACE = "chocolatier-diagnostics.rbxlx"
QA_MARKER = "StudioQaControl"


class QaError(RuntimeError):
    pass


def lua(value):
    """Данные передаются как литералы Luau, без shell и подстановок кода."""
    if value is None:
        return "nil"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        if not math.isfinite(value):
            raise QaError("Число для Luau должно быть конечным")
        return repr(value)
    if isinstance(value, str):
        equals = "="
        while "]" + equals + "]" in value:
            equals += "="
        # Luau убирает первый перевод строки у длинного литерала.
        return "[" + equals + "[\n" + value + "]" + equals + "]"
    if isinstance(value, (list, tuple)):
        return "{" + ",".join(lua(item) for item in value) + "}"
    if isinstance(value, dict):
        return "{" + ",".join("[ " + lua(k) + " ] = " + lua(v) for k, v in value.items()) + "}"
    raise QaError("Неподдерживаемые данные Luau: " + type(value).__name__)


def decode_tool(result):
    texts = [item["text"] for item in result.get("content", []) if item.get("type") == "text"]
    text = "\n".join(texts)
    if result.get("isError"):
        raise QaError(text or "Studio MCP вернул ошибку без текста")
    if result.get("structuredContent") is not None:
        return result["structuredContent"]
    try:
        return json.loads(text)
    except (ValueError, TypeError):
        return text


class MCP:
    """Один stdio-клиент, последовательные запросы, без перезапуска при таймауте."""

    def __init__(self, executable=DEFAULT_MCP, timeout=45):
        self.timeout = timeout
        self.next_id = 0
        self.pending = None
        self.replies = queue.Queue()
        self.stderr = tempfile.TemporaryFile(mode="w+")
        self.process = subprocess.Popen([executable], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                        stderr=self.stderr, text=True, bufsize=1)
        threading.Thread(target=self._read, daemon=True).start()
        try:
            self.request("initialize", {"protocolVersion": "2024-11-05", "capabilities": {},
                         "clientInfo": {"name": "infinite-chocolatier-qa", "version": "1"}})
            self._send({"jsonrpc": "2.0", "method": "notifications/initialized"})
        except BaseException:
            self.close()
            raise

    def _read(self):
        for line in self.process.stdout:
            try:
                response = json.loads(line)
            except ValueError:
                continue
            if "id" in response:
                self.replies.put(response)
        self.replies.put(None)

    def _send(self, payload):
        self.process.stdin.write(json.dumps(payload) + "\n")
        self.process.stdin.flush()

    def settle_pending(self):
        if self.pending is None:
            return None
        pending = self.pending
        deadline = time.monotonic() + self.timeout
        while True:
            try:
                reply = self.replies.get(timeout=max(.01, deadline - time.monotonic()))
            except queue.Empty:
                raise QaError(f"MCP запрос {pending} ещё не завершён; повторно не отправлялся")
            if reply is None:
                raise QaError("Studio MCP закрыл соединение")
            if reply.get("id") != pending:
                raise QaError("Нарушен порядок ответов Studio MCP")
            self.pending = None
            if "error" in reply:
                raise QaError(str(reply["error"]))
            return reply.get("result", {})

    def request(self, method, params):
        if self.pending is not None:
            raise QaError("Предыдущий MCP запрос ещё выполняется")
        self.next_id += 1
        self.pending = self.next_id
        self._send({"jsonrpc": "2.0", "id": self.pending, "method": method, "params": params})
        return self.settle_pending()

    def tool(self, name, **arguments):
        return decode_tool(self.request("tools/call", {"name": name, "arguments": arguments}))

    def close(self):
        if self.process.poll() is None:
            # Сначала даём proxy закончить работу по EOF; сигналы нужны,
            # только если штатное завершение не укладывается в срок.
            self.process.stdin.close()
            try:
                self.process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                self.process.terminate()
                try:
                    self.process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    self.process.kill()
                    self.process.wait(timeout=5)
        for stream in (self.process.stdin, self.process.stdout, self.stderr):
            stream.close()


def select_studio(studios, place_name, studio_id=None):
    # Разрешаем только явные локальные копии QA, никогда имя опубликованной игры.
    if place_name != DEFAULT_PLACE and not place_name.endswith("-qa.rbxlx"):
        raise QaError("Для записи нужна локальная сцена с именем *-qa.rbxlx")
    matches = [row for row in studios if row.get("name") == place_name
               and (studio_id is None or row.get("id") == studio_id)]
    if len(matches) != 1:
        raise QaError(f"Нужна ровно одна сцена {place_name!r}; найдено {len(matches)}")
    return matches[0]["id"]


def discover_studios(client):
    # Proxy отвечает на initialize раньше, чем Studio зарегистрирует сцену.
    # Ждём только обнаружение; команды запуска/записи здесь не повторяются.
    deadline = time.monotonic() + 30
    while True:
        try:
            studios = client.tool("list_roblox_studios").get("studios", [])
        except QaError as error:
            if client.pending is not None or "Unable to reach Roblox Studio right now" not in str(error):
                raise
            studios = []
        if studios or time.monotonic() >= deadline:
            return studios
        time.sleep(1)


GUARD = """
assert(game:GetService('RunService'):IsStudio(), 'Not Studio')
assert(not game:GetService('RunService'):IsRunning(), 'Already playing: do not interrupt this session')
assert(game.PlaceId == 0, 'Published place: use a local Rojo QA build')
assert(game.ReplicatedStorage:FindFirstChild('Shared'), 'Missing Shared')
assert(game.ServerScriptService:FindFirstChild('InfiniteChocolateServer'), 'Missing server')
assert(game.StarterPlayer.StarterPlayerScripts:FindFirstChild('InfiniteChocolateClient'), 'Missing client')
"""
BASES = {"shared": "game.ReplicatedStorage.Shared",
         "server": "game.ServerScriptService.InfiniteChocolateServer",
         "client": "game.StarterPlayer.StarterPlayerScripts.InfiniteChocolateClient"}


def source_inventory(root=ROOT):
    entries = []
    for folder, base in BASES.items():
        for path in sorted((root / "src" / folder).glob("*.luau")):
            entrypoint = path.name.startswith("init.")
            source = path.read_text()
            if QA_MARKER in source:
                raise QaError("Тестовый обработчик попал в исходники: " + str(path))
            entries.append({"folder": folder, "name": path.stem, "base": base,
                            "entrypoint": entrypoint, "source": source,
                            "class": ("Script" if folder == "server" else "LocalScript") if entrypoint else "ModuleScript",
                            "path": str(path.relative_to(root)),
                            "sha256": hashlib.sha256(source.encode()).hexdigest()})
    for folder in BASES:
        if not any(entry["folder"] == folder for entry in entries):
            raise QaError("Не найдены исходники src/" + folder)
    return entries


def sync_code(entries, overrides=None):
    overrides = overrides or {}
    rows = []
    for entry in entries:
        row = dict(entry)
        row["source"] = overrides.get(row["path"], row["source"])
        # Ссылки на корни подставляем как код из констант, исходники — литералами.
        rows.append("{base=" + row["base"] + ",name=" + lua(row["name"]) +
                    ",entrypoint=" + lua(row["entrypoint"]) + ",class=" + lua(row["class"]) +
                    ",source=" + lua(row["source"]) + "}")
    return GUARD + "\nlocal entries={" + ",\n".join(rows) + "}\n" + """
local expected={}
for _,e in entries do
 expected[e.base]=expected[e.base] or {}
 if not e.entrypoint then expected[e.base][e.name]=true end
 local target=if e.entrypoint then e.base else e.base:FindFirstChild(e.name)
 assert(not target or target.ClassName==e.class, 'Wrong class for '..e.name)
end
-- Лишний код не удаляем молча: требуется заново собрать тестовую копию.
for base,names in expected do
 for _,child in base:GetChildren() do
  assert(not child:IsA('LuaSourceContainer') or names[child.Name], 'Unexpected script: '..child:GetFullName())
 end
end
local editor=game:GetService('ScriptEditorService')
for _,e in entries do
 local target=if e.entrypoint then e.base else e.base:FindFirstChild(e.name)
 if not target then target=Instance.new(e.class); target.Name=e.name; target.Parent=e.base end
 editor:UpdateSourceAsync(target,function() return e.source end)
 assert(target.Source==e.source, 'Source readback mismatch: '..e.name)
end
return {scripts=#entries,verified=true}
"""


def qa_overrides(entries, root=ROOT):
    sources = {entry["path"]: entry["source"] for entry in entries}
    server_path = "src/server/init.server.luau"
    needle = "data, offline = Economy.load(nil), 0"
    if sources[server_path].count(needle) != 1:
        raise QaError("Точка тестового профиля изменилась; обновите сценарий QA")
    seed = "data, offline, offlineReport = Economy.load({slices=10000,collectionVersion=2,owned={workers_1=true},levels={kitchen=1,cafes=12}}), 1440, {seconds=14400,capped=true}"
    localization_path = "src/client/Localization.luau"
    if sources[localization_path].count("return L") != 1:
        raise QaError("Точка переключения языка изменилась; обновите сценарий QA")
    locale = "function L.__qaLocale(value) locale=value; for label,binding in bindings do render(label,binding) end end\nreturn L"
    client_path = "src/client/init.client.luau"
    return {server_path: sources[server_path].replace(needle, seed),
            localization_path: sources[localization_path].replace("return L", locale),
            client_path: sources[client_path] + "\n" + (root / "tools/studio_qa_client.luau").read_text()}


class Session:
    def __init__(self, mcp, studio_id, entries, report):
        self.mcp, self.studio_id, self.entries, self.report = mcp, studio_id, entries, report
        self.modified = False
        self.play_attempted = False

    def execute(self, code, mode="Edit"):
        return self.mcp.tool("execute_luau", studio_id=self.studio_id, datamodel_type=mode, code=code)

    def check(self):
        return self.execute(GUARD + "return {placeId=game.PlaceId,running=false}")

    def sync(self, overrides=None):
        self.report["stage"] = "install-test-sources" if overrides else "sync-clean-sources"
        self.modified = True
        return self.execute(sync_code(self.entries, overrides))

    def control(self, action, **options):
        args = dict(action=action, **options)
        return self.execute("local p=game.Players.LocalPlayer; local q=p and p:FindFirstChild('PlayerGui') and p.PlayerGui:FindFirstChild('" + QA_MARKER + "'); if not q then return {ready=false} end; return q:Invoke(" + lua(args) + ")", "Client")

    def cleanup(self):
        # После таймаута сначала ждём тот же запрос. Не отправляем повторную запись.
        if self.mcp.pending is not None:
            self.mcp.settle_pending()
        if self.play_attempted:
            self.mcp.tool("start_stop_play", studio_id=self.studio_id, is_start=False)
            self.play_attempted = False
        if self.modified:
            self.report["restoredSources"] = self.sync()
            self.modified = False
        self.report["cleanup"] = self.check()

    def smoke(self):
        self.check()
        self.sync(qa_overrides(self.entries))
        self.play_attempted = True
        self.report["stage"] = "start-play"
        self.mcp.tool("start_stop_play", studio_id=self.studio_id, is_start=True)
        deadline = time.monotonic() + 35
        self.report["stage"] = "wait-for-client"
        while time.monotonic() < deadline:
            state = self.control("snapshot")
            if isinstance(state, dict) and state.get("ready"):
                break
            time.sleep(.4)
        else:
            raise QaError("Игра не загрузила состояние за 35 секунд")
        checks = [("startup", state)]
        self.report["checks"] = checks
        if state.get("workers") != 25 or state.get("manual") != 1:
            raise QaError("Тестовый профиль не применён: " + str(state))
        for name, options in [("purchase", {}), ("orders", {}), ("journal", {}),
                              ("layout", {"locale": "en-us"}), ("layout", {"locale": "ru-ru"}),
                              ("kitchen", {}), ("visibility", {})]:
            print("Studio QA: " + name + " " + options.get("locale", ""), flush=True)
            self.report["stage"] = name
            result = self.control(name, **options)
            if not isinstance(result, dict) or result.get("ok") is not True:
                raise QaError(name + ": " + str(result))
            checks.append((name, result))
        self.report["console"] = self.mcp.tool("get_console_output", studio_id=self.studio_id)
        self.report["engineLogs"] = {}
        self.report["stage"] = "engine-errors"
        for mode in ("Client", "Server"):
            logs = self.execute("""
local errors={}; local count=0
for _,entry in game:GetService('LogService'):GetLogHistory() do
 count+=1
 assert(typeof(entry.messageType)=='EnumItem','Unknown log record format')
 if entry.messageType==Enum.MessageType.MessageError then table.insert(errors,entry.message) end
end
return {errors=errors,count=count}
""", mode)
            self.report["engineLogs"][mode] = logs
            if not isinstance(logs, dict) or "errors" not in logs or logs["errors"]:
                raise QaError("Ошибки движка " + mode + ": " + str(logs))
        self.report["visualReview"] = "Не выполнялась: проверены состояние, геометрия UI и вызовы обработчиков, не снимок или нативный ввод."


def run(args, mcp_factory=MCP):
    report = {"startedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "command": args.command}
    entries = source_inventory()
    report["sources"] = {entry["path"]: entry["sha256"] for entry in entries}
    client = session = None
    failure = None
    try:
        client = mcp_factory(args.mcp, args.timeout)
        studios = discover_studios(client)
        if args.command == "list":
            report["studios"] = studios
        else:
            studio_id = select_studio(studios, args.place_name, args.studio_id)
            report["studioId"] = studio_id
            session = Session(client, studio_id, entries, report)
            report["before"] = session.check()
            if args.command == "sync":
                report["sync"] = session.sync()
            elif args.command == "smoke":
                session.smoke()
        report["ok"] = True
    except BaseException as error:
        failure = error
        report["ok"] = False
        report["error"] = str(error) or type(error).__name__
        report["failedStage"] = report.get("stage", "preflight")
    finally:
        if session and (session.modified or session.play_attempted):
            try:
                session.cleanup()
            except BaseException as error:
                report["ok"] = False
                report["cleanupError"] = str(error) or type(error).__name__
                failure = failure or error
        if client:
            if failure and hasattr(client, "stderr"):
                client.stderr.seek(0)
                report["transportLog"] = client.stderr.read()[-4000:]
            client.close()
        destination = Path(args.report).resolve()
        destination.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
        print(json.dumps({"ok": report.get("ok"), "report": str(destination),
                          "error": report.get("error"), "cleanupError": report.get("cleanupError")}, ensure_ascii=False), flush=True)
    return 1 if failure else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["list", "check", "sync", "smoke"])
    parser.add_argument("--place-name", default=DEFAULT_PLACE)
    parser.add_argument("--studio-id")
    parser.add_argument("--mcp", default=DEFAULT_MCP)
    parser.add_argument("--timeout", type=float, default=45)
    parser.add_argument("--report", default="/tmp/chocolatier-studio-report.json")
    args = parser.parse_args()
    def interrupted(_signal, _frame):
        raise KeyboardInterrupt("Studio QA interrupted")
    signal.signal(signal.SIGTERM, interrupted)
    if not 1 <= args.timeout <= 60:
        parser.error("--timeout должен быть от 1 до 60 секунд")
    # flock освобождается ОС и при аварийном завершении; наличие файла не
    # считается доказательством работающего процесса.
    with open("/tmp/infinite-chocolatier-studio-qa.lock", "w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            parser.exit(2, "Другой сценарий Studio QA ещё выполняется.\n")
        return run(args)


if __name__ == "__main__":
    sys.exit(main())
