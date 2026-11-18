"""Report route categories, never authentication or full configuration."""
import argparse
import json
from pathlib import Path
import tomllib
from urllib.parse import urlparse

p = argparse.ArgumentParser()
p.add_argument('--config', required=True)
p.add_argument('--expected-base-url')
a = p.parse_args()
try:
    path = Path(a.config)
    config = tomllib.loads(path.read_text(encoding='utf-8-sig')) if path.exists() else {}
    value = config.get('openai_base_url')
    route = 'default'
    if value:
        u = urlparse(value)
        route = 'local-override' if u.hostname in ('localhost', '127.0.0.1', '::1') else 'remote-override'
    custom = config.get('model_provider') not in (None, 'openai')
    safe_base = None
    if value and u.scheme == 'http' and u.hostname in ('localhost', '127.0.0.1', '::1') and not (u.username or u.password or u.query or u.fragment):
        if u.port and u.path.rstrip('/') == '/backend-api/codex':
            host = '[' + u.hostname + ']' if ':' in u.hostname else u.hostname
            safe_base = f'http://{host}:{u.port}/backend-api/codex'
    catalog = config.get('model_catalog_json')
    catalog_exists = True
    if catalog:
        catalog_path = Path(catalog)
        if not catalog_path.is_absolute():
            catalog_path = path.parent / catalog_path
        catalog_exists = catalog_path.is_file()
    result = dict(route=route, customProvider=custom, baseUrl=safe_base, catalogExists=catalog_exists)
    if a.expected_base_url:
        expected = urlparse(a.expected_base_url)
        if expected.scheme != 'http' or expected.hostname not in ('localhost', '127.0.0.1', '::1') or not expected.port or expected.username or expected.password or expected.query or expected.fragment or expected.path.rstrip('/') != '/backend-api/codex':
            raise ValueError('Invalid expected Magpie URL')
        host = '[' + expected.hostname + ']' if ':' in expected.hostname else expected.hostname
        expected_base = f'http://{host}:{expected.port}/backend-api/codex'
        result['matchesExpected'] = not custom and safe_base == expected_base
    print(json.dumps(result))
except Exception:
    print(json.dumps(dict(error='Cannot inspect Codex route safely')))
    raise SystemExit(1)
