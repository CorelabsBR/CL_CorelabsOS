#!/usr/bin/env bash
set -Eeuo pipefail

RAIZ="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=biblioteca.sh
source "$RAIZ/scripts/biblioteca.sh"

arquivo="$FONTES/curl-$CURL_VERSAO.tar.xz"
arvore="$FONTES/curl-$CURL_VERSAO"
saida="$COMPILACAO/curl"
marca="$saida/.configuracao.sha256"
hash_config="$({
    printf '%s\n' \
        "CURL_VERSAO=$CURL_VERSAO" \
        "LDFLAGS=-static" \
        "CURL_LDFLAGS_BIN=-all-static" \
        "CA=/etc/ssl/certs/ca-certificates.crt" \
        "PROTOCOLOS=http,https"
} | sha256sum | cut -d' ' -f1)"

for comando in curl sha256sum tar make gcc readelf strip pkg-config; do exigir_comando "$comando"; done
preparar_diretorios
baixar_verificado "$CURL_URL" "$arquivo" "$CURL_SHA256"
"$RAIZ/scripts/compilar-openssl.sh"
#nordeste e seu poder de manipulação, não é mesmo?
if [[ ! -d "$arvore" ]]; then
    mensagem "Extraindo curl $CURL_VERSAO"
    tar -C "$FONTES" -xf "$arquivo"
fi

if [[ -x "$saida/usr/bin/curl" && -f "$marca" && "$(<"$marca")" == "$hash_config" ]]; then
    mensagem "curl já está atualizado"
    exit 0
fi

mensagem "Configurando curl $CURL_VERSAO estático com OpenSSL"
rm -rf -- "$saida.tmp"
mkdir -p -- "$saida.tmp/build" "$saida.tmp/install"
(
    cd "$saida.tmp/build"
    CPPFLAGS="-I$COMPILACAO/openssl/usr/include" \
    LDFLAGS="-static -L$COMPILACAO/openssl/usr/lib64" \
    LIBS="-ldl -pthread" \
        "$arvore/configure" \
        --prefix=/usr \
        --bindir=/usr/bin \
        --disable-shared \
        --enable-static \
        --with-openssl="$COMPILACAO/openssl/usr" \
        --with-ca-bundle=/etc/ssl/certs/ca-certificates.crt \
        --without-ca-path \
        --without-libpsl \
        --without-brotli \
        --without-zstd \
        --without-libidn2 \
        --without-nghttp2 \
        --without-nghttp3 \
        --without-ngtcp2 \
        --without-libssh2 \
        --without-librtmp \
        --without-gssapi \
        --disable-ftp --disable-file --disable-ldap --disable-ldaps \
        --disable-rtsp --disable-dict --disable-telnet --disable-tftp \
        --disable-pop3 --disable-imap --disable-smb --disable-smtp \
        --disable-gopher --disable-mqtt --disable-websockets
    make CURL_LDFLAGS_BIN=-all-static -j"$(numero_trabalhos)"
    make install DESTDIR="$saida.tmp/install"
)

binario="$saida.tmp/install/usr/bin/curl"
[[ -x "$binario" ]] || erro "a compilação não produziu /usr/bin/curl"
if readelf -l "$binario" | grep -q INTERP; then
    erro "curl possui interpretador dinâmico"
fi
strip --strip-unneeded "$binario"

rm -rf -- "$saida"
mv -- "$saida.tmp/install" "$saida"
printf '%s\n' "$hash_config" > "$marca"
mensagem "curl com validação TLS compilado."
