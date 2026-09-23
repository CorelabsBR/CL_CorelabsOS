#!/usr/bin/env bash

RAIZ="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=../configuracao/compilacao.conf
source "$RAIZ/configuracao/compilacao.conf"

FONTES="$RAIZ/fontes"
COMPILACAO="$RAIZ/compilacao"
IMAGENS="$RAIZ/imagens"
MAQUINAS="$RAIZ/maquinas"
LOGS="$COMPILACAO/logs"

mensagem() { printf '[Corelabs] %s\n' "$*"; }
erro() { printf '[Corelabs] Erro: %s\n' "$*" >&2; exit 1; }

preparar_diretorios() {
    mkdir -p -- "$FONTES" "$COMPILACAO" "$IMAGENS" "$MAQUINAS" "$LOGS"
}

exigir_comando() {
    command -v "$1" >/dev/null 2>&1 || erro "comando '$1' ausente; execute ./corelabs.sh dependencias"
}

numero_trabalhos() {
    local disponiveis
    disponiveis="$(nproc)"
    if [[ "$LIMITE_NUCLEOS" =~ ^[0-9]+$ ]] && (( LIMITE_NUCLEOS > 0 && LIMITE_NUCLEOS < disponiveis )); then
        printf '%s\n' "$LIMITE_NUCLEOS"
    else
        printf '%s\n' "$disponiveis"
    fi
}

baixar_verificado() {
    local url="$1" destino="$2" hash="$3" temporario
    if [[ -f "$destino" ]] && printf '%s  %s\n' "$hash" "$destino" | sha256sum --check --status; then
        mensagem "Fonte já presente e íntegra: $(basename -- "$destino")"
        return
    fi
    temporario="${destino}.parcial"
    rm -f -- "$temporario"
    mensagem "Baixando $(basename -- "$destino") da fonte oficial"
    curl --fail --location --proto '=https' --tlsv1.2 --output "$temporario" "$url"
    printf '%s  %s\n' "$hash" "$temporario" | sha256sum --check --status || {
        rm -f -- "$temporario"
        erro "SHA-256 inválido para $(basename -- "$destino")"
    }
    mv -- "$temporario" "$destino"
}

