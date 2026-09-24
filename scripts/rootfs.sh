#!/usr/bin/env bash
set -Eeuo pipefail
RAIZ="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=biblioteca.sh
source "$RAIZ/scripts/biblioteca.sh"
trap 'erro "a construção do rootfs falhou; consulte $LOGS/rootfs.log"' ERR

for comando in curl sha256sum tar make gcc rsync; do exigir_comando "$comando"; done
preparar_diretorios
arquivo="$FONTES/busybox-$BUSYBOX_VERSAO.tar.bz2"
arvore="$FONTES/busybox-$BUSYBOX_VERSAO"
saida="$COMPILACAO/busybox"
rootfs="$COMPILACAO/rootfs"
marca="$saida/.configuracao.sha256"
hash_config="$({
    printf '%s\n' \
        "BUSYBOX_VERSAO=$BUSYBOX_VERSAO" \
        "CONFIG_STATIC=y" \
        "CONFIG_SH_IS_ASH=y" \
        "CONFIG_CTTYHACK=y" \
        "CONFIG_TC=n"
} | sha256sum | cut -d' ' -f1)"
baixar_verificado "$BUSYBOX_URL" "$arquivo" "$BUSYBOX_SHA256"
if [[ ! -d "$arvore" ]]; then
    mensagem "Extraindo BusyBox $BUSYBOX_VERSAO"
    tar -C "$FONTES" -xf "$arquivo"
fi
mkdir -p -- "$saida"

if [[ ! -x "$saida/busybox" || ! -f "$marca" || "$(<"$marca")" != "$hash_config" ]]; then
    : >"$LOGS/rootfs.log"
    mensagem "Configurando BusyBox estático $BUSYBOX_VERSAO"
    make -C "$arvore" O="$saida" defconfig >>"$LOGS/rootfs.log" 2>&1
    definir_config() {
        local simbolo="$1" valor="$2" arquivo_config="$saida/.config"
        if grep -q "^${simbolo}=" "$arquivo_config"; then
            sed -i "s/^${simbolo}=.*/${simbolo}=${valor}/" "$arquivo_config"
        elif grep -q "^# ${simbolo} is not set$" "$arquivo_config"; then
            if [[ "$valor" == n ]]; then
                return
            fi
            sed -i "s/^# ${simbolo} is not set$/${simbolo}=${valor}/" "$arquivo_config"
        elif [[ "$valor" != n ]]; then
            printf '%s=%s\n' "$simbolo" "$valor" >> "$arquivo_config"
        fi
    }
    definir_config CONFIG_STATIC y
    definir_config CONFIG_SH_IS_ASH y
    definir_config CONFIG_CTTYHACK y
    definir_config CONFIG_TC n
    # BusyBox 1.36 não oferece olddefconfig; EOF aceita os padrões sem interação.
    make -C "$arvore" O="$saida" oldconfig </dev/null >>"$LOGS/rootfs.log" 2>&1
    mensagem "Compilando BusyBox com $(numero_trabalhos) trabalhos paralelos"
    make -C "$arvore" O="$saida" -j"$(numero_trabalhos)" >>"$LOGS/rootfs.log" 2>&1
    printf '%s\n' "$hash_config" > "$marca"
else
    mensagem "BusyBox já está atualizado"
fi

rm -rf -- "$rootfs.tmp"
mkdir -p -- "$rootfs.tmp"/{dev,proc,sys,run,tmp,root,mnt,etc,usr,var,home}
make -C "$arvore" O="$saida" CONFIG_PREFIX="$rootfs.tmp" install >>"$LOGS/rootfs.log" 2>&1
rsync -a -- "$RAIZ/sistema/" "$rootfs.tmp/"

# Corelabs OS Nexus: componentes nativos de userspace.
"$RAIZ/scripts/compilar-supervisor.sh"
"$RAIZ/scripts/compilar-bash.sh"

install -Dm0755     "$COMPILACAO/clsupervisor/clsupervisor"     "$rootfs.tmp/usr/bin/clsupervisor"

install -Dm0755     "$COMPILACAO/bash/bash"     "$rootfs.tmp/bin/bash"
mkdir -p -- "$rootfs.tmp/etc/corelabs" "$rootfs.tmp/usr/share/pixmaps"
cp -- "$RAIZ/branding/system/ascii.txt" "$rootfs.tmp/etc/corelabs/logo.ascii"
cp -- "$RAIZ/branding/system/oslogo.svg" "$rootfs.tmp/usr/share/pixmaps/corelabs-logo.svg"
chmod 0755 "$rootfs.tmp/init"
chmod 0755 "$rootfs.tmp/usr/lib/corelabs/banner"
chmod 1777 "$rootfs.tmp/tmp"
rm -rf -- "$rootfs"
mv -- "$rootfs.tmp" "$rootfs"
mensagem "Rootfs montado em $rootfs"
