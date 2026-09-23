#!/usr/bin/env bash
set -Eeuo pipefail

RAIZ="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"

TEMPORARIO="$(mktemp -d)"
trap 'rm -rf -- "$TEMPORARIO"' EXIT

mkdir -p \
    "$TEMPORARIO/servicos" \
    "$TEMPORARIO/bibliotecas"

REGISTRO="$TEMPORARIO/ordem.log"
export REGISTRO

# Criar três serviços simulados.
for numero in 01 02 03; do
    cat > "$TEMPORARIO/servicos/$numero-teste" <<'SERVICO'
#!/bin/sh

case "${1:-}" in
    start|stop)
        printf '%s %s\n' \
            "${0##*/}" "$1" >> "$REGISTRO"
        ;;
    *)
        exit 2
        ;;
esac
SERVICO

    chmod 0755 "$TEMPORARIO/servicos/$numero-teste"
done

# Adaptar apenas os caminhos das cópias de teste.
python3 - "$RAIZ" "$TEMPORARIO" <<'PY'
import pathlib
import sys

raiz = pathlib.Path(sys.argv[1])
temporario = pathlib.Path(sys.argv[2])

arquivos = {
    "inicializacao.sh": raiz / "sistema/etc/corelabs/inicializacao.sh",
    "encerramento.sh": raiz / "sistema/etc/corelabs/encerramento.sh",
}

for nome, origem in arquivos.items():
    conteudo = origem.read_text()

    conteudo = conteudo.replace(
        "/etc/corelabs/servicos",
        str(temporario / "servicos"),
    )

    conteudo = conteudo.replace(
        "/usr/lib/corelabs/registro.sh",
        str(temporario / "bibliotecas/registro.sh"),
    )

    destino = temporario / nome
    destino.write_text(conteudo)
    destino.chmod(0o755)
PY

echo "===== TESTANDO INICIALIZAÇÃO ====="

sh "$TEMPORARIO/inicializacao.sh"

echo "===== TESTANDO ENCERRAMENTO ====="

sh "$TEMPORARIO/encerramento.sh"

echo "===== ORDEM OBSERVADA ====="

cat "$REGISTRO"

cat > "$TEMPORARIO/esperado.log" <<'ESPERADO'
01-teste start
02-teste start
03-teste start
03-teste stop
02-teste stop
01-teste stop
ESPERADO

echo "===== VERIFICANDO RESULTADO ====="

if diff -u "$TEMPORARIO/esperado.log" "$REGISTRO"; then
    echo "SENTINEL_TESTE_ORDEM_OK"
else
    echo "SENTINEL_TESTE_ORDEM_FALHOU" >&2
    exit 1
fi
