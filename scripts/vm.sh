#!/usr/bin/env bash
set -Eeuo pipefail
RAIZ="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=biblioteca.sh
source "$RAIZ/scripts/biblioteca.sh"
# shellcheck source=../configuracao/vm.conf
source "$RAIZ/configuracao/vm.conf"

grafico=0
recuperacao=0
for opcao in "$@"; do
    case "$opcao" in
        --grafico) grafico=1 ;;
        --recuperacao) recuperacao=1 ;;
        *) erro "opção inválida para iniciar: $opcao" ;;
    esac
done
(( EUID != 0 )) || erro "a máquina virtual não deve ser executada como root"
exigir_comando qemu-system-x86_64

kernel="$COMPILACAO/kernel/bzImage"
initramfs="$IMAGENS/corelabs-initramfs.cpio.gz"
[[ "$VM_DISCO" == "$(basename -- "$VM_DISCO")" ]] ||
    erro "VM_DISCO deve conter apenas o nome do arquivo"

disco="$MAQUINAS/$VM_DISCO"
marcador="$MAQUINAS/.${VM_DISCO%.qcow2}-instalado"
if [[ ! -s "$kernel" || ! -s "$initramfs" ]]; then
    mensagem "Artefatos ausentes; iniciando compilação automática"
    "$RAIZ/corelabs.sh" compilar
elif [[ ! -e "$disco" ]]; then
    "$RAIZ/scripts/imagem.sh"
fi

aceleracao=(-accel tcg,thread=multi -cpu max)
if [[ -r /dev/kvm && -w /dev/kvm ]]; then
    aceleracao=(-accel kvm -cpu host)
    mensagem "Aceleração KVM habilitada"
else
    mensagem "KVM indisponível; usando emulação TCG"
fi

video=(-display none)
if (( grafico )); then
    video=(
        -device virtio-vga
        -device qemu-xhci
        -device usb-tablet
        -display gtk,grab-on-hover=off
    )
fi
mensagem "Inicializando Corelabs OS (${VM_CPUS} vCPUs, ${VM_MEMORIA_MB} MB)"
comum=(-name "$VM_NOME" -machine q35 "${aceleracao[@]}" -m "$VM_MEMORIA_MB" -smp "$VM_CPUS"
    -drive "if=none,file=$disco,format=qcow2,id=disco0" -device virtio-blk-pci,drive=disco0
    -netdev user,id=rede0 -device virtio-net-pci,netdev=rede0 -serial mon:stdio "${video[@]}" -no-reboot)
if (( recuperacao )); then
    mensagem "Modo de recuperação da Fase 0"
    exec qemu-system-x86_64 "${comum[@]}" -kernel "$kernel" -initrd "$initramfs" \
        -append "console=ttyS0,115200 rdinit=/init panic=-1"
fi

[[ -f "$marcador" ]] || erro "sistema não instalado; execute ./corelabs.sh instalar"
"$RAIZ/scripts/preparar-uefi.sh"
mensagem "Boot UEFI a partir do disco persistente"
exec qemu-system-x86_64 "${comum[@]}" \
    -drive "if=pflash,format=raw,readonly=on,file=$OVMF_CODE" \
    -drive "if=pflash,format=raw,file=$MAQUINAS/$VM_UEFI_VARS"

