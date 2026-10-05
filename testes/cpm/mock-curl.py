#!/usr/bin/env python3
"""Unit-only transport double; no TLS keys and never shipped in rootfs."""
import os
import pathlib
import sys
import time
import urllib.parse

args = sys.argv[1:]
assert '-k' not in args and '--insecure' not in args
assert args[args.index('--proto') + 1] == '=https'
assert args[args.index('--proto-redir') + 1] == '=https'
url = next(x for x in args if x.startswith('https://'))
path = urllib.parse.urlsplit(url).path.lstrip('/')
assert '..' not in pathlib.PurePosixPath(path).parts
source = pathlib.Path(os.environ['CPM_TEST_SERVER']) / path
output = pathlib.Path(args[args.index('--output') + 1])
if os.environ.get('CPM_TEST_DELAY'):
    pathlib.Path(os.environ['CPM_TEST_MARKER']).touch()
    time.sleep(float(os.environ['CPM_TEST_DELAY']))
if source.is_file():
    output.write_bytes(source.read_bytes())
    if '--write-out' in args:
        print('200', end='')
else:
    output.write_bytes(b'')
    if '--write-out' in args:
        print('404', end='')
    else:
        sys.exit(22)
