#!/usr/bin/env bash
set -Eeuo pipefail

RAIZ="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"

FONTE="$RAIZ/fontes/clsupervisor/supervisor.c"
DESTINO="$RAIZ/compilacao/clsupervisor"
BINARIO="$DESTINO/clsupervisor"

command -v gcc >/dev/null ||
    { echo "ERRO: GCC indisponível."; exit 1; }

command -v readelf >/dev/null ||
    { echo "ERRO: readelf indisponível."; exit 1; }

[[ -f "$FONTE" ]] ||
    { echo "ERRO: código-fonte não encontrado."; exit 1; }

mkdir -p "$DESTINO"

echo "[Corelabs] Compilando clsupervisor..."

gcc \
    -std=c11 \
    -O2 \
    -Wall \
    -Wextra \
    -Wpedantic \
    -Werror \
    -static \
    -o "$BINARIO.tmp" \
    "$FONTE"

if readelf -l "$BINARIO.tmp" |
    grep -q INTERP; then
    echo "ERRO: executável possui interpretador dinâmico."
    rm -f "$BINARIO.tmp"
    exit 1
fi

chmod 0755 "$BINARIO.tmp"
mv -f "$BINARIO.tmp" "$BINARIO"

echo "[Corelabs] clsupervisor compilado."
