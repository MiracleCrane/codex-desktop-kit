"""Reconnect through Magpie's CLI, preserving the selected model and user limits."""
import argparse
import datetime
import json
import os
from pathlib import Path
import shutil
import subprocess
import tomllib
import csv
import io
import sys
from urllib.parse import urlparse


def clients_running():
    if sys.platform != 'win32':
        return True
    tasklist = Path(os.environ['SystemRoot']) / 'System32/tasklist.exe'
    for name in ('codex.exe', 'ChatGPT.exe'):
        result = subprocess.run([str(tasklist), '/FI', 'IMAGENAME eq ' + name, '/FO', 'CSV', '/NH'], capture_output=True, timeout=10, creationflags=subprocess.CREATE_NO_WINDOW)
        if result.returncode:
            return True
        for row in csv.reader(io.StringIO(result.stdout.decode(errors='replace'))):
            if row and row[0].lower() == name.lower():
                return True
    return False


def reconnect(config_path, executable, expected_url, run=subprocess.run):
    config_path = Path(config_path)
    u = urlparse(expected_url)
    if u.scheme != 'http' or u.hostname not in ('localhost', '127.0.0.1', '::1') or not u.port or u.username or u.password or u.query or u.fragment or u.path.rstrip('/') != '/backend-api/codex':
        raise ValueError('Expected endpoint must be the local Magpie gateway.')
    before = tomllib.loads(config_path.read_text(encoding='utf-8-sig'))
    if before.get('model_provider') not in (None, 'openai'):
        raise ValueError('A different provider is selected; reconnect it explicitly in Magpie.')
    if before.get('openai_base_url') not in (None, '', expected_url):
        raise ValueError('Another model endpoint is configured; it was preserved.')
    model = before.get('model')
    if not isinstance(model, str) or not model or any(c.isspace() for c in model):
        raise ValueError('Select a model in Magpie once before enabling automatic reconnect.')
    if '/' not in model and not model.startswith('gpt-'):
        raise ValueError('The native model cannot be mapped safely; select it in Magpie once.')
    backup = config_path.parent / 'config-backups' / ('before-magpie-reconnect-' + datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f') + '.toml')
    backup.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(config_path, backup)
    env = dict(os.environ, CODEX_HOME=str(config_path.parent))
    routed = model if '/' in model else 'codex/' + model
    # Picking a namespaced Magpie model uses its own ConnectHow path.
    # Once joined, picking the same native name retains the connection.
    picks = [routed] if routed == model else [routed, model]
    for pick in picks:
        result = run([str(executable), 'codex', 'model', pick], env=env, capture_output=True, timeout=40,
                     creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
        if result.returncode:
            raise RuntimeError('Magpie reconnect failed; configuration backup was retained.')
    after = tomllib.loads(config_path.read_text(encoding='utf-8-sig'))
    for key in ('model', 'model_reasoning_effort', 'model_context_window', 'model_auto_compact_token_limit'):
        if after.get(key) != before.get(key):
            raise RuntimeError('Magpie changed a protected user setting; inspect the retained backup.')
    if after.get('features', {}).get('async_compaction') != before.get('features', {}).get('async_compaction'):
        raise RuntimeError('Background compaction settings changed; inspect the retained backup.')
    if after.get('openai_base_url', '').rstrip('/') != expected_url.rstrip('/'):
        raise RuntimeError('Magpie did not restore the expected endpoint.')


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--config', required=True)
    p.add_argument('--magpie', required=True)
    p.add_argument('--expected-base-url', required=True)
    args = p.parse_args()
    try:
        def guarded_run(*command, **options):
            if clients_running():
                raise RuntimeError('Close Codex before reconnecting its shared configuration.')
            return subprocess.run(*command, **options)
        if clients_running():
            raise RuntimeError('Close Codex before reconnecting its shared configuration.')
        reconnect(args.config, args.magpie, args.expected_base_url, run=guarded_run)
        print(json.dumps({'connected': True}))
    except Exception:
        print(json.dumps({'connected': False, 'error': 'Reconnect failed; settings and backup require inspection.'}))
        raise SystemExit(1)


if __name__ == '__main__':
    main()
