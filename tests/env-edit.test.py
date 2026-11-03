import argparse
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import unittest

sys.dont_write_bytecode = True
p = argparse.ArgumentParser()
p.add_argument('--work-directory', required=True)
a = p.parse_args()
root = Path(a.work_directory).resolve()
root.mkdir(parents=True, exist_ok=False)
script = Path(__file__).resolve().parents[1] / 'scripts/env-edit.py'
spec = importlib.util.spec_from_file_location('env_edit', script)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ProxyTransactions(unittest.TestCase):
    def setUp(self):
        self.path = root / self._testMethodName
        self.path.mkdir()
        self.config = self.path / '.env'
        self.state = self.path / 'first/state.json'

    def run_command(self, action, state=None, extra=(), ok=True):
        command = [sys.executable, '-X', 'utf8', str(script), action, '--state', str(state or self.state)]
        r = subprocess.run(command + list(extra), capture_output=True, text=True, encoding='utf-8')
        self.assertEqual(r.returncode == 0, ok, r.stdout + r.stderr)
        return json.loads(r.stdout)

    def prepare(self, state=None, proxy='http://127.0.0.1:7897', previous=None):
        args = ['--config', str(self.config), '--proxy', proxy, '--instance', (state or self.state).parent.name,
                '--no-proxy', 'localhost,127.0.0.1,::1,.corp.example']
        if previous:
            args += ['--previous-state', str(previous)]
        self.run_command('prepare', state, args)

    def test_restore_original_bom_crlf_and_duplicate_settings(self):
        original = b'\xef\xbb\xbf# local\r\nHTTP_PROXY="http://old:12"\r\nOTHER="example"\r\nHTTP_PROXY=http://last:34\r\n'
        self.config.write_bytes(original)
        self.prepare()
        self.run_command('apply')
        self.assertTrue(self.run_command('inspect')['effective'])
        self.run_command('restore')
        self.assertEqual(self.config.read_bytes(), original)

    def test_concurrent_edit_before_apply_is_preserved(self):
        self.config.write_bytes(b'OTHER=first\n')
        self.prepare()
        changed = b'OTHER=second\n'
        self.config.write_bytes(changed)
        self.run_command('apply', ok=False)
        self.assertEqual(self.config.read_bytes(), changed)

    def test_later_unrelated_edit_survives_restore(self):
        self.config.write_bytes(b'OTHER=before\n')
        self.prepare(); self.run_command('apply')
        with self.config.open('ab') as stream:
            stream.write(b'NEW_SETTING=retained\n')
        self.run_command('restore')
        self.assertEqual(self.config.read_bytes(), b'OTHER=before\nNEW_SETTING=retained\n')

    def test_owned_block_edit_is_not_overwritten(self):
        self.prepare(); self.run_command('apply')
        changed = self.config.read_bytes().replace(b'7897', b'1234')
        self.config.write_bytes(changed)
        self.run_command('restore', ok=False)
        self.assertEqual(self.config.read_bytes(), changed)

    def test_later_user_override_is_detected_and_preserved(self):
        self.prepare(); self.run_command('apply')
        with self.config.open('ab') as stream:
            stream.write(b'HTTP_PROXY=http://127.0.0.1:1234\n')
        self.assertFalse(self.run_command('inspect')['effective'])
        self.run_command('restore')
        self.assertEqual(module.values(self.config.read_bytes())['HTTP_PROXY'], 'http://127.0.0.1:1234')

    def test_upgrade_and_two_restores_preserve_user_changes(self):
        self.config.write_bytes(b'OTHER=initial\n')
        self.prepare(); self.run_command('apply')
        second = self.path / 'second/state.json'
        self.prepare(second, 'http://127.0.0.1:9876', self.state)
        self.run_command('apply', second)
        self.assertEqual(module.values(self.config.read_bytes())['HTTP_PROXY'], 'http://127.0.0.1:9876')
        self.assertEqual(self.config.read_bytes().count(b'# >>> codex-desktop-kit'), 1)
        with self.config.open('ab') as stream:
            stream.write(b'OTHER_NEW=retained\n')
        self.run_command('restore', second)
        self.assertTrue(self.run_command('inspect')['effective'])
        self.run_command('restore')
        self.assertEqual(self.config.read_bytes(), b'OTHER=initial\nOTHER_NEW=retained\n')

    def test_failed_upgrade_leaves_previous_proxy(self):
        self.prepare(); self.run_command('apply')
        second = self.path / 'second/state.json'
        self.prepare(second, 'http://127.0.0.1:9876', self.state)
        with self.config.open('ab') as stream:
            stream.write(b'UNRELATED=changed\n')
        self.run_command('apply', second, ok=False)
        self.assertTrue(self.run_command('inspect')['effective'])

    def test_no_final_newline_is_restored_exactly(self):
        self.config.write_bytes(b'OTHER=no-newline')
        self.prepare(); self.run_command('apply'); self.run_command('restore')
        self.assertEqual(self.config.read_bytes(), b'OTHER=no-newline')

    def test_existing_intranet_bypasses_are_preserved(self):
        self.config.write_bytes(b'NO_PROXY="10.0.0.0/8,.internal"\n')
        self.prepare(); self.run_command('apply')
        bypass = module.values(self.config.read_bytes())['NO_PROXY'].split(',')
        self.assertTrue({'10.0.0.0/8', '.internal', '.corp.example', '::1'}.issubset(bypass))

    def test_unknown_kit_installation_is_not_adopted(self):
        self.prepare(); self.run_command('apply')
        original = self.config.read_bytes()
        second = self.path / 'second/state.json'
        self.run_command('prepare', second, ['--config', str(self.config), '--proxy', 'http://127.0.0.1:7897', '--instance', 'second'], ok=False)
        self.assertEqual(self.config.read_bytes(), original)

    def test_windows_mixed_case_last_assignment_and_bypass(self):
        self.config.write_bytes(b'no_proxy=corp.internal\nHTTP_PROXY=http://127.0.0.1:12\nhttp_proxy=http://127.0.0.1:34\n')
        self.assertEqual(module.values(self.config.read_bytes())['HTTP_PROXY'], 'http://127.0.0.1:34')
        self.prepare(); self.run_command('apply')
        self.assertIn('corp.internal', module.values(self.config.read_bytes())['NO_PROXY'])
        with self.config.open('ab') as stream:
            stream.write(b'http_proxy=http://127.0.0.1:56\n')
        self.assertFalse(self.run_command('inspect')['effective'])


unittest.main(argv=[sys.argv[0]], verbosity=2)
