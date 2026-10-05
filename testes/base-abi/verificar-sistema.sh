#!/bin/sh
set -eu

[ "$(cat /etc/hostname)" = corelabs ]
[ "$(uname -m)" = x86_64 ]
[ "$(id -u)" = 1000 ]
[ "$(id -g)" = 100 ]
id -Gn | grep -w wheel

/lib64/ld-linux-x86-64.so.2 --version
[ "$(getconf GNU_LIBC_VERSION)" = 'glibc 2.44' ]
/bin/bash --version
ls --version
sort --version
lsblk --version
uuidgen --version
lsblk -o NAME,TYPE,SIZE

[ "$(stat -c '%u:%g:%a' /bin/su)" = '0:0:4755' ]
[ "$(stat -c '%u:%g:%a' /bin/busybox)" = '0:0:755' ]
[ "$(stat -c '%u:%g:%a' /usr/bin/sudo)" = '0:0:4755' ]
[ "$(stat -c '%u:%g:%a' /etc/sudoers)" = '0:0:440' ]
[ "$(stat -c '%u:%g' /home/girelli)" = '1000:100' ]
getent passwd girelli
getent group wheel

[ "$(printf 'z\na\n' | sort)" = "$(printf 'a\nz\n')" ]
printf '' | sha256sum | grep '^e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
[ "$(printf 'A' | iconv -f UTF-8 -t UTF-16LE | od -An -tx1 | tr -d ' \n')" = 4100 ]
[ "$(getopt -o a: -- -a corelabs)" = " -a 'corelabs' --" ]
flock /tmp/corelabs-abi-flock sh -c 'echo CORELABS_FLOCK_OK'
uuidgen | grep -E '^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$'

cd /
sha256sum --check --status /usr/share/corelabs/base-abi-v1.sha256
/lib64/ld-linux-x86-64.so.2 --list /tmp/hello-corelabs
/lib64/ld-linux-x86-64.so.2 --list /tmp/hello-corelabs-cpp
/tmp/hello-corelabs --dns
/tmp/hello-corelabs-cpp

ip addr
ip route
cat /etc/resolv.conf
nslookup example.com
curl --fail --max-time 20 -o /dev/null -w 'HTTP %{http_code}\n' http://example.com
curl --fail --max-time 20 -o /dev/null -w 'HTTPS %{http_code}\n' https://example.com
if curl --max-time 20 -o /dev/null https://expired.badssl.com; then
    echo 'ERRO: certificado inválido foi aceito.' >&2
    exit 1
else
    codigo=$?
    [ "$codigo" = 60 ]
fi

echo CORELABS_BASE_ABI_V1_SISTEMA_OK
