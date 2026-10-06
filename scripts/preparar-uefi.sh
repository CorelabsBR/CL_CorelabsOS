#!/usr/bin/env bash
set -Eeuo pipefail
RAIZ="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=biblioteca.sh
source "$RAIZ/scripts/biblioteca.sh"
# shellcheck source=../configuracao/vm.conf
source "$RAIZ/configuracao/vm.conf"

[[ -r "$OVMF_CODE" ]] || erro "firmware OVMF ausente: $OVMF_CODE"
[[ -r "$OVMF_VARS_MODELO" ]] || erro "modelo de variáveis OVMF ausente: $OVMF_VARS_MODELO"

[[ -n "${VM_UEFI_VARS:-}" ]] ||
    erro "VM_UEFI_VARS não configurado"
[[ "$VM_UEFI_VARS" != /* ]] ||
    erro "VM_UEFI_VARS deve ser um caminho relativo"
[[ "$VM_UEFI_VARS" != *".."* ]] ||
    erro "VM_UEFI_VARS contém caminho inválido"

vars="$MAQUINAS/$VM_UEFI_VARS"
mkdir -p -- "$(dirname -- "$vars")"

if [[ ! -f "$vars" ]]; then
    cp -- "$OVMF_VARS_MODELO" "$vars"
    mensagem "Armazenamento persistente das variáveis UEFI criado: $vars"
fi

