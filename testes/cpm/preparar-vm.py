#!/usr/bin/env python3
"""Gera fixture/transport double para a VM; executado somente no host."""
import hashlib
import io
from pathlib import Path
import sys
import tarfile

repo = Path(__file__).resolve().parents[2]
out = Path(sys.argv[1]).resolve()
out.mkdir(parents=True, exist_ok=True)
manifest = b"Name=cpm-abi-test\nVersion=1.0\nRelease=1\nArchitecture=x86_64\n"
with tarfile.open(out / "cpm-abi-test.cpm", "w:gz", format=tarfile.USTAR_FORMAT) as tar:
    info = tarfile.TarInfo("CPM/MANIFEST")
    info.mode = 0o644
    info.size = len(manifest)
    tar.addfile(info, io.BytesIO(manifest))
    binary = (repo / "compilacao/testes-base-abi/hello-Lithos-cpp").read_bytes()
    info = tarfile.TarInfo("payload/usr/bin/hello-cpm")
    info.mode = 0o755
    info.size = len(binary)
    tar.addfile(info, io.BytesIO(binary))
package = (out / "cpm-abi-test.cpm").read_bytes()
(out / "index").write_text("cpm-abi-test|1.0|1|x86_64|cpm-abi-test.cpm|"
                          + hashlib.sha256(package).hexdigest()
                          + "|Fixture dinamica Lithos Base ABI v1\n")
# Esse double é explicitamente local; não representa transporte HTTPS real.
(out / "curl").write_text('''#!/bin/sh
set -eu
out= status= url=
while [ "$#" -gt 0 ]; do
    case "$1" in
        --output|-o) out=$2; shift 2;;
        --write-out|--writeout|-w) status=$2; shift 2;;
        --proto|--proto-redir|--connect-timeout|--max-time|--max-filesize) shift 2;;
        https://fixtures.invalid/*) url=$1; shift;;
        --*) shift;;
        *) exec /usr/bin/curl "$@";;
    esac
done
case "$url" in
    *.sig) : > "$out"; printf 404;;
    */index) cp /tmp/cpm-fixtures/index "$out";;
    */packages/cpm-abi-test.cpm) cp /tmp/cpm-fixtures/cpm-abi-test.cpm "$out";;
    *) exit 1;;
esac
''')
print(out)
