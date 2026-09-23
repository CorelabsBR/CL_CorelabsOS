#!/usr/bin/env bash
set -Eeuo pipefail

RAIZ="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"

source "$RAIZ/scripts/biblioteca.sh"

DISCO="$RAIZ/maquinas/testes/corelabs-sentinel.qcow2"
PACOTE="$IMAGENS/corelabs-atualizacao-sentinel.cpio.gz"
LOG="$LOGS/instalacao-sentinel.log"

[[ $EUID -ne 0 ]] || {
    echo "ERRO: não execute como root."
    exit 1
}

for comando in qemu-img qemu-system-x86_64 timeout grep; do
    command -v "$comando" >/dev/null || {
        echo "ERRO: comando ausente: $comando"
        exit 1
    }
done

[[ -f "$DISCO" ]] || {
    echo "ERRO: imagem Sentinel não encontrada."
    exit 1
}

[[ -s "$PACOTE" ]] || {
    echo "ERRO: pacote Sentinel não encontrado."
    exit 1
}

[[ -f "$RAIZ/maquinas/testes/corelabs-sentinel-pre-instalacao.qcow2" ]] || {
    echo "ERRO: cópia de segurança não encontrada."
    exit 1
}

qemu-img check "$DISCO"

mkdir -p "$LOGS"
: > "$LOG"

echo "[Sentinel] Instalando exclusivamente na imagem de testes..."

set +e

timeout --signal=TERM 120 \
    qemu-system-x86_64 \
    -machine q35 \
    -accel tcg,thread=multi \
    -cpu max \
    -m 512 \
    -smp 1 \
    -kernel "$COMPILACAO/kernel/bzImage" \
    -initrd "$PACOTE" \
    -append "console=ttyS0,115200 loglevel=4 rdinit=/init" \
    -drive "if=none,file=$DISCO,format=qcow2,id=disco0" \
    -device virtio-blk-pci,drive=disco0 \
    -serial "file:$LOG" \
    -display none \
    -no-reboot

CODIGO=$?

set -e

echo
echo "===== LOG DA INSTALAÇÃO ====="
tail -n 40 "$LOG"

if ! grep -q '^CORELABS_SENTINEL_ATUALIZADA_OK' "$LOG"; then
    echo "ERRO: instalação não confirmada."
    exit 1
fi

if [[ "$CODIGO" -ne 0 ]]; then
    echo "ERRO: QEMU terminou com código $CODIGO."
    exit 1
fi

qemu-img check "$DISCO"

echo "SENTINEL_INSTALACAO_OK"
