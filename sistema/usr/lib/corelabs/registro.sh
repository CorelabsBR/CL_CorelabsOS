#!/bin/sh

CORELABS_DIRETORIO_LOG="/var/log/corelabs"

corelabs_registrar() (
    categoria="${1:-GERAL}"
    mensagem="${2:-}"
    arquivo="${3:-inicializacao.log}"

    case "$arquivo" in
        inicializacao.log|servicos.log) ;;
        *)
            echo "Arquivo de registro inválido." >&2
            exit 2
            ;;
    esac

    mkdir -p "$CORELABS_DIRETORIO_LOG" || exit 1

    data="$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)" ||
        data="DATA_INDISPONIVEL"

    printf '[%s] [%s] %s\n' \
        "$data" "$categoria" "$mensagem" \
        >> "$CORELABS_DIRETORIO_LOG/$arquivo"
)
