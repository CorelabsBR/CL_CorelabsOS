#!/usr/bin/env bash
set -Eeuo pipefail
RAIZ="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=biblioteca.sh
source "$RAIZ/scripts/biblioteca.sh"
# shellcheck source=../configuracao/vm.conf
source "$RAIZ/configuracao/vm.conf"

[[ -f "$MAQUINAS/.corelabs-instalado" ]] || erro "sistema ainda não instalado; execute ./corelabs.sh instalar"
for comando in qemu-system-x86_64 timeout; do exigir_comando "$comando"; done
"$RAIZ/scripts/preparar-uefi.sh"

aceleracao=(-accel tcg,thread=multi -cpu max)
[[ -r /dev/kvm && -w /dev/kvm ]] && aceleracao=(-accel kvm -cpu host)
token="CORELABS_PERSISTENCIA_$(date +%s)"

executar_boot() {
    local entrada="$1" log="$2"
    set +e
    { sleep 8; printf '%b' "$entrada"; } | timeout --signal=TERM "$VM_TIMEOUT_TESTE" \
        qemu-system-x86_64 -machine q35 "${aceleracao[@]}" -m 1024 -smp 2 \
        -drive "if=pflash,format=raw,readonly=on,file=$OVMF_CODE" \
        -drive "if=pflash,format=raw,file=$MAQUINAS/OVMF_VARS.fd" \
        -drive "if=none,file=$MAQUINAS/corelabs.qcow2,format=qcow2,id=disco0" \
        -device virtio-blk-pci,drive=disco0 -netdev user,id=rede0 \
        -device virtio-net-pci,netdev=rede0 -serial stdio -display none -no-reboot \
        > "$log" 2>&1
    local codigo=$?
    set -e
    (( codigo == 0 )) || erro "boot de persistência terminou com código $codigo; consulte $log"
}

mensagem "Primeiro boot: criando arquivo persistente"
executar_boot "echo $token > /root/prova-persistencia\nsync\necho GRAVACAO_PERSISTENTE_OK\npoweroff\n" \
    "$LOGS/persistencia-gravacao.log"
tr -d '\r' < "$LOGS/persistencia-gravacao.log" | grep -qx 'GRAVACAO_PERSISTENTE_OK' \
    || erro "o primeiro boot não confirmou a gravação"

mensagem "Segundo boot: lendo o arquivo persistente"
executar_boot "cat /root/prova-persistencia\necho LEITURA_PERSISTENTE_OK\npoweroff\n" \
    "$LOGS/persistencia-leitura.log"
tr -d '\r' < "$LOGS/persistencia-leitura.log" | grep -qx "$token" \
    || erro "o conteúdo persistente não reapareceu no segundo boot"
tr -d '\r' < "$LOGS/persistencia-leitura.log" | grep -qx 'LEITURA_PERSISTENTE_OK' \
    || erro "o segundo console não respondeu"
mensagem "Persistência confirmada entre duas inicializações UEFI"
