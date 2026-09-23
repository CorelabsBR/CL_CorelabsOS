#!/bin/sh

export PATH=/sbin:/bin:/usr/sbin:/usr/bin

diretorio=/etc/corelabs/servicos
falhas=0

if [ -r /usr/lib/corelabs/registro.sh ]; then
    . /usr/lib/corelabs/registro.sh
fi

registrar() {
    if command -v corelabs_registrar >/dev/null 2>&1; then
        corelabs_registrar "BOOT" "$1" "inicializacao.log" ||
            echo "[Corelabs] Aviso: falha ao registrar inicialização." >&2
    fi
}

echo "[Corelabs] Inicializando serviços..."
registrar "Inicialização dos serviços iniciada."

for servico in "$diretorio"/*; do
    [ -f "$servico" ] || continue
    [ -x "$servico" ] || continue

    nome="${servico##*/}"

    case "$nome" in
        *.disabled) continue ;;
    esac

    echo "[Corelabs] Iniciando: $nome"
    registrar "Iniciando serviço: $nome"

    if "$servico" start; then
        echo "[Corelabs] OK: $nome"
        registrar "Serviço iniciado: $nome"
    else
        resultado=$?
        echo "[Corelabs] FALHA: $nome (código $resultado)"
        registrar "Falha no serviço: $nome (código $resultado)"
        falhas=$((falhas + 1))
    fi
done

echo "[Corelabs] Inicialização concluída. Falhas: $falhas"
registrar "Inicialização concluída. Falhas: $falhas"

[ "$falhas" -eq 0 ]
