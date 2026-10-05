#!/usr/bin/env bash
set -Eeuo pipefail
RAIZ="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=biblioteca.sh
source "$RAIZ/scripts/biblioteca.sh"

for comando in cpio gzip; do exigir_comando "$comando"; done
rootfs="$COMPILACAO/rootfs"
destino="$IMAGENS/Lithos-initramfs.cpio.gz"
[[ -x "$rootfs/init" && -x "$rootfs/bin/busybox" ]] || erro "rootfs ausente; execute ./Lithos.sh rootfs"
mkdir -p -- "$IMAGENS"
temporario="${destino}.tmp"
mensagem "Empacotando initramfs"
find "$rootfs" -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +
(
    cd "$rootfs"
    find . -print0 | LC_ALL=C sort -z | cpio --reproducible --null -o --format=newc --owner=0:0 2>/dev/null | gzip -n -9
) > "$temporario"
mv -- "$temporario" "$destino"
mensagem "Initramfs criado: $destino"
