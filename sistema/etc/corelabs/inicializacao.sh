#!/bin/sh

export PATH=/sbin:/bin:/usr/sbin:/usr/bin

diretorio=/etc/corelabs/servicos
falhas=0

echo "[Corelabs] Inicializando serviços..."

for servico in "$diretorio"/*; do
    [ -f "$servico" ] || continue
    [ -x "$servico" ] || continue

    nome="${servico##*/}"

    case "$nome" in
        *.disabled) continue ;;
    esac

    echo "[Corelabs] Iniciando: $nome"

    if "$servico" start; then
        echo "[Corelabs] OK: $nome"
    else
        echo "[Corelabs] FALHA: $nome"
        falhas=$((falhas + 1))
    fi
done

echo "[Corelabs] Inicialização concluída. Falhas: $falhas"

[ "$falhas" -eq 0 ]
