"""Границы записи и восстановление без установленной Studio."""
import importlib.util
import json
from pathlib import Path
import tempfile
import types
import queue
import shutil
import subprocess
import unittest
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location("studio_qa",ROOT/"tools/studio_qa.py")
qa=importlib.util.module_from_spec(spec)
spec.loader.exec_module(qa)

class FakeMCP:
    def __init__(self,failure=None):
        self.failure=failure; self.calls=[]; self.pending=None; self.closed=False
    def tool(self,name,**args):
        self.calls.append((name,args))
        if name=="list_roblox_studios":
            return {"studios":[{"id":"local-qa","name":qa.DEFAULT_PLACE}]}
        if name=="execute_luau":
            code=args["code"]
            if 'GetLogHistory()' in code: return {"count":0,"errors":[]}
            if "q:Invoke" in code:
                if self.failure: raise qa.QaError("test interruption")
                return {"ready":True,"workers":25,"manual":1,"ok":True}
            if "local entries=" in code: return {"scripts":44,"verified":True}
            return {"placeId":0,"running":False}
        return "ok"
    def close(self): self.closed=True

class StudioQaTests(unittest.TestCase):
    def test_timeout_keeps_same_request_and_never_sends_it_twice(self):
        client=qa.MCP.__new__(qa.MCP)
        client.timeout=.002; client.next_id=0; client.pending=None; client.replies=queue.Queue()
        sent=[]; client._send=sent.append
        with self.assertRaises(qa.QaError): client.request("tools/call",{"name":"start_stop_play"})
        self.assertEqual(client.pending,1)
        with self.assertRaises(qa.QaError): client.request("tools/call",{"name":"start_stop_play"})
        self.assertEqual(len(sent),1)
        client.replies.put({"id":1,"result":{"done":True}})
        self.assertEqual(client.settle_pending(),{"done":True})
        self.assertIsNone(client.pending)

    @unittest.skipUnless(shutil.which("lune"),"Для проверки генератора нужен Lune")
    def test_generated_scripts_compile_and_data_roundtrip_in_luau(self):
        data={"text":"\nрусский ]=] \"quote\"", "boolean":True,"numbers":[1,2,3]}
        entries=qa.source_inventory()
        sources=[qa.sync_code(entries),qa.sync_code(entries,qa.qa_overrides(entries)),
                 (ROOT/"src/client/init.client.luau").read_text()+"\n"+(ROOT/"tools/studio_qa_client.luau").read_text()]
        code="local luau=require('@lune/luau')\n"
        for source in sources: code+="luau.compile("+qa.lua(source)+")\n"
        code+="local data="+qa.lua(data)+"\nprint(require('@lune/serde').encode('json',data))\n"
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/"qa-compile.luau"; path.write_text(code)
            result=subprocess.run(["lune","run",str(path)],capture_output=True,text=True,timeout=20)
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(json.loads(result.stdout),data)

    def test_studio_registration_can_follow_a_temporary_unreachable_reply(self):
        fake=FakeMCP(); attempts=[]
        def discover(name,**args):
            attempts.append(name)
            if len(attempts)<3: raise qa.QaError("Unable to reach Roblox Studio right now")
            return FakeMCP.tool(fake,name,**args)
        fake.tool=discover
        with patch.object(qa.time,"sleep"):
            self.assertEqual(qa.discover_studios(fake)[0]["id"],"local-qa")
        self.assertEqual(attempts,["list_roblox_studios"]*3)

    def test_wrong_or_ambiguous_scene_is_rejected(self):
        with self.assertRaises(qa.QaError):
            qa.select_studio([{"id":"prod","name":"Infinite Chocolatier"}],"Infinite Chocolatier")
        studios=[{"id":"a","name":qa.DEFAULT_PLACE},{"id":"b","name":qa.DEFAULT_PLACE}]
        with self.assertRaises(qa.QaError): qa.select_studio(studios,qa.DEFAULT_PLACE)
        self.assertEqual(qa.select_studio(studios,qa.DEFAULT_PLACE,"b"),"b")
        with self.assertRaises(qa.QaError): qa.select_studio(studios,qa.DEFAULT_PLACE,"missing")

    def test_lua_strings_preserve_quotes_newlines_and_bracket_tokens(self):
        text="\nрусский 'quoted' ]=] ]==] `$(ignored)`"
        self.assertEqual(qa.lua(text),"[===[\n"+text+"]===]")
        with self.assertRaises(qa.QaError): qa.lua(float("nan"))
        with self.assertRaises(qa.QaError): qa.lua(float("inf"))

    def test_tool_errors_are_not_treated_as_success(self):
        self.assertEqual(qa.decode_tool({"content":[{"type":"text","text":'{"ready":true}'}]}),{"ready":True})
        with self.assertRaises(qa.QaError):
            qa.decode_tool({"isError":True,"content":[{"type":"text","text":"not Studio"}]})

    def test_overrides_only_in_memory_and_clean_sync_restores_all_sources(self):
        entries=qa.source_inventory(); before={e["path"]:e["source"] for e in entries}
        overrides=qa.qa_overrides(entries)
        self.assertIn(qa.QA_MARKER,overrides["src/client/init.client.luau"])
        self.assertNotIn(qa.QA_MARKER,qa.sync_code(entries))
        self.assertIn(qa.QA_MARKER,qa.sync_code(entries,overrides))
        self.assertEqual(before,{e["path"]:e["source"] for e in qa.source_inventory()})
        self.assertIn("game.PlaceId == 0",qa.sync_code(entries))
        self.assertIn("Unexpected script:",qa.sync_code(entries))

    def test_failed_smoke_stops_own_play_and_restores_sources(self):
        fake=FakeMCP(failure=True)
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/"report.json"
            args=types.SimpleNamespace(command="smoke",mcp="unused",timeout=1,place_name=qa.DEFAULT_PLACE,studio_id=None,report=str(path))
            self.assertEqual(qa.run(args,lambda *args:fake),1)
            report=json.loads(path.read_text())
        play=[args["is_start"] for name,args in fake.calls if name=="start_stop_play"]
        self.assertEqual(play,[True,False])
        syncs=[args["code"] for name,args in fake.calls if name=="execute_luau" and "local entries=" in args["code"]]
        self.assertIn(qa.QA_MARKER,syncs[0]); self.assertNotIn(qa.QA_MARKER,syncs[-1])
        self.assertFalse(report["ok"]); self.assertEqual(report["cleanup"],{"placeId":0,"running":False})
        self.assertTrue(fake.closed)

    def test_existing_play_or_published_scene_is_not_stopped(self):
        fake=FakeMCP()
        def reject(name,**args):
            if name=="execute_luau": raise qa.QaError("Already playing")
            return FakeMCP.tool(fake,name,**args)
        fake.tool=reject
        with tempfile.TemporaryDirectory() as directory:
            args=types.SimpleNamespace(command="smoke",mcp="unused",timeout=1,place_name=qa.DEFAULT_PLACE,studio_id=None,report=str(Path(directory)/"report.json"))
            self.assertEqual(qa.run(args,lambda *args:fake),1)
        self.assertFalse(any(name=="start_stop_play" for name,_ in fake.calls))

    def test_cleanup_failure_cannot_report_success(self):
        fake=FakeMCP(); syncs=[]
        def fail_restore(name,**args):
            if name=="execute_luau" and "local entries=" in args["code"]:
                syncs.append(args["code"])
                if len(syncs)>1: raise qa.QaError("cleanup disconnected")
            return FakeMCP.tool(fake,name,**args)
        fake.tool=fail_restore
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/"report.json"
            args=types.SimpleNamespace(command="smoke",mcp="unused",timeout=1,place_name=qa.DEFAULT_PLACE,studio_id=None,report=str(path))
            self.assertEqual(qa.run(args,lambda *args:fake),1)
            report=json.loads(path.read_text())
        self.assertFalse(report["ok"])
        self.assertEqual(report["cleanupError"],"cleanup disconnected")

    def test_engine_error_is_a_failed_smoke_even_when_feature_checks_pass(self):
        fake=FakeMCP()
        def error_log(name,**args):
            if name=="execute_luau" and 'GetLogHistory()' in args["code"]:
                return {"count":1,"errors":["test engine failure"]}
            return FakeMCP.tool(fake,name,**args)
        fake.tool=error_log
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/"report.json"
            args=types.SimpleNamespace(command="smoke",mcp="unused",timeout=1,place_name=qa.DEFAULT_PLACE,studio_id=None,report=str(path))
            self.assertEqual(qa.run(args,lambda *args:fake),1)
            report=json.loads(path.read_text())
        self.assertFalse(report["ok"]); self.assertEqual(report["failedStage"],"engine-errors")
        self.assertIn("cleanup",report)

if __name__=="__main__": unittest.main()
