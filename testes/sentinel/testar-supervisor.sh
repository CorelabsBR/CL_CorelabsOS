#!/usr/bin/env bash
set -Eeuo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUPERVISOR="$RAIZ/compilacao/clsupervisor/clsupervisor"

falhar() {
    echo "FALHA: $*" >&2
    exit 1
}

executar() {
    echo
    echo "===== $1 ====="
    shift
    "$@"
}

[[ -x "$SUPERVISOR" ]] ||
    falhar "Supervisor não compilado."

TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT

echo "===== POLÍTICA NUNCA ====="

if "$SUPERVISOR" nunca -- /bin/false \
    >"$TEMP/nunca.log" 2>&1; then
    falhar "A política nunca ignorou o erro."
else
    CODIGO=$?
    [[ "$CODIGO" -eq 1 ]] ||
        falhar "Código inesperado: $CODIGO"
fi

[[ "$(grep -c 'Processo iniciado' "$TEMP/nunca.log")" -eq 1 ]] ||
    falhar "Política nunca executou mais de uma vez."

echo "OK"

echo
echo "===== POLÍTICA FALHA: SUCESSO ====="

"$SUPERVISOR" falha -- /bin/true \
    >"$TEMP/sucesso.log" 2>&1 ||
    falhar "Processo bem-sucedido retornou erro."

[[ "$(grep -c 'Processo iniciado' "$TEMP/sucesso.log")" -eq 1 ]] ||
    falhar "Processo bem-sucedido foi reiniciado."

echo "OK"

echo
echo "===== POLÍTICA FALHA: REINICIALIZAÇÕES ====="

if timeout 15s "$SUPERVISOR" falha -- /bin/false \
    >"$TEMP/falha.log" 2>&1; then
    falhar "Falhas consecutivas não foram detectadas."
else
    CODIGO=$?
    [[ "$CODIGO" -eq 1 ]] ||
        falhar "Código inesperado: $CODIGO"
fi

[[ "$(grep -c 'Processo iniciado' "$TEMP/falha.log")" -eq 6 ]] ||
    falhar "Quantidade incorreta de execuções."

grep -q 'Limite de reinicializações atingido' \
    "$TEMP/falha.log" ||
    falhar "Limite não foi registrado."

echo "OK"

executar \
    "ENCERRAMENTO DE DESCENDENTES" \
    "$RAIZ/testes/sentinel/testar-descendentes.sh"

executar \
    "SAÍDA PREMATURA" \
    "$RAIZ/testes/sentinel/testar-saida-prematura.sh"

echo
echo "SENTINEL_SUITE_OK"
