#!/usr/bin/env bash
set -Eeuo pipefail

RAIZ="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"

# shellcheck source=biblioteca.sh
source "$RAIZ/scripts/biblioteca.sh"

for comando in cpio gzip; do
    exigir_comando "$comando"
done

busybox="$COMPILACAO/rootfs/bin/busybox"
destino="$IMAGENS/corelabs-inspecao.cpio.gz"
ambiente="$COMPILACAO/inspecao"
temporario="${destino}.tmp"

[[ -x "$busybox" ]] ||
    erro "BusyBox do rootfs ausente; execute ./corelabs.sh rootfs"

mensagem "Preparando ambiente mínimo de inspeção"

rm -rf -- "$ambiente"
mkdir -p -- \
    "$ambiente/bin" \
    "$ambiente/sbin" \
    "$ambiente/dev" \
    "$ambiente/proc" \
    "$ambiente/sys"

install -m 0755 -- "$busybox" "$ambiente/bin/busybox"

for applet in sh mount umount sync; do
    ln -s busybox "$ambiente/bin/$applet"
done

for applet in fdisk blkid; do
    ln -s ../bin/busybox "$ambiente/sbin/$applet"
done

cat > "$ambiente/init" <<'INIT'
#!/bin/sh

export PATH=/sbin:/bin
export HOME=/root
export TERM="${TERM:-vt100}"

falha() {
    codigo="$1"
    shift

    echo "ERRO_INSPECAO_CORELABS: $*"
    sync
    /bin/busybox poweroff -f
    exit "$codigo"
}

mount -t proc proc /proc ||
    falha 10 "não foi possível montar /proc"

mount -t sysfs sysfs /sys ||
    falha 11 "não foi possível montar /sys"

mount -t devtmpfs devtmpfs /dev ||
    falha 12 "não foi possível montar /dev"

echo "INICIO_INSPECAO_CORELABS"

if [ ! -b /dev/vda ]; then
    falha 20 "/dev/vda não está disponível"
fi

fdisk -l /dev/vda
resultado_fdisk=$?

blkid /dev/vda /dev/vda*
resultado_blkid=$?

echo "RESULTADO_FDISK_CORELABS=$resultado_fdisk"
echo "RESULTADO_BLKID_CORELABS=$resultado_blkid"
echo "FIM_INSPECAO_CORELABS"

sync

umount /sys 2>/dev/null || true
umount /proc 2>/dev/null || true

/bin/busybox poweroff -f

while :; do
    sleep 3600
done
INIT

chmod 0755 "$ambiente/init"

mkdir -p -- "$IMAGENS"

(
    cd "$ambiente"
    find . -print0 |
        LC_ALL=C sort -z |
        cpio --null -o --format=newc --owner=0:0 2>/dev/null |
        gzip -9
) > "$temporario"

mv -- "$temporario" "$destino"

mensagem "Initramfs de inspeção criado: $destino"
