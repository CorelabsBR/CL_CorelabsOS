#!/usr/bin/env bash
set -Eeuo pipefail
RAIZ="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=biblioteca.sh
source "$RAIZ/scripts/biblioteca.sh"
# shellcheck source=../configuracao/vm.conf
source "$RAIZ/configuracao/vm.conf"

disco="$MAQUINAS/corelabs.qcow2"
[[ -f "$disco" ]] || erro "imagem de disco ausente"
[[ -s "$COMPILACAO/kernel/bzImage" && -s "$IMAGENS/corelabs-initramfs.cpio.gz" ]] \
    || erro "ambiente de recuperação ausente"
aceleracao=(-accel tcg,thread=multi -cpu max)
[[ -r /dev/kvm && -w /dev/kvm ]] && aceleracao=(-accel kvm -cpu host)
log="$LOGS/inspecao-disco.log"

mensagem "Inspecionando partições e sistemas de arquivos sem persistir alterações"
set +e
{ sleep 3; printf 'echo INICIO_INSPECAO_CORELABS\nfdisk -l /dev/vda\nblkid /dev/vda*\necho FIM_INSPECAO_CORELABS\npoweroff -f\n'; } \
    | timeout --signal=TERM "$VM_TIMEOUT_TESTE" qemu-system-x86_64 \
        -machine q35 "${aceleracao[@]}" -m 512 -smp 1 \
        -kernel "$COMPILACAO/kernel/bzImage" -initrd "$IMAGENS/corelabs-initramfs.cpio.gz" \
        -append "console=ttyS0,115200 rdinit=/init panic=-1" \
        -drive "if=none,file=$disco,format=qcow2,id=disco0,snapshot=on" \
        -device virtio-blk-pci,drive=disco0 -serial stdio -display none -no-reboot \
        > "$log" 2>&1
codigo=$?
set -e
(( codigo == 0 )) || erro "inspeção terminou com código $codigo; consulte $log"
tr -d '\r' < "$log" | sed -n '/^INICIO_INSPECAO_CORELABS$/,/^FIM_INSPECAO_CORELABS$/p'

