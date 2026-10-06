#!/usr/bin/env bash
set -Eeuo pipefail
RAIZ="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$RAIZ/scripts/biblioteca.sh"
for comando in readelf realpath; do exigir_comando "$comando"; done
unset CFLAGS CXXFLAGS CPPFLAGS LDFLAGS
toolchain="$(realpath "$COMPILACAO/toolchain")"
sysroot="$(realpath "$COMPILACAO/sysroot")"
saida="$COMPILACAO/testes-base-abi"
mkdir -p "$saida"
unset CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH LIBRARY_PATH LD_LIBRARY_PATH
unset GCC_EXEC_PREFIX COMPILER_PATH
export LC_ALL=C
[[ "$("$toolchain/bin/$BASE_ABI_ALVO-gcc" -print-sysroot)" == "$sysroot" ]] ||
    erro "sysroot padrão da toolchain incorreto"
"$toolchain/bin/$BASE_ABI_ALVO-gcc" -E -v -x c /dev/null \
    > "$saida/include-search.log" 2>&1
while IFS= read -r linha; do
    [[ "$linha" == ' /'* ]] || continue
    caminho="${linha# }"
    resolvido="$(realpath "$caminho")"
    [[ "$resolvido" == "$toolchain/"* || "$resolvido" == "$sysroot/"* ]] ||
        erro "include externo ao target: $caminho"
done < <(sed -n '/#include <...> search starts here:/,/End of search list./p' "$saida/include-search.log")
"$toolchain/bin/$BASE_ABI_ALVO-gcc" --sysroot="$sysroot" -O2 -pthread \
    "$RAIZ/testes/base-abi/hello-Lithos.c" -ldl -lm -Wl,-t \
    -o "$saida/hello-Lithos" > "$saida/c-link.log" 2>&1
"$toolchain/bin/$BASE_ABI_ALVO-g++" --sysroot="$sysroot" -O2 -pthread \
    "$RAIZ/testes/base-abi/hello-Lithos-cpp.cc" -Wl,-t \
    -o "$saida/hello-Lithos-cpp" > "$saida/cpp-link.log" 2>&1
for log in "$saida/c-link.log" "$saida/cpp-link.log"; do
    while IFS= read -r linha; do
        [[ "$linha" == /* ]] || continue
        # Arquivos temporários gerados pelo próprio compilador não são bibliotecas.
        [[ "$linha" == /tmp/cc*.o ]] && continue
        resolvido="$(realpath "$linha")"
        [[ "$resolvido" == "$toolchain/"* || "$resolvido" == "$sysroot/"* ]] ||
            erro "input externo ao target no link: $linha"
    done < "$log"
    grep -F "$sysroot/usr/lib/libc.so.6" "$log" >/dev/null || erro "libc Lithos não aparece no link"
done
for programa in hello-Lithos hello-Lithos-cpp; do
    readelf -lW "$saida/$programa" > "$saida/$programa.readelf"
    readelf -dW "$saida/$programa" >> "$saida/$programa.readelf"
    grep -F '/lib64/ld-linux-x86-64.so.2' "$saida/$programa.readelf" >/dev/null || erro "PT_INTERP incorreto"
    grep -F 'Shared library: [libc.so.6]' "$saida/$programa.readelf" >/dev/null || erro "libc ausente"
done
for biblioteca in libstdc++.so.6 libgcc_s.so.1; do
    grep -F "Shared library: [$biblioteca]" "$saida/hello-Lithos-cpp.readelf" >/dev/null ||
        erro "runtime C++ ausente: $biblioteca"
done
"$RAIZ/scripts/auditar-elf.sh" "$COMPILACAO/rootfs"
mensagem "Provas C/C++ compiladas com inputs exclusivos do target: $saida"
mensagem "A execução deve ocorrer no Lithos; estes checks não executam os ELF no Ubuntu."
