#!/usr/bin/env bash
set -Eeuo pipefail
RAIZ="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=biblioteca.sh
source "$RAIZ/scripts/biblioteca.sh"
# shellcheck source=../configuracao/vm.conf
source "$RAIZ/configuracao/vm.conf"

[[ -r "$OVMF_CODE" ]] || erro "firmware OVMF ausente: $OVMF_CODE"
[[ -r "$OVMF_VARS_MODELO" ]] || erro "modelo de variáveis OVMF ausente: $OVMF_VARS_MODELO"
if [[ ! -f "$MAQUINAS/OVMF_VARS.fd" ]]; then
    cp -- "$OVMF_VARS_MODELO" "$MAQUINAS/OVMF_VARS.fd"
    mensagem "Armazenamento persistente das variáveis UEFI criado"
fi

