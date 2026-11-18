import importlib.util
from pathlib import Path
import tempfile
import unittest
from types import SimpleNamespace

spec=importlib.util.spec_from_file_location('reconnect',Path(__file__).resolve().parents[1]/'scripts/reconnect-magpie.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
BASE='http://127.0.0.1:3456/backend-api/codex'

class Tests(unittest.TestCase):
    def test_native_pick_and_limits_preserved(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'config.toml';p.write_text('model="gpt-test"\nmodel_context_window=1050000\nmodel_auto_compact_token_limit=900000\n')
            calls=[]
            def run(args,**kwargs):
                calls.append(args[-1]);s=p.read_text();import re
                s=re.sub(r'model="[^"]+"','model="'+args[-1]+'"',s)
                if 'openai_base_url' not in s:s+='openai_base_url="'+BASE+'"\n'
                p.write_text(s);return SimpleNamespace(returncode=0)
            m.reconnect(p,'fixture.exe',BASE,run)
            self.assertEqual(calls,['codex/gpt-test','gpt-test'])
            self.assertTrue(list((Path(d)/'config-backups').glob('*.toml')))
    def test_foreign_route_and_unknown_model_are_preserved(self):
        for text in ['model="gpt-test"\nopenai_base_url="https://other.invalid"\n','model="unknown"\n','model="gpt-test"\nmodel_provider="other"\n']:
            with tempfile.TemporaryDirectory() as d:
                p=Path(d)/'config.toml';p.write_text(text)
                with self.assertRaises(ValueError):m.reconnect(p,'fixture.exe',BASE,lambda *a,**k:self.fail('must not execute'))
                self.assertEqual(p.read_text(),text)
    def test_command_failure_stops(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'config.toml';p.write_text('model="gpt-test"\n')
            with self.assertRaises(RuntimeError):m.reconnect(p,'fixture.exe',BASE,lambda *a,**k:SimpleNamespace(returncode=1))

if __name__=='__main__':unittest.main()
