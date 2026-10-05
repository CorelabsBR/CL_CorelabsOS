#!/usr/bin/env bash
set -Eeuo pipefail
RAIZ="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$RAIZ/scripts/biblioteca.sh"
exigir_comando readelf
exigir_comando realpath
rootfs="$(realpath -- "${1:-$COMPILACAO/rootfs}")"
[[ "$rootfs" != / && -d "$rootfs" ]] || erro "rootfs inválido para auditoria"
export LC_ALL=C
if [[ -f "$rootfs/usr/share/corelabs/base-abi-v1.sha256" ]]; then
    (
        cd "$rootfs"
        sha256sum --check --status usr/share/corelabs/base-abi-v1.sha256
    ) || erro "runtime difere dos artefatos compilados para Corelabs"
fi
total=0
dinamicos=0
modulos_origin=0
while IFS= read -r -d '' arquivo; do
    # readelf inspeciona os bytes; nenhum ELF é executado no host.
    cabecalho="$(readelf -hW "$arquivo" 2>/dev/null)" || continue
    total=$((total + 1))
    [[ "$cabecalho" == *ELF64* && "$cabecalho" == *"Advanced Micro Devices X86-64"* ]] ||
        erro "ELF fora da arquitetura x86_64: $arquivo"
    programa="$(readelf -lW "$arquivo")"
    dynamic="$(readelf -dW "$arquivo")"
    diretorios=(/usr/lib /lib /lib64 /usr/lib64)
    if [[ "$dynamic" == *'(RPATH)'* || "$dynamic" == *'(RUNPATH)'* ]]; then
        caminhos="$(sed -n 's/.*(\(RPATH\|RUNPATH\)).*\[\([^]]*\)\].*/\2/p' <<< "$dynamic")"
        # Os módulos gconv oficiais usam apenas $ORIGIN para suas bibliotecas
        # auxiliares no mesmo diretório. Não autoriza paths absolutos, listas,
        # $ORIGIN/.. ou RPATH em executáveis/pacotes arbitrários.
        if [[ "${arquivo%/*}" == "$rootfs/usr/lib/gconv" && "$arquivo" == *.so && \
            "$cabecalho" == *'DYN (Shared object file)'* && \
            "$programa" != *'Requesting program interpreter:'* && "$caminhos" == '$ORIGIN' && \
            "$(realpath "${arquivo%/*}")" == "$rootfs/usr/lib/gconv" && \
            -f "$rootfs/usr/share/corelabs/base-abi-v1.sha256" ]] && \
            awk -v modulo="usr/lib/gconv/${arquivo##*/}" \
                '$2 == modulo {encontrado=1} END {exit !encontrado}' \
                "$rootfs/usr/share/corelabs/base-abi-v1.sha256"; then
            diretorios=(/usr/lib/gconv "${diretorios[@]}")
            modulos_origin=$((modulos_origin + 1))
        else
            erro "RPATH/RUNPATH não permitido na Base ABI v1: $arquivo"
        fi
    fi
    if [[ "$programa" == *'Requesting program interpreter:'* ]]; then
        interprete="$(sed -n 's/.*Requesting program interpreter: \([^]]*\)].*/\1/p' <<< "$programa")"
        [[ "$interprete" == /lib64/ld-linux-x86-64.so.2 ]] ||
            erro "PT_INTERP não Corelabs: $arquivo: $interprete"
        [[ -f "$rootfs$interprete" ]] || erro "loader ausente: $interprete"
        resolvido="$(realpath "$rootfs$interprete")"
        [[ "$resolvido" == "$rootfs/"* ]] || erro "loader escapou do rootfs"
        dinamicos=$((dinamicos + 1))
    fi
    while IFS= read -r dependencia; do
        [[ -n "$dependencia" ]] || continue
        [[ "$dependencia" != */* ]] || erro "DT_NEEDED contém path: $arquivo: $dependencia"
        encontrada=0
        for diretorio in "${diretorios[@]}"; do
            if [[ -f "$rootfs$diretorio/$dependencia" ]]; then
                resolvido="$(realpath "$rootfs$diretorio/$dependencia")"
                [[ "$resolvido" == "$rootfs/"* ]] || erro "biblioteca escapou do rootfs: $dependencia"
                encontrada=1
                break
            fi
        done
        (( encontrada )) || erro "DT_NEEDED não resolvido no rootfs: $arquivo: $dependencia"
    done < <(sed -n 's/.*(NEEDED).*\[\([^]]*\)\].*/\1/p' <<< "$dynamic")
done < <(find "$rootfs" -type f -print0)
(( dinamicos > 0 )) || erro "nenhum executável dinâmico encontrado"
mensagem "Auditoria ELF: $total ELF x86_64, $dinamicos executáveis dinâmicos; dependências internas, sem RPATH externo ($modulos_origin módulos gconv com \$ORIGIN local)."
