#!/bin/sh

export PATH=/sbin:/bin:/usr/sbin:/usr/bin

diretorio=/etc/Lithos/servicos
falhas=0

if [ -r /usr/lib/Lithos/registro.sh ]; then
    . /usr/lib/Lithos/registro.sh
fi

registrar() {
    if command -v Lithos_registrar >/dev/null 2>&1; then
        Lithos_registrar "BOOT" "$1" "inicializacao.log" ||
            echo "[Lithos] Aviso: falha ao registrar inicialização." >&2
    fi
}

echo "[Lithos] Inicializando serviços..."
registrar "Inicialização dos serviços iniciada."

for servico in "$diretorio"/*; do
    [ -f "$servico" ] || continue
    [ -x "$servico" ] || continue

    nome="${servico##*/}"

    case "$nome" in
        *.disabled) continue ;;
    esac

    echo "[Lithos] Iniciando: $nome"
    registrar "Iniciando serviço: $nome"

    if "$servico" start; then
        echo "[Lithos] OK: $nome"
        registrar "Serviço iniciado: $nome"
    else
        resultado=$?
        echo "[Lithos] FALHA: $nome (código $resultado)"
        registrar "Falha no serviço: $nome (código $resultado)"
        falhas=$((falhas + 1))
    fi
done

echo "[Lithos] Inicialização concluída. Falhas: $falhas"
registrar "Inicialização concluída. Falhas: $falhas"

[ "$falhas" -eq 0 ]
