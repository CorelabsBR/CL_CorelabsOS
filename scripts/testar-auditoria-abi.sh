#!/usr/bin/env bash
set -Eeuo pipefail
RAIZ="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$RAIZ/scripts/biblioteca.sh"
toolchain="$(realpath "$COMPILACAO/toolchain")"
sysroot="$(realpath "$COMPILACAO/sysroot")"
temporario="$(mktemp -d "$COMPILACAO/auditoria-abi.XXXXXX")"
trap 'rm -rf -- "$temporario"' EXIT
unset CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH LIBRARY_PATH LD_LIBRARY_PATH
unset GCC_EXEC_PREFIX COMPILER_PATH
export LC_ALL=C
cp -a "$COMPILACAO/base-abi-runtime/." "$temporario/"
mkdir -p "$temporario/usr/bin"

esperar_rejeicao() {
    local esperado="$1"
    if "$RAIZ/scripts/auditar-elf.sh" "$temporario" >"$temporario/rejeicao.log" 2>&1; then
        erro "auditor aceitou fixture inválida: $esperado"
    fi
    grep -F "$esperado" "$temporario/rejeicao.log" >/dev/null || {
        sed -n '1,8p' "$temporario/rejeicao.log" >&2
        erro "fixture rejeitada por razão inesperada: $esperado"
    }
}

"$toolchain/bin/$BASE_ABI_ALVO-gcc" --sysroot="$sysroot" \
    "$RAIZ/testes/base-abi/hello-Lithos.c" -pthread -ldl -lm \
    -Wl,-rpath,/usr/lib/x86_64-linux-gnu -o "$temporario/usr/bin/fixture"
esperar_rejeicao 'RPATH/RUNPATH não permitido'

"$toolchain/bin/$BASE_ABI_ALVO-gcc" --sysroot="$sysroot" \
    "$RAIZ/testes/base-abi/hello-Lithos.c" -pthread -ldl -lm \
    '-Wl,-rpath,$ORIGIN' -o "$temporario/usr/bin/fixture"
esperar_rejeicao 'RPATH/RUNPATH não permitido'

"$toolchain/bin/$BASE_ABI_ALVO-gcc" --sysroot="$sysroot" \
    "$RAIZ/testes/base-abi/hello-Lithos.c" -pthread -ldl -lm \
    -Wl,--disable-new-dtags,-rpath,"$COMPILACAO" -o "$temporario/usr/bin/fixture"
esperar_rejeicao 'RPATH/RUNPATH não permitido'

"$toolchain/bin/$BASE_ABI_ALVO-gcc" --sysroot="$sysroot" \
    "$RAIZ/testes/base-abi/hello-Lithos.c" -pthread -ldl -lm \
    -Wl,--dynamic-linker=/lib/loader-externo.so -o "$temporario/usr/bin/fixture"
esperar_rejeicao 'PT_INTERP não Lithos'

cp "$COMPILACAO/testes-base-abi/hello-Lithos-cpp" "$temporario/usr/bin/fixture"
mv "$temporario/usr/lib/libstdc++.so.6" "$temporario/libstdc++.so.6.guardada"
esperar_rejeicao 'DT_NEEDED não resolvido'
ln -s "$sysroot/usr/lib/libstdc++.so.6" "$temporario/usr/lib/libstdc++.so.6"
esperar_rejeicao 'biblioteca escapou do rootfs'
rm -- "$temporario/usr/lib/libstdc++.so.6"
mv "$temporario/libstdc++.so.6.guardada" "$temporario/usr/lib/libstdc++.so.6"

truncate -s 1 "$temporario/usr/lib/libc.so.6"
esperar_rejeicao 'runtime difere dos artefatos'
mensagem "Auditor rejeitou RUNPATH Ubuntu, ORIGIN fora de gconv, RPATH de build, loader estrangeiro, dependência ausente, link externo e runtime adulterado."
