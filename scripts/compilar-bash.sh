#!/usr/bin/env bash
set -Eeuo pipefail

RAIZ="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"

# shellcheck source=biblioteca.sh
source "$RAIZ/scripts/biblioteca.sh"

arquivo="$FONTES/bash-$BASH_VERSAO.tar.gz"
arvore="$FONTES/bash-$BASH_VERSAO"
saida="$COMPILACAO/bash"
binario="$saida/bash"
marca="$saida/.configuracao.sha256"

hash_config="$({
    printf '%s\n' \
        "BASH_VERSAO=$BASH_VERSAO" \
        "LDFLAGS=-static" \
        "PREFIX=/usr" \
        "BINDIR=/bin" \
        "WITHOUT_BASH_MALLOC=y"
} | sha256sum | cut -d' ' -f1)"

for comando in curl sha256sum tar make gcc readelf strip; do
    exigir_comando "$comando"
done

preparar_diretorios

baixar_verificado \
    "$BASH_URL" \
    "$arquivo" \
    "$BASH_SHA256"

if [[ ! -d "$arvore" ]]; then
    mensagem "Extraindo Bash $BASH_VERSAO"
    tar -C "$FONTES" -xf "$arquivo"
fi

if [[ -x "$binario" &&
      -f "$marca" &&
      "$(<"$marca")" == "$hash_config" ]]; then
    mensagem "Bash já está atualizado"
    exit 0
fi

mensagem "Configurando GNU Bash $BASH_VERSAO estático"

rm -rf -- "$saida.tmp"
mkdir -p -- "$saida.tmp"

(
    cd "$saida.tmp"

    LDFLAGS="-static" \
        "$arvore/configure" \
        --prefix=/usr \
        --bindir=/bin \
        --without-bash-malloc

    mensagem "Compilando Bash com $(numero_trabalhos) trabalhos paralelos"

    make -j"$(numero_trabalhos)"

    if readelf -l bash | grep -q INTERP; then
        erro "Bash possui interpretador dinâmico"
    fi

    ./bash --noprofile --norc -c '
        [[ "$((21 * 2))" -eq 42 ]] || exit 1
    '

    strip --strip-unneeded bash

    if readelf -l bash | grep -q INTERP; then
        erro "Bash deixou de ser estático após strip"
    fi
)

rm -rf -- "$saida"
mv -- "$saida.tmp" "$saida"

printf '%s\n' "$hash_config" > "$marca"

mensagem "GNU Bash $BASH_VERSAO compilado."
