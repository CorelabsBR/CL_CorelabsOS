#!/bin/sh

export PATH=/sbin:/bin:/usr/sbin:/usr/bin

DIRETORIO="/etc/Lithos/servicos"
BIBLIOTECA="/usr/lib/Lithos/registro.sh"

if [ -r "$BIBLIOTECA" ]; then
    . "$BIBLIOTECA"
fi

registrar() {
    if command -v Lithos_registrar >/dev/null 2>&1; then
        Lithos_registrar "SHUTDOWN" "$1" "inicializacao.log" ||
            echo "[Lithos] Aviso: falha ao registrar encerramento."
    fi
}

echo "[Lithos] Encerrando serviços..."
registrar "Encerramento dos serviços iniciado."

falhas=0

# Inverter a ordem sem depender de comandos externos.
set --

for servico in "$DIRETORIO"/*; do
    [ -f "$servico" ] || continue
    [ -x "$servico" ] || continue

    case "$servico" in
        *.disabled) continue ;;
    esac

    set -- "$servico" "$@"
done

for servico do
    nome="${servico##*/}"

    echo "[Lithos] Encerrando: $nome"
    registrar "Encerrando serviço: $nome"

    if "$servico" stop; then
        echo "[Lithos] OK: $nome"
        registrar "Serviço encerrado: $nome"
    else
        echo "[Lithos] FALHA: $nome"
        registrar "Falha ao encerrar serviço: $nome"
        falhas=$((falhas + 1))
    fi
done

echo "[Lithos] Encerramento concluído. Falhas: $falhas"
registrar "Encerramento concluído. Falhas: $falhas"

exit "$falhas"
