#!/usr/bin/env bash
set -Eeuo pipefail
RAIZ="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=biblioteca.sh
source "$RAIZ/scripts/biblioteca.sh"
# shellcheck source=../configuracao/vm.conf
source "$RAIZ/configuracao/vm.conf"

(( EUID != 0 )) || erro "o instalador não deve ser executado como root"
for comando in qemu-system-x86_64 qemu-img timeout; do exigir_comando "$comando"; done
disco="$MAQUINAS/corelabs.qcow2"
[[ -f "$disco" ]] || "$RAIZ/scripts/imagem.sh"
qemu-img info --output=json "$disco" | grep -q '"format": "qcow2"' \
    || erro "o alvo não é uma imagem QCOW2"
[[ "$(realpath -- "$disco")" == "$RAIZ/maquinas/corelabs.qcow2" ]] \
    || erro "alvo fora do caminho permitido"

"$RAIZ/scripts/preparar-instalador.sh"
"$RAIZ/scripts/inspecionar-disco.sh"

mensagem "A instalação apagará as partições e os dados dentro de: $disco"
mensagem "Nenhum disco físico do host será acessado."
printf 'Digite exatamente INSTALAR CORELABS para continuar: '
read -r confirmacao
[[ "$confirmacao" == "INSTALAR CORELABS" ]] || erro "instalação cancelada"

aceleracao=(-accel tcg,thread=multi -cpu max)
[[ -r /dev/kvm && -w /dev/kvm ]] && aceleracao=(-accel kvm -cpu host)
log="$LOGS/instalacao.log"
set +e
timeout --signal=TERM "$VM_TIMEOUT_TESTE" qemu-system-x86_64 \
    -machine q35 "${aceleracao[@]}" -m 1024 -smp 2 \
    -kernel "$COMPILACAO/kernel/bzImage" -initrd "$IMAGENS/corelabs-instalador.cpio.gz" \
    -append "console=ttyS0,115200 rdinit=/init corelabs.instalar=SIM" \
    -drive "if=none,file=$disco,format=qcow2,id=alvo" \
    -device virtio-blk-pci,drive=alvo -serial stdio -display none -no-reboot \
    > "$log" 2>&1
codigo=$?
set -e
if (( codigo == 0 )) && grep -q '^CORELABS_INSTALACAO_OK' "$log"; then
    printf '%s\n' "$VM_RAIZ_UUID" > "$MAQUINAS/.corelabs-instalado"
    mensagem "Instalação concluída no disco virtual"
else
    erro "instalação falhou com código $codigo; consulte $log"
fi
