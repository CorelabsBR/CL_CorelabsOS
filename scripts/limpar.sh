#!/usr/bin/env bash
set -Eeuo pipefail
RAIZ="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=biblioteca.sh
source "$RAIZ/scripts/biblioteca.sh"

printf 'Remover somente artefatos de compilação e o initramfs? O disco QCOW2 será preservado. [s/N] '
read -r resposta
[[ "$resposta" =~ ^[sS]$ ]] || { mensagem "Limpeza cancelada"; exit 0; }
rm -rf -- "$COMPILACAO"
rm -f -- "$IMAGENS/corelabs-initramfs.cpio.gz"
mensagem "Artefatos removidos; fontes e disco persistente foram preservados"

