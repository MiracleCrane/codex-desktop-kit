"""Own one marked proxy block in Codex .env; preserve all other bytes."""
import argparse
import ctypes
import hashlib
import json
import os
from pathlib import Path
import re
from urllib.parse import urlparse

KEYS = ('HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY', 'NO_PROXY', 'NODE_USE_ENV_PROXY')


class Conflict(ValueError):
    pass


def digest(data):
    return hashlib.sha256(data).hexdigest()


def commit(path, expected, data):
    if os.name != 'nt':
        raise Conflict('Windows is required for the configuration transaction')
    import msvcrt
    path.parent.mkdir(parents=True, exist_ok=True)
    create = ctypes.WinDLL('kernel32', use_last_error=True).CreateFileW
    create.argtypes = [ctypes.c_wchar_p, ctypes.c_uint32, ctypes.c_uint32,
                       ctypes.c_void_p, ctypes.c_uint32, ctypes.c_uint32, ctypes.c_void_p]
    create.restype = ctypes.c_void_p
    handle = create(str(path), 0xC0000000, 0, None, 3 if path.exists() else 1, 0x80, None)
    if handle == ctypes.c_void_p(-1).value:
        raise Conflict('Configuration is busy; no concurrent writer was overwritten')
    with os.fdopen(msvcrt.open_osfhandle(handle, os.O_RDWR | os.O_BINARY), 'r+b') as stream:
        before = stream.read()
        if digest(before) != expected:
            raise Conflict('Configuration changed before commit')
        try:
            stream.seek(0)
            stream.write(data)
            stream.truncate()
            stream.flush()
            os.fsync(stream.fileno())
        except BaseException:
            stream.seek(0)
            stream.write(before)
            stream.truncate()
            stream.flush()
            os.fsync(stream.fileno())
            raise


def values(data):
    result = {}
    for line in data.decode('utf-8-sig').splitlines():
        match = re.match(r'^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$', line)
        if not match or match[1].upper() not in KEYS:
            continue
        raw = match[2]
        if raw.startswith('"'):
            value, end = json.JSONDecoder().raw_decode(raw)
            if raw[end:].strip() and not raw[end:].lstrip().startswith('#'):
                raise Conflict('Unsupported existing proxy expression')
        elif raw.startswith("'") and "'" in raw[1:]:
            value, tail = raw[1:].split("'", 1)
            if tail.strip() and not tail.lstrip().startswith('#'):
                raise Conflict('Unsupported existing proxy expression')
        else:
            value = re.split(r'\s+#', raw, maxsplit=1)[0].strip()
        if not isinstance(value, str) or '$' in value or '\n' in value or '\r' in value:
            raise Conflict('Existing proxy expression needs explicit review')
        result[match[1].upper()] = value
    return result


def main():
    p = argparse.ArgumentParser()
    p.add_argument('action', choices=('prepare', 'apply', 'inspect', 'check-restore', 'restore'))
    p.add_argument('--state', required=True)
    p.add_argument('--config')
    p.add_argument('--proxy')
    p.add_argument('--no-proxy', default='')
    p.add_argument('--instance')
    p.add_argument('--previous-state')
    a = p.parse_args()
    state_path = Path(a.state).resolve()
    if a.action == 'prepare':
        if state_path.exists():
            raise Conflict('Transaction already exists')
        u = urlparse(a.proxy or '')
        if (u.scheme != 'http' or u.hostname not in ('localhost', '127.0.0.1', '::1')
                or not u.port or u.username or u.password or u.query or u.fragment
                or u.path not in ('', '/')):
            raise Conflict('Use a local HTTP/mixed proxy without embedded credentials')
        if not re.fullmatch(r'[A-Za-z0-9-]{1,80}', a.instance or ''):
            raise Conflict('Invalid transaction identifier')
        config = Path(a.config).resolve()
        before = config.read_bytes() if config.exists() else b''
        current = values(before)
        replaced_block = b''
        base = before
        if a.previous_state:
            previous = json.loads(Path(a.previous_state).read_text(encoding='utf-8-sig'))
            replaced_block = previous['block'].encode()
            if Path(previous['config']).resolve() != config or before.count(replaced_block) != 1:
                raise Conflict('Previous installation no longer owns its proxy block')
            base = before.replace(replaced_block, b'', 1)
        if b'# >>> codex-desktop-kit proxy ' in base:
            raise Conflict('An existing kit block must be restored through its receipt first')
        bypass = []
        for value in ('localhost,127.0.0.1,::1', current.get('NO_PROXY', ''), a.no_proxy):
            for part in value.split(','):
                part = part.strip()
                if part and part not in bypass:
                    if any(c in part for c in '\r\n"\x00'):
                        raise Conflict('Invalid bypass entry')
                    bypass.append(part)
        selected = {key: a.proxy.rstrip('/') for key in KEYS[:3]}
        selected.update(NO_PROXY=','.join(bypass), NODE_USE_ENV_PROXY='1')
        newline = '\r\n' if b'\r\n' in before else '\n'
        block = (f'# >>> codex-desktop-kit proxy {a.instance} >>>' + newline
                 + newline.join(f'{key}={json.dumps(value)}' for key, value in selected.items())
                 + newline + f'# <<< codex-desktop-kit proxy {a.instance} <<<' + newline).encode()
        separator = b'' if not base or base.endswith(b'\n') else newline.encode()
        after = base + separator + block
        state_path.parent.mkdir(parents=True, exist_ok=True)
        backup = state_path.with_name('env.before')
        backup.write_bytes(before)
        state = dict(formatVersion=1, status='prepared', config=str(config), before=str(backup),
                     beforeSha256=digest(before), afterSha256=digest(after),
                     block=block.decode(), separator=separator.decode(), values=selected,
                     replacedBlock=replaced_block.decode())
    else:
        state = json.loads(state_path.read_text(encoding='utf-8-sig'))
        config = Path(state['config'])
        data = config.read_bytes() if config.exists() else b''
        block = state['block'].encode()
        if a.action == 'check-restore':
            allowed = state['status'] == 'restored' or (state['status'] == 'prepared' and block not in data) or data.count(block) == 1
            if not allowed:
                raise Conflict('Owned proxy block changed; preserve it for manual review')
            if digest(data) == state['afterSha256'] and digest(Path(state['before']).read_bytes()) != state['beforeSha256']:
                raise Conflict('Backup changed')
            print(json.dumps(dict(restorable=True)))
            return
        if a.action == 'inspect':
            print(json.dumps(dict(status=state['status'], ownsBlock=data.count(block) == 1,
                                  effective=values(data) == state['values'])))
            return
        if a.action == 'apply':
            if state['status'] == 'applied' and data.count(block) == 1 and values(data) == state['values']:
                print(json.dumps(dict(status='already_applied')))
                return
            if digest(data) != state['beforeSha256']:
                raise Conflict('Configuration changed after preparation')
            previous_block = state.get('replacedBlock', '').encode()
            base = data.replace(previous_block, b'', 1) if previous_block else data
            after = base + state['separator'].encode() + block
            if digest(after) != state['afterSha256']:
                raise Conflict('Prepared transaction changed')
            commit(config, digest(data), after)
            state['status'] = 'applied'
        else:
            if state['status'] == 'restored':
                print(json.dumps(dict(status='already_restored')))
                return
            if state['status'] == 'prepared' and block not in data:
                state['status'] = 'restored'
            else:
                if data.count(block) != 1:
                    raise Conflict('Owned proxy block changed; preserve it for manual review')
                if digest(data) == state['afterSha256']:
                    restored = Path(state['before']).read_bytes()
                    if digest(restored) != state['beforeSha256']:
                        raise Conflict('Backup changed')
                else:
                    restored = data.replace(block, state.get('replacedBlock', '').encode(), 1)
                commit(config, digest(data), restored)
                state['status'] = 'restored'
    temporary = state_path.with_suffix('.tmp')
    temporary.write_text(json.dumps(state, indent=2) + '\n', encoding='utf-8')
    os.replace(temporary, state_path)
    print(json.dumps(dict(status=state['status'])))


if __name__ == '__main__':
    try:
        main()
    except Exception as exc:
        print(json.dumps(dict(status='failed', error=str(exc) if isinstance(exc, Conflict) else type(exc).__name__)))
        raise SystemExit(1)
