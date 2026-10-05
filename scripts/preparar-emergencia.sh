#!/usr/bin/env bash
set -Eeuo pipefail

RAIZ="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"

# shellcheck source=biblioteca.sh
source "$RAIZ/scripts/biblioteca.sh"

for comando in cpio gzip; do
    exigir_comando "$comando"
done

busybox="$COMPILACAO/rootfs/bin/busybox"
origem_init="$RAIZ/sistema-emergencia/init"
destino="$IMAGENS/corelabs-emergency.cpio.gz"
temporario="$COMPILACAO/emergencia.tmp"

[[ -x "$busybox" ]] ||
    erro "BusyBox do rootfs ausente"

[[ -x "$origem_init" ]] ||
    erro "init de emergência ausente"

rm -rf -- "$temporario"
mkdir -p -- \
    "$temporario/bin" \
    "$temporario/sbin" \
    "$temporario/dev/pts" \
    "$temporario/proc" \
    "$temporario/sys" \
    "$temporario/run" \
    "$temporario/root" \
    "$temporario/mnt/root"

cp -- "$busybox" "$temporario/bin/busybox"
cp -- "$origem_init" "$temporario/init"

chmod 0755 \
    "$temporario/init" \
    "$temporario/bin/busybox"

for applet in \
    sh ash \
    cat echo ls mkdir \
    mount umount \
    dmesg grep sleep sync setsid cttyhack tty id ps
do
    ln -s busybox "$temporario/bin/$applet"
done

for applet in \
    blkid fdisk fsck mdev \
    reboot poweroff
do
    ln -s ../bin/busybox "$temporario/sbin/$applet"
done

mkdir -p -- "$IMAGENS"

(
    cd "$temporario"
    find . -print0 |
        LC_ALL=C sort -z |
        cpio --null -o --format=newc --owner=0:0 2>/dev/null |
        gzip -9
) > "${destino}.tmp"

mv -- "${destino}.tmp" "$destino"
rm -rf -- "$temporario"

mensagem "Initramfs de emergência criado: $destino"
