#!/usr/bin/env bash
set -Eeuo pipefail

RAIZ="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"

source "$RAIZ/scripts/biblioteca.sh"
source "$RAIZ/configuracao/vm.conf"

destino="$COMPILACAO/atualizacao-infraestrutura"
pacote="$destino.tmp/opt/corelabs-infraestrutura"

assinatura_init="c2179256cdbbd089c14bb65657793bcd5b5a04cf8c42fcddc3dd2353d9b8d38b"

"$RAIZ/scripts/rootfs.sh"

rm -rf -- "$destino.tmp"

mkdir -p \
    "$destino.tmp"/{dev,proc,sys,run,tmp,root,mnt,etc,usr,var,home} \
    "$pacote/etc/corelabs/servicos"

make -C "$FONTES/busybox-$BUSYBOX_VERSAO" \
    O="$COMPILACAO/busybox" \
    CONFIG_PREFIX="$destino.tmp" \
    install >/dev/null

cp "$RAIZ/sistema-atualizador/infraestrutura-init" \
    "$destino.tmp/init"

sed -i \
    -e "s/@RAIZ_UUID@/$VM_RAIZ_UUID/g" \
    -e "s/@ASSINATURA_INIT@/$assinatura_init/g" \
    "$destino.tmp/init"

cp "$RAIZ/sistema/init" "$pacote/init"

cp "$RAIZ/sistema/etc/corelabs/inicializacao.sh" \
    "$pacote/etc/corelabs/inicializacao.sh"

cp "$RAIZ/sistema/etc/corelabs/servicos/01-diretorios" \
    "$pacote/etc/corelabs/servicos/01-diretorios"

mkdir -p "$pacote/usr/bin" "$pacote/usr/lib"

cp "$RAIZ/sistema/usr/bin/clservice"     "$pacote/usr/bin/clservice"

cp "$RAIZ/sistema/usr/lib/os-release"     "$pacote/usr/lib/os-release"

cp "$RAIZ/sistema/etc/motd"     "$pacote/etc/motd"

chmod 0755 \
    "$destino.tmp/init" \
    "$pacote/init" \
    "$pacote/etc/corelabs/inicializacao.sh" \
    "$pacote/etc/corelabs/servicos/01-diretorios"

mkdir -p "$IMAGENS"

(
    cd "$destino.tmp"

    find . -print0 |
        LC_ALL=C sort -z |
        cpio --null -o --format=newc --owner=0:0 2>/dev/null |
        gzip -9
) > "$IMAGENS/corelabs-atualizacao-infraestrutura.cpio.gz"

rm -rf -- "$destino"
mv -- "$destino.tmp" "$destino"

echo "[Corelabs] Pacote de infraestrutura preparado."
