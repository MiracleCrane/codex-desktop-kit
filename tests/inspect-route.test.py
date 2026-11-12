import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'scripts/inspect-route.py'
BASE = 'http://127.0.0.1:3456/backend-api/codex'


class RouteTests(unittest.TestCase):
    def inspect(self, text, expected=None, catalog=False):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            path=root/'config.toml';path.write_text(text,encoding='utf-8')
            if catalog:(root/'models.json').write_text('{}')
            args=[sys.executable,str(SCRIPT),'--config',str(path)]
            if expected:args+=['--expected-base-url',expected]
            result=subprocess.run(args,text=True,capture_output=True)
            return result.returncode,json.loads(result.stdout),result.stdout

    def test_default(self):
        code,data,_=self.inspect('model="fixture"\n')
        self.assertEqual(code,0);self.assertEqual(data['route'],'default');self.assertTrue(data['catalogExists'])

    def test_magpie_and_relative_catalog(self):
        code,data,_=self.inspect(f'openai_base_url="{BASE}"\nmodel_catalog_json="models.json"\n',BASE,True)
        self.assertEqual(code,0);self.assertTrue(data['matchesExpected']);self.assertTrue(data['catalogExists'])

    def test_missing_catalog(self):
        _,data,_=self.inspect(f'openai_base_url="{BASE}"\nmodel_catalog_json="models.json"\n',BASE)
        self.assertFalse(data['catalogExists'])

    def test_foreign_route_and_provider(self):
        for text in [f'openai_base_url="{BASE.replace("3456","3457")}"\n',f'openai_base_url="{BASE}"\nmodel_provider="other"\n']:
            _,data,_=self.inspect(text,BASE);self.assertFalse(data['matchesExpected'])

    def test_sensitive_url_is_not_reported(self):
        _,data,out=self.inspect('openai_base_url="http://name:sensitive-fixture@127.0.0.1:3456/backend-api/codex"\n',BASE)
        self.assertFalse(data['matchesExpected']);self.assertIsNone(data['baseUrl']);self.assertNotIn('sensitive-fixture',out)

    def test_bad_expected_and_bad_toml(self):
        for text,expected in [('', 'https://example.com/backend-api/codex'),('invalid = [',BASE)]:
            code,data,_=self.inspect(text,expected);self.assertNotEqual(code,0);self.assertIn('error',data)


if __name__=='__main__':unittest.main()
