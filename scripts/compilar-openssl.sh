#!/usr/bin/env bash
set -Eeuo pipefail

RAIZ="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=biblioteca.sh
source "$RAIZ/scripts/biblioteca.sh"

arquivo="$FONTES/openssl-$OPENSSL_VERSAO.tar.gz"
arvore="$FONTES/openssl-$OPENSSL_VERSAO"
saida="$COMPILACAO/openssl"
marca="$saida/.configuracao.sha256"
hash_config="$({
    printf '%s\n' \
        "OPENSSL_VERSAO=$OPENSSL_VERSAO" \
        "STATIC=y" \
        "MODULES=n" \
        "COMPRESSION=n"
} | sha256sum | cut -d' ' -f1)"

for comando in curl sha256sum tar make gcc perl; do exigir_comando "$comando"; done
preparar_diretorios
baixar_verificado "$OPENSSL_URL" "$arquivo" "$OPENSSL_SHA256"

if [[ ! -d "$arvore" ]]; then
    mensagem "Extraindo OpenSSL $OPENSSL_VERSAO"
    tar -C "$FONTES" -xf "$arquivo"
fi

if [[ -f "$saida/usr/lib64/libssl.a" && -f "$marca" && "$(<"$marca")" == "$hash_config" ]]; then
    mensagem "OpenSSL já está atualizado"
    exit 0
fi

mensagem "Compilando OpenSSL $OPENSSL_VERSAO estático"
rm -rf -- "$saida.tmp"
mkdir -p -- "$saida.tmp/build" "$saida.tmp/install"
(
    cd "$saida.tmp/build"
    "$arvore/Configure" linux-x86_64 \
        --prefix=/usr \
        --libdir=lib64 \
        no-shared no-module no-tests no-apps no-docs \
        no-zlib no-zstd no-legacy
    make -j"$(numero_trabalhos)" build_sw
    make install_sw DESTDIR="$saida.tmp/install"
)

[[ -f "$saida.tmp/install/usr/lib64/libssl.a" ]] || erro "libssl.a não foi produzida"
rm -rf -- "$saida"
mv -- "$saida.tmp/install" "$saida"
printf '%s\n' "$hash_config" > "$marca"
mensagem "OpenSSL estático compilado."
