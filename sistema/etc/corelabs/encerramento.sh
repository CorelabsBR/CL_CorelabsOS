#!/bin/sh

export PATH=/sbin:/bin:/usr/sbin:/usr/bin

DIRETORIO="/etc/corelabs/servicos"
BIBLIOTECA="/usr/lib/corelabs/registro.sh"

if [ -r "$BIBLIOTECA" ]; then
    . "$BIBLIOTECA"
fi

registrar() {
    if command -v corelabs_registrar >/dev/null 2>&1; then
        corelabs_registrar "SHUTDOWN" "$1" "inicializacao.log" ||
            echo "[Corelabs] Aviso: falha ao registrar encerramento."
    fi
}

echo "[Corelabs] Encerrando serviços..."
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

    echo "[Corelabs] Encerrando: $nome"
    registrar "Encerrando serviço: $nome"

    if "$servico" stop; then
        echo "[Corelabs] OK: $nome"
        registrar "Serviço encerrado: $nome"
    else
        echo "[Corelabs] FALHA: $nome"
        registrar "Falha ao encerrar serviço: $nome"
        falhas=$((falhas + 1))
    fi
done

echo "[Corelabs] Encerramento concluído. Falhas: $falhas"
registrar "Encerramento concluído. Falhas: $falhas"

exit "$falhas"
