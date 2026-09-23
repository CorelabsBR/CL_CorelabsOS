#!/usr/bin/env bash
set -Eeuo pipefail
RAIZ="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=biblioteca.sh
source "$RAIZ/scripts/biblioteca.sh"
trap 'erro "a compilação das ferramentas do instalador falhou; consulte $LOGS/ferramentas-instalador.log"' ERR

for comando in curl sha256sum tar make gcc; do exigir_comando "$comando"; done
preparar_diretorios
log="$LOGS/ferramentas-instalador.log"
: > "$log"

compilar_e2fsprogs() {
    local arquivo="$FONTES/e2fsprogs-$E2FSPROGS_VERSAO.tar.xz"
    local arvore="$FONTES/e2fsprogs-$E2FSPROGS_VERSAO"
    local saida="$COMPILACAO/e2fsprogs"
    baixar_verificado "$E2FSPROGS_URL" "$arquivo" "$E2FSPROGS_SHA256"
    [[ -d "$arvore" ]] || tar -C "$FONTES" -xf "$arquivo"
    if [[ ! -x "$saida/misc/mke2fs.static" ]]; then
        rm -rf -- "$saida"
        mkdir -p -- "$saida"
        mensagem "Compilando mke2fs estático do e2fsprogs $E2FSPROGS_VERSAO"
        (
            cd "$saida"
            "$arvore/configure" --disable-nls --disable-defrag --disable-e2initrd-helper \
                --disable-fuse2fs --disable-uuidd --enable-libblkid --enable-libuuid \
                --disable-fsck LDFLAGS=-static
            make -j"$(numero_trabalhos)" libs
            make -C misc -j"$(numero_trabalhos)" mke2fs.static
        ) >> "$log" 2>&1
    fi
    file "$saida/misc/mke2fs.static" | grep -q 'statically linked' || erro "mke2fs não ficou estático"
}

compilar_sfdisk() {
    local arquivo="$FONTES/util-linux-$UTIL_LINUX_VERSAO.tar.xz"
    local arvore="$FONTES/util-linux-$UTIL_LINUX_VERSAO"
    local saida="$COMPILACAO/util-linux"
    baixar_verificado "$UTIL_LINUX_URL" "$arquivo" "$UTIL_LINUX_SHA256"
    [[ -d "$arvore" ]] || tar -C "$FONTES" -xf "$arquivo"
    if [[ ! -x "$saida/sfdisk.static" ]]; then
        rm -rf -- "$saida"
        mkdir -p -- "$saida"
        mensagem "Compilando sfdisk estático do util-linux $UTIL_LINUX_VERSAO"
        (
            cd "$saida"
            "$arvore/configure" --disable-all-programs --enable-libuuid \
                --enable-libsmartcols --enable-libfdisk --enable-fdisks \
                --enable-static-programs=sfdisk --disable-shared --enable-static \
                --without-systemd --without-python --without-ncurses \
                --without-readline --disable-nls
            make -j"$(numero_trabalhos)" sfdisk.static
        ) >> "$log" 2>&1
    fi
    file "$saida/sfdisk.static" | grep -q 'statically linked' || erro "sfdisk não ficou estático"
}

compilar_e2fsprogs
compilar_sfdisk
mensagem "Ferramentas estáticas do instalador concluídas"
