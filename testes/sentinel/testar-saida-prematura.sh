#!/usr/bin/env bash
set -Eeuo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUPERVISOR="$RAIZ/compilacao/clsupervisor/clsupervisor"
TEMP="$(mktemp -d)"
PID_SUPERVISOR=""

limpar() {
    if [[ -n "$PID_SUPERVISOR" ]]; then
        kill -TERM "$PID_SUPERVISOR" 2>/dev/null || true
        wait "$PID_SUPERVISOR" 2>/dev/null || true
    fi

    if [[ -s "$TEMP/descendente.pid" ]]; then
        PID="$(cat "$TEMP/descendente.pid")"
        if [[ -r "/proc/$PID/cmdline" ]] &&
           tr '\0' ' ' < "/proc/$PID/cmdline" |
               grep -Fq "$TEMP/descendente.sh"; then
            kill -TERM "$PID" 2>/dev/null || true
        fi
    fi

    rm -rf "$TEMP"
}

trap limpar EXIT

cat > "$TEMP/descendente.sh" <<'FILHO'
#!/bin/sh
echo "$$" > "$1"
exec sleep 60
FILHO

cat > "$TEMP/servico.sh" <<'SERVICO'
#!/bin/sh
"$1/descendente.sh" "$1/descendente.pid" &
sleep 0.3
exit 1
SERVICO

chmod +x "$TEMP/"*.sh

"$SUPERVISOR" nunca -- \
    "$TEMP/servico.sh" "$TEMP" \
    > "$TEMP/supervisor.log" 2>&1 &

PID_SUPERVISOR=$!

wait "$PID_SUPERVISOR" || true
PID_SUPERVISOR=""

if [[ ! -s "$TEMP/descendente.pid" ]]; then
    echo "ERRO: descendente não foi criado."
    exit 1
fi

PID="$(cat "$TEMP/descendente.pid")"
ESTADO="$(ps -o stat= -p "$PID" 2>/dev/null || true)"

echo "PID descendente: $PID"
echo "Estado: ${ESTADO:-inexistente}"

if [[ -n "$ESTADO" && "$ESTADO" != Z* ]]; then
    echo "FALHA DETECTADA: descendente sobreviveu."
    exit 1
fi

echo "SENTINEL_TESTE_SAIDA_PREMATURA_OK"
