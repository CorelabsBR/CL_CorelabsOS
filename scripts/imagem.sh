#!/usr/bin/env bash
set -Eeuo pipefail
RAIZ="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=biblioteca.sh
source "$RAIZ/scripts/biblioteca.sh"
# shellcheck source=../configuracao/vm.conf
source "$RAIZ/configuracao/vm.conf"

exigir_comando qemu-img
[[ "$VM_DISCO_GB" =~ ^[1-9][0-9]*$ ]] || erro "VM_DISCO_GB inválido em configuracao/vm.conf"
mkdir -p -- "$MAQUINAS"
disco="$MAQUINAS/corelabs.qcow2"
if [[ -e "$disco" ]]; then
    mensagem "Disco persistente preservado: $disco"
    exit 0
fi
qemu-img create -f qcow2 "$disco" "${VM_DISCO_GB}G"
mensagem "Disco vazio de ${VM_DISCO_GB} GB criado; o rootfs ainda não persiste dados nele"

