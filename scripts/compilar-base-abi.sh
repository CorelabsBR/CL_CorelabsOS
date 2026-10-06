#!/usr/bin/env bash
set -Eeuo pipefail
RAIZ="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$RAIZ/scripts/biblioteca.sh"
"$RAIZ/scripts/compilar-toolchain.sh"
exec 9>"$COMPILACAO/.base-abi.lock"
flock 9
alvo="$BASE_ABI_ALVO"
toolchain="$(realpath "$COMPILACAO/toolchain")"
sysroot="$(realpath "$COMPILACAO/sysroot")"
base="${toolchain%/toolchain}"
saida="$COMPILACAO/base-abi-runtime"
marca="$saida/.configuracao.sha256"
hash_config="$({
    sha256sum "$RAIZ/scripts/compilar-base-abi.sh" "$RAIZ/scripts/auditar-elf.sh"
    sha256sum "$sysroot/usr/lib/libc.so.6" "$sysroot/usr/lib/ld-linux-x86-64.so.2" \
        "$sysroot/usr/lib/libstdc++.so.6" "$sysroot/usr/lib/libgcc_s.so.1"
    printf '%s\n' "$(<"$base/.configuracao.sha256")" "$COREUTILS_SHA256" "$UTIL_LINUX_SHA256"
} | sha256sum | cut -d' ' -f1)"
for comando in rsync readelf make pkg-config; do exigir_comando "$comando"; done
baixar_verificado "$COREUTILS_URL" "$FONTES/coreutils-$COREUTILS_VERSAO.tar.xz" "$COREUTILS_SHA256"
baixar_verificado "$UTIL_LINUX_URL" "$FONTES/util-linux-$UTIL_LINUX_VERSAO.tar.xz" "$UTIL_LINUX_SHA256"
for nome in "coreutils-$COREUTILS_VERSAO" "util-linux-$UTIL_LINUX_VERSAO"; do
    [[ -d "$FONTES/$nome" ]] || tar -C "$FONTES" -xf "$FONTES/$nome.tar.xz"
done
if [[ -f "$marca" && "$(<"$marca")" == "$hash_config" && \
    -x "$saida/usr/bin/ls" && -x "$saida/usr/bin/lsblk" && -f "$saida/usr/lib/libc.so.6" ]]; then
    "$RAIZ/scripts/auditar-elf.sh" "$saida"
    mensagem "Lithos Base ABI v1 já está atualizada"
    exit 0
fi

trap 'erro "construção da Base ABI falhou; consulte $LOGS/base-abi-userspace.log"' ERR
unset CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH LIBRARY_PATH LD_LIBRARY_PATH
unset GCC_EXEC_PREFIX COMPILER_PATH CONFIG_SITE
export LC_ALL=C PATH="$toolchain/bin:$PATH"
export CC="$alvo-gcc" CXX="$alvo-g++" AR="$alvo-ar" RANLIB="$alvo-ranlib"
export STRIP="$alvo-strip" OBJDUMP="$alvo-objdump" READELF="$alvo-readelf"
export CFLAGS='-O2 -g0' CXXFLAGS='-O2 -g0' CPPFLAGS= LDFLAGS=
export PKG_CONFIG_SYSROOT_DIR="$sysroot"
export PKG_CONFIG_LIBDIR="$sysroot/usr/lib/pkgconfig:$sysroot/usr/share/pkgconfig"
unset PKG_CONFIG_PATH
host="$("$FONTES/coreutils-$COREUTILS_VERSAO/build-aux/config.guess")"
rm -rf -- "$saida.tmp"
mkdir -p "$saida.tmp/usr/lib" "$saida.tmp/lib64" "$base/build/userspace"
log="$LOGS/base-abi-userspace.log"
{
    # Somente runtime glibc/GCC: nenhum header, archive .a ou compilador no rootfs.
    while IFS= read -r -d '' biblioteca; do
        if [[ -L "$biblioteca" ]] || readelf -h "$biblioteca" >/dev/null 2>&1; then
            cp -a "$biblioteca" "$saida.tmp/usr/lib/"
        fi
    done < <(find "$sysroot/usr/lib" -maxdepth 1 \( -name '*.so' -o -name '*.so.*' \) -print0)
    ln -s ../usr/lib/ld-linux-x86-64.so.2 "$saida.tmp/lib64/ld-linux-x86-64.so.2"
    ln -s usr/lib "$saida.tmp/lib"
    install -Dm0755 "$sysroot/usr/sbin/ldconfig" "$saida.tmp/usr/sbin/ldconfig"
    cp -a "$sysroot/usr/lib/gconv" "$saida.tmp/usr/lib/"
    for comando in getconf getent iconv; do
        install -Dm0755 "$sysroot/usr/bin/$comando" "$saida.tmp/usr/bin/$comando"
    done

    rm -rf -- "$base/build/userspace/coreutils"
    mkdir -p "$base/build/userspace/coreutils"
    (
        cd "$base/build/userspace/coreutils"
        "$FONTES/coreutils-$COREUTILS_VERSAO/configure" --host="$alvo" --build="$host" \
            --prefix=/usr --libexecdir=/usr/libexec --disable-nls --disable-rpath \
            --without-libgmp --disable-libcap --disable-acl --disable-xattr \
            --without-openssl --without-selinux \
            --enable-no-install-program=kill,uptime
        make -j"$(numero_trabalhos)"
        make DESTDIR="$saida.tmp" install
    )

    rm -rf -- "$base/build/userspace/util-linux"
    mkdir -p "$base/build/userspace/util-linux"
    (
        cd "$base/build/userspace/util-linux"
        "$FONTES/util-linux-$UTIL_LINUX_VERSAO/configure" --host="$alvo" --build="$host" \
            --prefix=/usr --bindir=/usr/bin --sbindir=/usr/sbin \
            --libdir=/usr/lib --disable-all-programs \
            --enable-libuuid --enable-libblkid --enable-libmount --enable-libsmartcols \
            --enable-uuidgen --enable-lsblk \
            --disable-static --enable-shared --disable-nls \
            --without-systemd --without-python --without-ncursesw --without-ncurses \
            --without-readline
        make -j"$(numero_trabalhos)"
        make DESTDIR="$saida.tmp" install
    )
    # Remove metadados de desenvolvimento; mantém os utilitários e seus runtimes.
    rm -rf -- "$saida.tmp/usr/include" "$saida.tmp/usr/share" "$saida.tmp/usr/lib/pkgconfig"
    find "$saida.tmp/usr/lib" -name '*.la' -delete
    while IFS= read -r -d '' arquivo; do
        if readelf -h "$arquivo" >/dev/null 2>&1; then
            "$STRIP" --strip-unneeded "$arquivo"
        fi
    done < <(find "$saida.tmp" -type f -print0)
    mkdir -p "$saida.tmp/usr/share/Lithos"
    (
        cd "$saida.tmp"
        find usr/lib usr/bin usr/sbin usr/libexec -type f -print0 |
            LC_ALL=C sort -z | xargs -0 sha256sum > usr/share/Lithos/base-abi-v1.sha256
    )
    "$RAIZ/scripts/auditar-elf.sh" "$saida.tmp"
} > "$log" 2>&1
printf '%s\n' "$hash_config" > "$saida.tmp/.configuracao.sha256"
rm -rf -- "$saida"
mv "$saida.tmp" "$saida"
mensagem "Lithos Base ABI v1 construída; log: $log"
