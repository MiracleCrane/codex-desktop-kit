"""Report route categories, never authentication or full configuration."""
import argparse
import json
from pathlib import Path
import tomllib
from urllib.parse import urlparse

p = argparse.ArgumentParser()
p.add_argument('--config', required=True)
a = p.parse_args()
try:
    path = Path(a.config)
    config = tomllib.loads(path.read_text(encoding='utf-8-sig')) if path.exists() else {}
    value = config.get('openai_base_url')
    route = 'default'
    if value:
        u = urlparse(value)
        route = 'local-override' if u.hostname in ('localhost', '127.0.0.1', '::1') else 'remote-override'
    print(json.dumps(dict(route=route, customProvider=bool(config.get('model_provider') not in (None, 'openai')))))
except Exception:
    print(json.dumps(dict(error='Cannot inspect Codex route safely')))
    raise SystemExit(1)
