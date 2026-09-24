#!/usr/bin/env bash
#linha feita com sucesso nao pode falar que nao é linha de codigo pq sim
set -Eeuo pipefail
RAIZ="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=biblioteca.sh
source "$RAIZ/scripts/biblioteca.sh"
# shellcheck source=../configuracao/vm.conf
source "$RAIZ/configuracao/vm.conf"

(( EUID != 0 )) || erro "a atualização não deve ser executada como root"
[[ -f "$MAQUINAS/.corelabs-instalado" ]] || erro "sistema persistente não instalado"
"$RAIZ/scripts/preparar-atualizacao-identidade.sh"

aceleracao=(-accel tcg,thread=multi -cpu max)
# # [[ -r /dev/kvm && -w /dev/kvm ]] && aceleracao=(-accel kvm -cpu host)
log="$LOGS/atualizacao-identidade.log"
set +e
timeout --signal=TERM "$VM_TIMEOUT_TESTE" qemu-system-x86_64 \
    -machine q35 "${aceleracao[@]}" -m 512 -smp 1 \
    -kernel "$COMPILACAO/kernel/bzImage" -initrd "$IMAGENS/corelabs-atualizacao-identidade.cpio.gz" \
    -append "console=ttyS0,115200 earlycon=uart,io,0x3f8,115200 loglevel=4 rdinit=/init" \
    -drive "if=none,file=${CORELABS_DISCO:-$MAQUINAS/corelabs.qcow2},format=qcow2,id=disco0" \
    -device virtio-blk-pci,drive=disco0 -serial "file:$log" -display none -no-reboot
codigo=$?
set -e
(( codigo == 0 )) || erro "atualização terminou com código $codigo; consulte $log"
grep -q '^CORELABS_IDENTIDADE_ATUALIZADA_OK' "$log" \
    || erro "marcador de atualização não encontrado; consulte $log"
mensagem "Identidade atualizada sem reparticionar o disco"

