#!/usr/bin/env bash
set -Eeuo pipefail

RAIZ="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"

source "$RAIZ/scripts/biblioteca.sh"
source "$RAIZ/configuracao/vm.conf"

DESTINO="$COMPILACAO/atualizacao-sentinel"
PACOTE="$DESTINO.tmp/opt/corelabs-sentinel"

ASSINATURA_INIT="d0994abd9c2f74f360154286dd65b511ce19cd3c31ef0a6191041c929459f269"

"$RAIZ/scripts/rootfs.sh"

SUPERVISOR="$COMPILACAO/rootfs/usr/bin/clsupervisor"

ASSINATURA_SUPERVISOR="$(
    sha256sum "$SUPERVISOR" |
        cut -d ' ' -f 1
)"

rm -rf -- "$DESTINO.tmp"

mkdir -p \
    "$DESTINO.tmp"/{dev,proc,sys,run,tmp,root,mnt,etc,usr,var,home} \
    "$PACOTE"

make -C "$FONTES/busybox-$BUSYBOX_VERSAO" \
    O="$COMPILACAO/busybox" \
    CONFIG_PREFIX="$DESTINO.tmp" \
    install >/dev/null

cp \
    "$RAIZ/sistema-atualizador/sentinel/init" \
    "$DESTINO.tmp/init"

sed -i \
    -e "s/@RAIZ_UUID@/$VM_RAIZ_UUID/g" \
    -e "s/@ASSINATURA_INIT@/$ASSINATURA_INIT/g" \
    -e "s/@ASSINATURA_SUPERVISOR@/$ASSINATURA_SUPERVISOR/g" \
    "$DESTINO.tmp/init"

cp "$SUPERVISOR" "$PACOTE/clsupervisor"

cp \
    "$RAIZ/sistema/usr/lib/os-release" \
    "$PACOTE/os-release"

cp \
    "$RAIZ/sistema/etc/motd" \
    "$PACOTE/motd"

chmod 0755 \
    "$DESTINO.tmp/init" \
    "$PACOTE/clsupervisor"

mkdir -p "$IMAGENS"

(
    cd "$DESTINO.tmp"

    find . -print0 |
        LC_ALL=C sort -z |
        cpio --null -o --format=newc --owner=0:0 2>/dev/null |
        gzip -9
) > "$IMAGENS/corelabs-atualizacao-sentinel.cpio.gz"

rm -rf -- "$DESTINO"
mv -- "$DESTINO.tmp" "$DESTINO"

echo "[Sentinel] Pacote preparado."
echo "[Sentinel] SHA-256: $ASSINATURA_SUPERVISOR"
