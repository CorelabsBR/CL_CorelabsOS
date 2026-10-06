#!/usr/bin/env bash
set -Eeuo pipefail
RAIZ="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$RAIZ/scripts/biblioteca.sh"

for comando in gcc g++ gawk make makeinfo bison patch perl python3 tar curl sha256sum readelf rsync flock; do
    exigir_comando "$comando"
done
[[ "$(uname -m)" == x86_64 ]] || erro "bootstrap da Base ABI v1 requer host x86_64"
preparar_diretorios
exec 9>"$COMPILACAO/.base-abi.lock"
flock 9

# O compilador executa no host; somente seus produtos usam o sysroot Lithos.
# Variáveis de busca externas não podem contaminar os produtos do target.
unset CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH LIBRARY_PATH LD_LIBRARY_PATH
unset GCC_EXEC_PREFIX COMPILER_PATH CONFIG_SITE PKG_CONFIG_PATH
unset CFLAGS CXXFLAGS CPPFLAGS LDFLAGS CC CXX AR AS LD RANLIB STRIP
export LC_ALL=C CONFIG_SHELL=/bin/bash
alvo="$BASE_ABI_ALVO"
config_hash="$({
    for variavel in BASE_ABI_ALVO BINUTILS_VERSAO BINUTILS_SHA256 GCC_VERSAO GCC_SHA256 \
        GLIBC_VERSAO GLIBC_SHA256 GLIBC_FIXES_SHA256 GLIBC_FHS_SHA256 KERNEL_VERSAO \
        KERNEL_SHA256 GMP_SHA256 MPFR_SHA256 MPC_SHA256; do
        printf '%s=%s\n' "$variavel" "${!variavel}"
    done
} | sha256sum | cut -d' ' -f1)"
base="$COMPILACAO/base-abi/$config_hash"
toolchain="$base/toolchain"
bootstrap="$base/bootstrap"
sysroot="$base/sysroot"
build="$base/build"
mkdir -p "$toolchain" "$bootstrap" "$sysroot/usr/include" "$build" "$base/marcas"
trap 'erro "toolchain falhou na etapa ${etapa:-fontes}; consulte $LOGS/base-abi-${etapa:-fontes}.log"' ERR

fonte() {
    local nome="$1" extensao="$2" url="$3" hash="$4"
    baixar_verificado "$url" "$FONTES/$nome.$extensao" "$hash"
    [[ -d "$FONTES/$nome" ]] || tar -C "$FONTES" -xf "$FONTES/$nome.$extensao"
}
fonte "binutils-$BINUTILS_VERSAO" tar.xz "$BINUTILS_URL" "$BINUTILS_SHA256"
fonte "gcc-$GCC_VERSAO" tar.xz "$GCC_URL" "$GCC_SHA256"
fonte "glibc-$GLIBC_VERSAO" tar.xz "$GLIBC_URL" "$GLIBC_SHA256"
fonte "linux-$KERNEL_VERSAO" tar.xz "$KERNEL_URL" "$KERNEL_SHA256"
fonte "gmp-$GMP_VERSAO" tar.bz2 "$GMP_URL" "$GMP_SHA256"
fonte "mpfr-$MPFR_VERSAO" tar.bz2 "$MPFR_URL" "$MPFR_SHA256"
fonte "mpc-$MPC_VERSAO" tar.gz "$MPC_URL" "$MPC_SHA256"
baixar_verificado "$GLIBC_FIXES_URL" "$FONTES/glibc-$GLIBC_VERSAO-upstream_fixes-2.patch" "$GLIBC_FIXES_SHA256"
baixar_verificado "$GLIBC_FHS_URL" "$FONTES/glibc-fhs-1.patch" "$GLIBC_FHS_SHA256"

binutils_src="$FONTES/binutils-$BINUTILS_VERSAO"
gcc_src="$base/gcc-src"
glibc_src="$base/glibc-src"
[[ "$("$binutils_src/config.sub" "$alvo")" == "$alvo" ]] || erro "triple não canônico"
host="$("$binutils_src/config.guess")"
[[ "$host" != "$alvo" ]] || erro "host e target precisam ser distintos no bootstrap cruzado"
trabalhos="$(numero_trabalhos)"
# GCC pode consumir mais de 1 GiB por frontend. Respeita também LIMITE_NUCLEOS.
memoria_jobs="$(awk '/MemAvailable:/ {n=int($2/1572864); print (n>0?n:1)}' /proc/meminfo)"
(( trabalhos <= memoria_jobs )) || trabalhos="$memoria_jobs"

cadeia="$config_hash"
executar_etapa() {
    etapa="$1"
    trabalhos="$(numero_trabalhos)"
    memoria_jobs="$(awk '/MemAvailable:/ {n=int($2/1572864); print (n>0?n:1)}' /proc/meminfo)"
    (( trabalhos <= memoria_jobs )) || trabalhos="$memoria_jobs"
    cadeia="$(printf '%s\n' "$cadeia" "$(declare -f "$etapa")" | sha256sum | cut -d' ' -f1)"
    local marca="$base/marcas/$etapa"
    local produto
    case "$etapa" in
        preparar_fontes) produto="$gcc_src/configure" ;;
        binutils_inicial) produto="$toolchain/bin/$alvo-ld" ;;
        gcc_inicial) produto="$bootstrap/bin/$alvo-gcc" ;;
        headers_linux) produto="$sysroot/usr/include/linux/version.h" ;;
        glibc) produto="$sysroot/usr/lib/libc.so.6" ;;
        gcc_final) produto="$toolchain/bin/$alvo-g++" ;;
    esac
    if [[ -s "$produto" && -f "$marca" && -f "$marca.integridade" && \
        "$(<"$marca")" == "$cadeia" && \
        "$(sha256sum "$produto" | cut -d' ' -f1)" == "$(<"$marca.integridade")" ]]; then
        mensagem "Base ABI: $etapa já está atualizado"
        sha256sum "$produto" | cut -d' ' -f1 > "$marca.integridade"
        return
    fi
    mensagem "Base ABI: $etapa ($trabalhos trabalhos); log: $LOGS/base-abi-$etapa.log"
    "$etapa" >"$LOGS/base-abi-$etapa.log" 2>&1
    [[ -s "$produto" ]] || erro "etapa $etapa não produziu $produto"
    printf '%s\n' "$cadeia" > "$marca"
    sha256sum "$produto" | cut -d' ' -f1 > "$marca.integridade"
}

preparar_fontes() {
    rm -rf -- "$gcc_src" "$glibc_src"
    cp -a "$FONTES/gcc-$GCC_VERSAO" "$gcc_src"
    for componente in gmp mpfr mpc; do
        local versao_var="${componente^^}_VERSAO"
        ln -s "$FONTES/$componente-${!versao_var}" "$gcc_src/$componente"
    done
    # Todas as bibliotecas x86_64 vão para lib, sem multilib ou layout Ubuntu.
    sed -i '/m64=/s/lib64/lib/' "$gcc_src/gcc/config/i386/t-linux64"
    cp -a "$FONTES/glibc-$GLIBC_VERSAO" "$glibc_src"
    patch -d "$glibc_src" -p1 < "$FONTES/glibc-fhs-1.patch"
    patch -d "$glibc_src" -p1 < "$FONTES/glibc-$GLIBC_VERSAO-upstream_fixes-2.patch"
}

binutils_inicial() {
    rm -rf -- "$build/binutils"
    mkdir -p "$build/binutils"
    (
        cd "$build/binutils"
        "$binutils_src/configure" --prefix="$toolchain" --target="$alvo" \
            --with-sysroot="$sysroot" --disable-nls --disable-werror \
            --disable-gprofng --disable-gdb --disable-sim --disable-multilib
        make -j"$trabalhos"
        make install
    )
}

gcc_inicial() {
    (
        export PATH="$toolchain/bin:$PATH"
        configurar_gcc "$build/gcc-inicial" \
            --prefix="$bootstrap" --target="$alvo" --with-sysroot="$sysroot" \
            --with-glibc-version="$GLIBC_VERSAO" --with-newlib --without-headers \
            --with-as="$toolchain/bin/$alvo-as" --with-ld="$toolchain/bin/$alvo-ld" \
            --enable-default-pie --enable-default-ssp \
            --enable-languages=c --disable-bootstrap --disable-nls --disable-shared \
            --disable-multilib --disable-threads --disable-libatomic --disable-libgomp \
            --disable-libquadmath --disable-libssp --disable-libstdcxx \
            --disable-libsanitizer --disable-fixincludes --without-isl --without-zstd \
            CFLAGS='-O1 -g0' CXXFLAGS='-O1 -g0'
        cd "$build/gcc-inicial"
        make -j"$trabalhos" all-gcc all-target-libgcc
        make install-gcc install-target-libgcc
    )
}

# Retoma um build interrompido apenas quando os argumentos configure coincidem.
# GCC acrescenta LTO e target_alias à representação guardada em config.status.
configurar_gcc() {
    local diretorio="$1" anterior=
    shift
    if [[ -f "$diretorio/Makefile" && -x "$diretorio/config.status" ]]; then
        anterior="$("$diretorio/config.status" --config)"
    fi
    if [[ -n "$anterior" ]] && python3 -c '
import shlex, sys
def normalize(args):
    result = []
    for arg in args:
        if arg.startswith("target_alias="):
            continue
        if arg.startswith("--enable-languages="):
            langs = arg.split("=", 1)[1].split(",")
            arg = "--enable-languages=" + ",".join(sorted(x for x in langs if x != "lto"))
        result.append(arg)
    return sorted(result)
sys.exit(0 if normalize(shlex.split(sys.argv[1])) == normalize(sys.argv[2:]) else 1)
' "$anterior" "$@"; then
        mensagem "Retomando GCC com a mesma configuração"
    else
        rm -rf -- "$diretorio"
        mkdir -p "$diretorio"
        (cd "$diretorio"; "$gcc_src/configure" "$@")
    fi
}

headers_linux() {
    mkdir -p "$build/headers"
    make -C "$FONTES/linux-$KERNEL_VERSAO" O="$build/headers" ARCH=x86 \
        INSTALL_HDR_PATH="$sysroot/usr" headers_install
}

glibc() {
    rm -rf -- "$build/glibc"
    mkdir -p "$build/glibc" "$sysroot/lib64"
    (
        cd "$build/glibc"
        export PATH="$bootstrap/bin:$toolchain/bin:$PATH"
        printf '%s\n' 'rootsbindir=/usr/sbin' > configparms
        CC="$bootstrap/bin/$alvo-gcc" CXX=false AR="$toolchain/bin/$alvo-ar" \
        RANLIB="$toolchain/bin/$alvo-ranlib" NM="$toolchain/bin/$alvo-nm" \
        OBJDUMP="$toolchain/bin/$alvo-objdump" READELF="$toolchain/bin/$alvo-readelf" \
            "$glibc_src/configure" --prefix=/usr --host="$alvo" --build="$host" \
            --with-headers="$sysroot/usr/include" --enable-kernel=5.10 \
            --disable-nscd --disable-werror libc_cv_slibdir=/usr/lib libc_cv_rtlddir=/lib64
        make -j"$trabalhos"
        make -j1 DESTDIR="$sysroot" install
    )
    ln -sfn ../usr/lib/ld-linux-x86-64.so.2 "$sysroot/lib64/ld-linux-x86-64.so.2"
    ln -sfn usr/lib "$sysroot/lib"
}

gcc_final() {
    (
        export PATH="$toolchain/bin:$PATH"
        configurar_gcc "$build/gcc-final" \
            --prefix="$toolchain" --target="$alvo" --with-sysroot="$sysroot" \
            --with-native-system-header-dir=/usr/include \
            --with-as="$toolchain/bin/$alvo-as" --with-ld="$toolchain/bin/$alvo-ld" \
            --enable-languages=c,c++ --disable-bootstrap --disable-nls \
            --enable-shared --enable-threads=posix --disable-multilib \
            --enable-default-pie --enable-default-ssp --disable-fixincludes \
            --disable-libstdcxx-pch \
            --disable-libsanitizer --disable-libquadmath --disable-libgomp \
            --disable-libssp --disable-libvtv --without-isl --without-zstd \
            CFLAGS='-O2 -g0' CXXFLAGS='-O2 -g0'
        cd "$build/gcc-final"
        make -j"$trabalhos"
        make install
    )
    # O runtime é produzido pelo compilador target, nunca copiado do host.
    local biblioteca
    for biblioteca in libgcc_s.so* libstdc++.so* libatomic.so*; do
        cp -a "$toolchain/$alvo/lib/"$biblioteca "$sysroot/usr/lib/"
    done
}

# glibc instala o loader em rtlddir=/lib64. Consolida os bytes produzidos pela
# etapa no diretório de runtime antes de compilar o GCC final, que liga
# libgcc_s.so contra esse interpretador. Isso também repara gerações retomadas
# que já continham o link FHS, mas ainda não o arquivo de destino.
publicar_loader() {
    [[ -s "$build/glibc/elf/ld.so" ]] || erro "loader compilado ausente"
    mkdir -p "$sysroot/usr/lib" "$sysroot/lib64"
    if ! cmp -s "$build/glibc/elf/ld.so" "$sysroot/usr/lib/ld-linux-x86-64.so.2"; then
        install -m0755 "$build/glibc/elf/ld.so" "$sysroot/usr/lib/ld-linux-x86-64.so.2"
    fi
    ln -sfn ../usr/lib/ld-linux-x86-64.so.2 "$sysroot/lib64/ld-linux-x86-64.so.2"
}

for etapa in preparar_fontes binutils_inicial gcc_inicial headers_linux glibc gcc_final; do
    executar_etapa "$etapa"
    [[ "$etapa" != glibc ]] || publicar_loader
done
[[ -x "$toolchain/bin/$alvo-g++" && -f "$sysroot/usr/lib/libc.so.6" && \
    -f "$sysroot/usr/lib/libstdc++.so.6" ]] || erro "toolchain/runtime incompletos"
printf '%s\n' "$cadeia" > "$base/.configuracao.sha256"
# Publica somente depois de concluir. Builds anteriores continuam disponíveis.
for diretorio in toolchain sysroot; do
    [[ ! -e "$COMPILACAO/$diretorio" || -L "$COMPILACAO/$diretorio" ]] ||
        erro "$COMPILACAO/$diretorio já existe e não é um link gerenciado"
    ln -sfn "$base/$diretorio" "$COMPILACAO/$diretorio"
done
mensagem "Toolchain GNU Lithos e sysroot publicados."
