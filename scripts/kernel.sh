#!/usr/bin/env bash
set -Eeuo pipefail
RAIZ="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=biblioteca.sh
source "$RAIZ/scripts/biblioteca.sh"
trap 'erro "a compilação do kernel falhou; consulte $LOGS/kernel.log"' ERR

forcar=0
case "${1:-}" in
    "") ;;
    --forcar) forcar=1 ;;
    *) erro "opção inválida para kernel: $1" ;;
esac

for comando in curl sha256sum tar make gcc; do exigir_comando "$comando"; done
preparar_diretorios
arquivo="$FONTES/linux-$KERNEL_VERSAO.tar.xz"
arvore="$FONTES/linux-$KERNEL_VERSAO"
saida="$COMPILACAO/kernel"
artefato="$saida/bzImage"
marca="$saida/.configuracao.sha256"
hash_config="$(sha256sum "$RAIZ/configuracao/kernel.config" "$RAIZ/configuracao/compilacao.conf" | sha256sum | cut -d' ' -f1)"

baixar_verificado "$KERNEL_URL" "$arquivo" "$KERNEL_SHA256"
if [[ ! -d "$arvore" ]]; then
    mensagem "Extraindo Linux $KERNEL_VERSAO"
    tar -C "$FONTES" -xf "$arquivo"
fi
mkdir -p -- "$saida"

if (( ! forcar )) && [[ -s "$artefato" && -f "$marca" ]] && [[ "$(<"$marca")" == "$hash_config" ]]; then
    mensagem "Kernel já está atualizado: $artefato"
    exit 0
fi

if (( forcar )); then
    mensagem "Recompilação completa do kernel solicitada"
    make -C "$arvore" O="$saida" mrproper >>"$LOGS/kernel.log" 2>&1 || true
fi

: >"$LOGS/kernel.log"
mensagem "Configurando Linux $KERNEL_VERSAO"
make -C "$arvore" O="$saida" x86_64_defconfig >>"$LOGS/kernel.log" 2>&1
while IFS= read -r linha; do
    [[ "$linha" =~ ^CONFIG_([A-Za-z0-9_]+)=(y|m|n|".*"|[0-9]+)$ ]] || continue
    opcao="CONFIG_${BASH_REMATCH[1]}"
    valor="${BASH_REMATCH[2]}"
    case "$valor" in
        y) "$arvore/scripts/config" --file "$saida/.config" --enable "$opcao" ;;
        m) "$arvore/scripts/config" --file "$saida/.config" --module "$opcao" ;;
        n) "$arvore/scripts/config" --file "$saida/.config" --disable "$opcao" ;;
        \"*) "$arvore/scripts/config" --file "$saida/.config" --set-str "$opcao" "${valor:1:${#valor}-2}" ;;
        *) "$arvore/scripts/config" --file "$saida/.config" --set-val "$opcao" "$valor" ;;
    esac
done < "$RAIZ/configuracao/kernel.config"
make -C "$arvore" O="$saida" olddefconfig >>"$LOGS/kernel.log" 2>&1
mensagem "Compilando kernel com $(numero_trabalhos) trabalhos paralelos"
make -C "$arvore" O="$saida" -j"$(numero_trabalhos)" bzImage >>"$LOGS/kernel.log" 2>&1
cp -- "$saida/arch/x86/boot/bzImage" "$artefato"
printf '%s\n' "$hash_config" > "$marca"
mensagem "Kernel criado: $artefato"

