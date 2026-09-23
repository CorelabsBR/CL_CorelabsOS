#!/usr/bin/env bash
set -Eeuo pipefail

RAIZ="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"

source "$RAIZ/scripts/biblioteca.sh"
source "$RAIZ/configuracao/vm.conf"

DISCO="${1:-}"

[[ -n "$DISCO" ]] || {
    echo "Informe explicitamente a imagem de teste." >&2
    exit 1
}

DISCO="$(realpath -e -- "$DISCO")"

case "$DISCO" in
    "$RAIZ/maquinas/testes/"*.qcow2)
        ;;
    *)
        echo "Somente imagens do diretório de testes são permitidas." >&2
        exit 1
        ;;
esac
LOG="$LOGS/atualizacao-infraestrutura.log"

[[ $EUID -ne 0 ]] || {
    echo "Não execute este script como root." >&2
    exit 1
}

[[ -f "$DISCO" ]] || {
    echo "Imagem de teste não encontrada." >&2
    exit 1
}

for comando in qemu-img qemu-system-x86_64 timeout grep; do
    command -v "$comando" >/dev/null || {
        echo "Comando ausente: $comando" >&2
        exit 1
    }
done

# Recusa imagens bloqueadas por outro processo.
qemu-img info -U "$DISCO" >/dev/null

# A verificação normal precisa obter o bloqueio da imagem.
qemu-img check "$DISCO"

"$RAIZ/scripts/preparar-atualizacao-infraestrutura.sh"

mkdir -p "$LOGS"
: > "$LOG"

echo "[Corelabs] Atualizando exclusivamente a imagem de teste..."

set +e

timeout --signal=TERM 120 \
    qemu-system-x86_64 \
    -machine q35 \
    -accel tcg,thread=multi \
    -cpu max \
    -m 512 \
    -smp 1 \
    -kernel "$COMPILACAO/kernel/bzImage" \
    -initrd "$IMAGENS/corelabs-atualizacao-infraestrutura.cpio.gz" \
    -append "console=ttyS0,115200 loglevel=4 rdinit=/init" \
    -drive "if=none,file=$DISCO,format=qcow2,id=disco0" \
    -device virtio-blk-pci,drive=disco0 \
    -serial "file:$LOG" \
    -display none \
    -no-reboot

CODIGO=$?

set -e

echo "===== LOG ====="
tail -n 35 "$LOG"

if ! grep -q '^CORELABS_INFRAESTRUTURA_ATUALIZADA_OK' "$LOG"; then
    echo "ERRO: atualização não confirmada." >&2
    exit 1
fi

if [[ "$CODIGO" -ne 0 ]]; then
    echo "ERRO: QEMU terminou com código $CODIGO." >&2
    exit 1
fi

qemu-img check "$DISCO"

echo "[Corelabs] Atualização concluída na imagem de teste."
