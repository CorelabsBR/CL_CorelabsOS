#!/usr/bin/env bash
set -Eeuo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUPERVISOR="$RAIZ/compilacao/clsupervisor/clsupervisor"

TEMPORARIO="$(mktemp -d)"
PID_SUPERVISOR=""

limpar() {
    if [[ -n "$PID_SUPERVISOR" ]]; then
        kill -TERM "$PID_SUPERVISOR" 2>/dev/null || true
        wait "$PID_SUPERVISOR" 2>/dev/null || true
    fi

    if [[ -s "$TEMPORARIO/filho.pid" ]]; then
        PID_FILHO="$(cat "$TEMPORARIO/filho.pid")"

        # O teste só encerra o processo que ele próprio criou.
        if [[ -r "/proc/$PID_FILHO/cmdline" ]] &&
           tr '\0' ' ' < "/proc/$PID_FILHO/cmdline" |
               grep -Fq "$TEMPORARIO/descendente.sh"; then
            kill -TERM "$PID_FILHO" 2>/dev/null || true
        fi
    fi

    rm -rf "$TEMPORARIO"
}

trap limpar EXIT

cat > "$TEMPORARIO/descendente.sh" <<'FILHO'
#!/bin/sh

echo "$$" > "$1"
exec sleep 60
FILHO

cat > "$TEMPORARIO/servico.sh" <<'SERVICO'
#!/bin/sh

"$1/descendente.sh" "$1/filho.pid" &
wait
SERVICO

chmod +x \
    "$TEMPORARIO/descendente.sh" \
    "$TEMPORARIO/servico.sh"

"$SUPERVISOR" nunca -- \
    "$TEMPORARIO/servico.sh" "$TEMPORARIO" \
    > "$TEMPORARIO/supervisor.log" 2>&1 &

PID_SUPERVISOR=$!

for tentativa in {1..50}; do
    [[ -s "$TEMPORARIO/filho.pid" ]] && break
    sleep 0.1
done

if [[ ! -s "$TEMPORARIO/filho.pid" ]]; then
    echo "ERRO: descendente não iniciou."
    exit 1
fi

PID_FILHO="$(cat "$TEMPORARIO/filho.pid")"

echo "Supervisor: $PID_SUPERVISOR"
echo "Descendente: $PID_FILHO"

kill -TERM "$PID_SUPERVISOR"

wait "$PID_SUPERVISOR" || true
PID_SUPERVISOR=""

sleep 0.5

if kill -0 "$PID_FILHO" 2>/dev/null; then
    ESTADO="$(ps -o stat= -p "$PID_FILHO" 2>/dev/null || true)"

    case "$ESTADO" in
        Z*)
            echo "Descendente terminou, mas ainda consta como zumbi."
            ;;
        *)
            echo "FALHA: descendente continua executando."
            exit 1
            ;;
    esac
else
    echo "Descendente encerrado."
fi

echo "SENTINEL_TESTE_DESCENDENTES_OK"
