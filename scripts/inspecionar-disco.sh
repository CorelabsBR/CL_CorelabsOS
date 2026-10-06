#!/usr/bin/env bash
set -Eeuo pipefail

RAIZ="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"

# shellcheck source=biblioteca.sh
source "$RAIZ/scripts/biblioteca.sh"

# shellcheck source=../configuracao/vm.conf
source "$RAIZ/configuracao/vm.conf"

disco="$MAQUINAS/$VM_DISCO"
initramfs="$IMAGENS/Lithos-inspecao.cpio.gz"
log="$LOGS/inspecao-disco.log"
log_normalizado="${log}.normalizado"

[[ -f "$disco" ]] ||
    erro "imagem de disco ausente: $disco"

[[ -s "$COMPILACAO/kernel/bzImage" ]] ||
    erro "kernel ausente"

"$RAIZ/scripts/preparar-inspecao.sh"

[[ -s "$initramfs" ]] ||
    erro "initramfs de inspeção ausente"

aceleracao=(-accel tcg,thread=multi -cpu max)
if [[ -r /dev/kvm && -w /dev/kvm ]]; then
    aceleracao=(-accel kvm -cpu host)
fi

mkdir -p -- "$LOGS"
rm -f -- "$log_normalizado"

mensagem "Inspecionando partições e sistemas de arquivos sem persistir alterações"

set +e
timeout --signal=TERM "$VM_TIMEOUT_TESTE" \
    qemu-system-x86_64 \
        -machine q35 \
        "${aceleracao[@]}" \
        -m 512 \
        -smp 1 \
        -kernel "$COMPILACAO/kernel/bzImage" \
        -initrd "$initramfs" \
        -append "console=ttyS0,115200 rdinit=/init panic=-1" \
        -drive "if=none,file=$disco,format=qcow2,id=disco0,snapshot=on" \
        -device virtio-blk-pci,drive=disco0 \
        -serial "file:$log" \
        -display none \
        -no-reboot \
        >/dev/null 2>&1
codigo=$?
set -e

(( codigo == 0 )) ||
    erro "inspeção terminou com código $codigo; consulte $log"

tr -d '\r' < "$log" > "$log_normalizado"

if grep -q '^ERRO_INSPECAO_Lithos:' "$log_normalizado"; then
    grep '^ERRO_INSPECAO_Lithos:' "$log_normalizado" >&2 || true
    erro "ambiente de inspeção reportou falha; consulte $log"
fi

grep -q '^INICIO_INSPECAO_Lithos$' "$log_normalizado" ||
    erro "marcador inicial ausente; consulte $log"

grep -q '^FIM_INSPECAO_Lithos$' "$log_normalizado" ||
    erro "marcador final ausente; consulte $log"

resultado_fdisk="$(
    sed -n 's/^RESULTADO_FDISK_Lithos=\([0-9][0-9]*\)$/\1/p' \
        "$log_normalizado" |
        tail -n 1
)"

resultado_blkid="$(
    sed -n 's/^RESULTADO_BLKID_Lithos=\([0-9][0-9]*\)$/\1/p' \
        "$log_normalizado" |
        tail -n 1
)"

[[ -n "$resultado_fdisk" ]] ||
    erro "resultado do fdisk ausente; consulte $log"

[[ -n "$resultado_blkid" ]] ||
    erro "resultado do blkid ausente; consulte $log"

(( resultado_fdisk == 0 )) ||
    erro "fdisk falhou com código $resultado_fdisk; consulte $log"

case "$resultado_blkid" in
    0|2) ;;
    *)
        erro "blkid falhou com código $resultado_blkid; consulte $log"
        ;;
esac

sed -n \
    '/^INICIO_INSPECAO_Lithos$/,/^FIM_INSPECAO_Lithos$/p' \
    "$log_normalizado"

rm -f -- "$log_normalizado"

mensagem "Inspeção concluída com sucesso"
