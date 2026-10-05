#!/usr/bin/env bash
set -Eeuo pipefail
RAIZ="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=biblioteca.sh
source "$RAIZ/scripts/biblioteca.sh"
# shellcheck source=../configuracao/vm.conf
source "$RAIZ/configuracao/vm.conf"

for comando in cpio gzip make sed; do exigir_comando "$comando"; done
"$RAIZ/scripts/rootfs.sh"
"$RAIZ/scripts/initramfs.sh"
destino="$COMPILACAO/atualizacao-identidade"
rm -rf -- "$destino.tmp"
mkdir -p -- "$destino.tmp"/{dev,proc,sys,run,tmp,root,mnt,etc,usr,var,home,opt/Lithos-identidade}
make -C "$FONTES/busybox-$BUSYBOX_VERSAO" O="$COMPILACAO/busybox" \
    CONFIG_PREFIX="$destino.tmp" install >/dev/null
cp -- "$RAIZ/sistema-atualizador/init" "$destino.tmp/init"
sed -i "s/@RAIZ_UUID@/$VM_RAIZ_UUID/g" "$destino.tmp/init"
chmod 0755 "$destino.tmp/init"

payload="$destino.tmp/opt/Lithos-identidade"
mkdir -p -- "$payload/usr/lib/Lithos" "$payload/usr/share/pixmaps" "$payload/etc/Lithos"
cp -- "$RAIZ/sistema/usr/lib/os-release" "$payload/usr/lib/os-release"
cp -- "$RAIZ/sistema/usr/lib/Lithos/banner" "$payload/usr/lib/Lithos/banner"
cp -- "$RAIZ/branding/system/ascii.txt" "$payload/etc/Lithos/logo.ascii"
cp -- "$RAIZ/branding/system/oslogo.svg" "$payload/usr/share/pixmaps/Lithos-logo.svg"
cp -- "$RAIZ/sistema/etc/Lithos/banner.conf" "$payload/etc/Lithos/banner.conf"
cp -- "$RAIZ/sistema/etc/issue" "$payload/etc/issue"
cp -- "$RAIZ/sistema/etc/motd" "$payload/etc/motd"
cp -- "$RAIZ/sistema/init" "$payload/init"

(
    cd "$destino.tmp"
    find . -print0 | LC_ALL=C sort -z | cpio --null -o --format=newc --owner=0:0 2>/dev/null | gzip -9
) > "$IMAGENS/Lithos-atualizacao-identidade.cpio.gz"
rm -rf -- "$destino"
mv -- "$destino.tmp" "$destino"
mensagem "Atualização de identidade preparada"
