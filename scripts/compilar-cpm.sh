#!/usr/bin/env bash
set -Eeuo pipefail
RAIZ="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$RAIZ/scripts/biblioteca.sh"
for comando in readelf sha256sum; do exigir_comando "$comando"; done
toolchain="$(realpath "$COMPILACAO/toolchain")"
sysroot="$(realpath "$COMPILACAO/sysroot")"
saida="$COMPILACAO/cpm"
fonte="$RAIZ/fontes/cpm/arquivo.c"
mkdir -p "$saida"
hash="$(sha256sum "$fonte" "$RAIZ/scripts/compilar-cpm.sh" \
    "$toolchain/bin/$BASE_ABI_ALVO-gcc" "$sysroot/usr/lib/libc.so.6" | sha256sum | cut -d' ' -f1)"
if [[ -x "$saida/arquivo" && -f "$saida/.configuracao.sha256" && "$(<"$saida/.configuracao.sha256")" == "$hash" ]]; then
    mensagem "Auxiliar CPM já está atualizado"
    exit 0
fi
unset CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH LIBRARY_PATH LD_LIBRARY_PATH
unset GCC_EXEC_PREFIX COMPILER_PATH
"$toolchain/bin/$BASE_ABI_ALVO-gcc" --sysroot="$sysroot" -std=c11 -O2 -g0 \
    -Wall -Wextra -Werror -o "$saida/arquivo.tmp" "$fonte"
"$toolchain/bin/$BASE_ABI_ALVO-strip" --strip-unneeded "$saida/arquivo.tmp"
readelf -lW "$saida/arquivo.tmp" | grep -F '/lib64/ld-linux-x86-64.so.2' >/dev/null
mv "$saida/arquivo.tmp" "$saida/arquivo"
printf '%s\n' "$hash" > "$saida/.configuracao.sha256"
mensagem "Auxiliar CPM compilado contra a Base ABI v1"
