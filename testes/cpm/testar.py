#!/usr/bin/env python3
"""Rootless, isolated integration tests. Python is used ONLY on the host."""
import gzip
import hashlib
import io
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import time

REPO = Path(__file__).resolve().parents[2]
AREA = Path(tempfile.mkdtemp(prefix='cpm-testes.', dir=REPO / 'compilacao'))
ROOT = AREA / 'root'
SERVER = AREA / 'server/x86_64'
BIN = AREA / 'bin'
ROOT.mkdir(mode=0o755)
SERVER.mkdir(parents=True)
BIN.mkdir()
for name, source in [('curl', 'mock-curl.py'), ('id', 'mock-id.sh'), ('stat', 'mock-stat.sh')]:
    shutil.copyfile(REPO / 'testes/cpm' / source, BIN / name)
    (BIN / name).chmod(0o755)
ENV = dict(os.environ, PATH=f'{BIN}:{os.environ["PATH"]}', CPM_ROOT=str(ROOT),
           CPM_ARCHIVER=str(REPO / 'compilacao/cpm/arquivo-host-testes'), CPM_TEST_SERVER=str(SERVER.parent))
CONFIG = ROOT / 'etc/cpm/repos.d/corelabs.repo'
CONFIG.parent.mkdir(parents=True)
CONFIG.write_text('[corelabs]\n Server = https://fixtures.invalid/$arch\nEnabled = yes\nSigLevel = Optional\n')
CPM = ['sh', str(REPO / 'sistema/usr/bin/cpm')]
INDEX = SERVER / 'index'
INDEX.write_bytes(b'')
tests = 0

def run(*args, ok=True, text=None, env=None):
    global tests
    p = subprocess.run(CPM + list(args), env=env or ENV, capture_output=True, text=True, timeout=20)
    if (p.returncode == 0) != ok or (text and text not in p.stdout + p.stderr):
        raise AssertionError(f'{args}: exit={p.returncode}\n{p.stdout}{p.stderr}')
    tests += 1
    print('OK', *args, 'aceito' if ok else 'rejeitado')
    return p

def db_snapshot():
    base = ROOT / 'var/lib/cpm/db'
    return {str(p.relative_to(base)): p.read_bytes() for p in base.rglob('*') if p.is_file()}

def package(name='teste', mode='valid', dest='usr/share/teste/message.txt', manifest_name=None):
    manifest = f'Name = {manifest_name or name}\nVersion = 1.0\nRelease = 1\nArchitecture = x86_64\nDepends =\nProvides =\nConflicts =\nReplaces =\n'
    raw = io.BytesIO()
    with tarfile.open(fileobj=raw, mode='w', format=tarfile.USTAR_FORMAT) as tar:
        def add(path, data=b'fixture\n', kind=tarfile.REGTYPE, target=''):
            t = tarfile.TarInfo(path)
            t.mode = 0o755 if kind == tarfile.DIRTYPE else 0o777 if kind == tarfile.SYMTYPE else 0o644
            t.type = kind
            t.linkname = target
            t.size = len(data) if kind == tarfile.REGTYPE else 0
            tar.addfile(t, io.BytesIO(data) if t.size else None)
        if mode != 'missing':
            add('CPM/MANIFEST', manifest.encode())
        add('payload/' + dest)
        if mode == 'traversal': add('payload/../../escape')
        if mode == 'absolute': add('/tmp/escape')
        if mode == 'symlink': add('payload/usr/share/escape', kind=tarfile.SYMTYPE, target='../../../escape')
        if mode == 'hardlink': add('payload/usr/share/escape', kind=tarfile.LNKTYPE, target='/etc/shadow')
        if mode == 'fifo': add('payload/usr/share/escape', kind=tarfile.FIFOTYPE)
        if mode == 'device': add('payload/usr/share/escape', kind=tarfile.CHRTYPE)
        if mode == 'outside': add('CPM/hook', b'#!/bin/sh\nexit 1\n')
        if mode == 'ancestor':
            add('payload/usr/share/alias', kind=tarfile.SYMTYPE, target='teste')
            add('payload/usr/share/alias/out')
        if mode == 'safe-link': add('payload/usr/share/teste/link', kind=tarfile.SYMTYPE, target='message.txt')
        if mode == 'duplicate': add('payload/' + dest)
    data = gzip.compress(raw.getvalue(), mtime=0)
    if mode == 'truncated': data = data[:20]
    filename = f'{name}-1.0-1-x86_64.cpm'
    target = SERVER / 'packages' / filename
    target.parent.mkdir(exist_ok=True)
    target.write_bytes(data)
    digest = hashlib.sha256(data).hexdigest()
    return f'{name}|1.0|1|x86_64|{filename}|{digest}|Pacote TESTE\n'

try:
    run('--version', text='CPM 0.2')
    run('--help', text='remove')
    run('update')
    run('search', 'fastfetch')
    run('list')
    run('install', 'inexistente', ok=False)
    before = (ROOT / 'var/lib/cpm/repos/corelabs/index').read_bytes()
    valid = package(mode='safe-link')
    for bad in ['x|y\n', valid.replace('x86_64|', 'aarch64|', 1), valid.replace('teste|', '../escape|', 1),
                valid.replace('teste-1.0-1-x86_64.cpm', '../escape.cpm'), valid.replace('|1|', '|0|', 1)]:
        INDEX.write_text(bad)
        run('update', ok=False)
        assert (ROOT / 'var/lib/cpm/repos/corelabs/index').read_bytes() == before
    INDEX.write_text(valid)
    run('update')
    run('search', 'TeStE', text='teste 1.0-1')
    run('info', 'teste', text='Installed: no')
    run('install', 'teste')
    assert (ROOT / 'usr/share/teste/link').is_symlink()
    run('list', text='teste 1.0-1')
    run('info', 'teste', text='Installed: yes')
    run('install', 'teste', ok=False)
    # Ownership collision, while the first package remains installed.
    INDEX.write_text(package('outro', dest='usr/share/teste/message.txt'))
    run('update')
    snap = db_snapshot()
    run('install', 'outro', ok=False, text='ownership')
    assert db_snapshot() == snap
    # Corrupted removal must not touch root, even with a recalculated files hash.
    installed = ROOT / 'var/lib/cpm/db/installed/teste'
    original_files = (installed / 'files').read_bytes()
    original_desc = (installed / 'desc').read_bytes()
    bad_files = b'd|/|1|1\n'
    (installed / 'files').write_bytes(bad_files)
    digest = hashlib.sha256(bad_files).hexdigest()
    lines = original_desc.decode().splitlines()
    (installed / 'desc').write_text('\n'.join('FilesSHA256 = ' + digest if x.startswith('FilesSHA256') else x for x in lines) + '\n')
    run('remove', 'teste', ok=False)
    assert (ROOT / 'usr/share/teste/message.txt').exists()
    (installed / 'files').write_bytes(original_files)
    (installed / 'desc').write_bytes(original_desc)
    run('remove', 'teste')
    assert not (ROOT / 'usr/share/teste').exists()
    run('list')
    for mode in ['missing', 'truncated', 'traversal', 'absolute', 'symlink', 'hardlink',
                 'fifo', 'device', 'outside', 'ancestor', 'duplicate', 'manifest', 'sha']:
        line = package(mode=mode, manifest_name='errado' if mode == 'manifest' else None)
        if mode == 'sha': line = line.replace(line.split('|')[5], '0' * 64)
        INDEX.write_text(line)
        run('update')
        snap = db_snapshot()
        run('install', 'teste', ok=False)
        assert db_snapshot() == snap and not (ROOT / 'usr/share/teste/message.txt').exists()
    # Existing unmanaged file and symlink ancestor.
    INDEX.write_text(package())
    run('update')
    (ROOT / 'usr/share/teste').mkdir(parents=True, mode=0o755)
    (ROOT / 'usr/share').chmod(0o755)
    (ROOT / 'usr/share/teste/message.txt').write_text('unmanaged')
    run('install', 'teste', ok=False, text='unmanaged')
    assert (ROOT / 'usr/share/teste/message.txt').read_text() == 'unmanaged'
    (ROOT / 'usr/share/teste/message.txt').unlink()
    (ROOT / 'usr/share/teste').rmdir()
    (ROOT / 'usr/share/teste').symlink_to(AREA)
    run('install', 'teste', ok=False)
    assert not (AREA / 'message.txt').exists()
    (ROOT / 'usr/share/teste').unlink()
    # Required closed, Optional-present signature closed, disabled repo ignored.
    oldconf = CONFIG.read_text()
    CONFIG.write_text(oldconf.replace('Optional', 'Required'))
    run('update', ok=False, text='Required')
    CONFIG.write_text(oldconf)
    (SERVER / 'index.sig').write_text('not a signature')
    run('update', ok=False, text='assinatura presente')
    (SERVER / 'index.sig').unlink()
    CONFIG.write_text(oldconf + '\n[disabled]\nEnabled = no\nServer = $(touch /tmp/evil)\n')
    run('update')
    CONFIG.write_text(oldconf.replace('https://fixtures.invalid/$arch', 'https://fixtures.invalid/$(id)'))
    run('update', ok=False)
    CONFIG.write_text(oldconf)
    run('update', ok=False, env=dict(ENV, CPM_TEST_UID='1000'), text='requer root')
    run('search', 'teste', env=dict(ENV, CPM_TEST_UID='1000'))
    run('info', 'teste', env=dict(ENV, CPM_TEST_UID='1000'))
    run('list', env=dict(ENV, CPM_TEST_UID='1000'))
    # Concurrent mutation: a real flock, not a mocked lock.
    marker = AREA / 'network.started'
    delayed = subprocess.Popen(CPM + ['update'], env=dict(ENV, CPM_TEST_DELAY='2', CPM_TEST_MARKER=str(marker)),
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    deadline = time.monotonic() + 5
    while not marker.exists() and time.monotonic() < deadline: time.sleep(0.02)
    assert marker.exists()
    run('update', ok=False, text='operação CPM')
    out, err = delayed.communicate(timeout=10)
    assert delayed.returncode == 0, out + err
    # Database commit failure: intercept only publish rename; undo must restore payload + DB.
    shutil.copyfile(REPO / 'testes/cpm/mock-mv.sh', BIN / 'mv')
    (BIN / 'mv').chmod(0o755)
    snap = db_snapshot()
    run('install', 'teste', ok=False)
    assert db_snapshot() == snap and not (ROOT / 'usr/share/teste').exists()
    (BIN / 'mv').unlink()
    # An interrupted process leaves WAL pending; next mutation recovers first.
    shutil.copyfile(REPO / 'testes/cpm/mock-mv.sh', BIN / 'mv')
    (BIN / 'mv').chmod(0o755)
    run('install', 'teste', ok=False, env=dict(ENV, CPM_TEST_CRASH='1'))
    assert list((ROOT / 'var/lib/cpm/transactions').iterdir())
    (BIN / 'mv').unlink()
    run('update', text='recuperando transação')
    assert db_snapshot() == snap and not (ROOT / 'usr/share/teste').exists()
    run('install', 'teste')
    snap = db_snapshot()
    shutil.copyfile(REPO / 'testes/cpm/mock-mv.sh', BIN / 'mv')
    (BIN / 'mv').chmod(0o755)
    run('remove', 'teste', ok=False, env=dict(ENV, CPM_TEST_FAIL_REMOVE='1'))
    assert db_snapshot() == snap and (ROOT / 'usr/share/teste/message.txt').exists()
    run('remove', 'teste', ok=False, env=dict(ENV, CPM_TEST_CRASH_REMOVE='1'))
    (BIN / 'mv').unlink()
    run('update', text='recuperando transação')
    assert db_snapshot() == snap and (ROOT / 'usr/share/teste/message.txt').exists()
    run('remove', 'teste')
    assert not list((ROOT / 'var/lib/cpm/transactions').iterdir())
    # Partial publication failure must restore BOTH repository indices.
    CONFIG.write_text(oldconf + '\n[second]\nServer=https://fixtures.invalid/$arch\nEnabled=yes\nSigLevel=Optional\n')
    run('update')
    indices_before = {p: p.read_bytes() for p in (ROOT / 'var/lib/cpm/repos').glob('*/index')}
    INDEX.write_bytes(b'')
    shutil.copyfile(REPO / 'testes/cpm/mock-mv.sh', BIN / 'mv')
    (BIN / 'mv').chmod(0o755)
    run('update', ok=False, env=dict(ENV, CPM_TEST_FAIL_INDEX='1'))
    assert all(p.read_bytes() == value for p, value in indices_before.items())
    (BIN / 'mv').unlink()
    CONFIG.write_text(oldconf)
    INDEX.write_bytes(b'\0')
    run('update', ok=False)
    for operation in ['install', 'remove']:
        run(operation, 'teste', ok=False, env=dict(ENV, CPM_TEST_UID='1000'), text='requer root')
    print(f'CPM_UNITARIOS_OK: {tests} verificações; artefatos em {AREA}')
finally:
    # Preserve fixtures/loggable state for inspection; no deletion of user data.
    print('Área descartável preservada:', AREA)
