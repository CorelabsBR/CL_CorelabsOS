#!/bin/sh
set -eu
[ "$(id -u)" -eq 0 ]
base=/tmp/cpm-fixtures
mkdir -p "$base"
for file in index cpm-abi-test.cpm curl; do
    /usr/bin/curl --fail --max-time 20 "http://10.0.2.2:18991/compilacao/cpm-vm-fixtures/$file" -o "$base/$file"
done
chmod 755 "$base/curl"
# Raiz isolada e nova: o transporte é um double local, não o archive oficial.
CPM_ROOT=$(mktemp -d /tmp/cpm-vm.XXXXXX)
export CPM_ROOT
mkdir -p "$CPM_ROOT/etc/cpm/repos.d"
printf '[fixture]\nServer = https://fixtures.invalid/$arch\nEnabled = yes\nSigLevel = Optional\n' > "$CPM_ROOT/etc/cpm/repos.d/fixture.repo"
PATH="$base:$PATH"
export PATH
cpm update
cpm search DInAMICA
cpm info cpm-abi-test
cpm install cpm-abi-test
cpm list | grep '^cpm-abi-test 1.0-1$'
cpm info cpm-abi-test | grep 'Installed: yes'
/lib64/ld-linux-x86-64.so.2 --list "$CPM_ROOT/usr/bin/hello-cpm"
"$CPM_ROOT/usr/bin/hello-cpm"
cpm remove cpm-abi-test
[ ! -e "$CPM_ROOT/usr/bin/hello-cpm" ]
[ ! -e "$CPM_ROOT/var/lib/cpm/db/installed/cpm-abi-test" ]
[ ! -s "$CPM_ROOT/var/lib/cpm/db/ownership" ]
[ "$(cpm list | wc -l)" -eq 0 ]
echo CPM_VM_INSTALACAO_REMOCAO_OK
