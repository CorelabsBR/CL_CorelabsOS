#!/usr/bin/env bash
set -Eeuo pipefail
RAIZ="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=biblioteca.sh
source "$RAIZ/scripts/biblioteca.sh"

for comando in cpio gzip; do exigir_comando "$comando"; done
rootfs="$COMPILACAO/rootfs"
destino="$IMAGENS/corelabs-initramfs.cpio.gz"
[[ -x "$rootfs/init" && -x "$rootfs/bin/busybox" ]] || erro "rootfs ausente; execute ./corelabs.sh rootfs"
mkdir -p -- "$IMAGENS"
temporario="${destino}.tmp"
mensagem "Empacotando initramfs"
(
    cd "$rootfs"
    find . -print0 | LC_ALL=C sort -z | cpio --null -o --format=newc --owner=0:0 2>/dev/null | gzip -9
) > "$temporario"
mv -- "$temporario" "$destino"
mensagem "Initramfs criado: $destino"

