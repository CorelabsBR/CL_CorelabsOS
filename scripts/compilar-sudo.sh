#!/usr/bin/env bash
set -Eeuo pipefail

RAIZ="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=biblioteca.sh
source "$RAIZ/scripts/biblioteca.sh"

arquivo="$FONTES/sudo-$SUDO_VERSAO.tar.gz"
arvore="$FONTES/sudo-$SUDO_VERSAO"
saida="$COMPILACAO/sudo"
marca="$saida/.configuracao.sha256"
hash_config="$({
    printf '%s\n' \
        "SUDO_VERSAO=$SUDO_VERSAO" \
        "LDFLAGS=-static" \
        "STATIC_SUDOERS=y" \
        "PAM=n" \
        "LOG_CLIENT=n" \
        "HARDENING=n" \
        "PIE=n"
} | sha256sum | cut -d' ' -f1)"

for comando in curl sha256sum tar make gcc readelf strip; do exigir_comando "$comando"; done
preparar_diretorios
baixar_verificado "$SUDO_URL" "$arquivo" "$SUDO_SHA256"

if [[ ! -d "$arvore" ]]; then
    mensagem "Extraindo sudo $SUDO_VERSAO"
    tar -C "$FONTES" -xf "$arquivo"
fi

if [[ -x "$saida/usr/bin/sudo" && -f "$marca" && "$(<"$marca")" == "$hash_config" ]]; then
    mensagem "sudo já está atualizado"
    exit 0
fi

mensagem "Configurando sudo $SUDO_VERSAO estático"
rm -rf -- "$saida.tmp"
mkdir -p -- "$saida.tmp/build" "$saida.tmp/install"
(
    cd "$saida.tmp/build"
    LDFLAGS="-static" "$arvore/configure" \
        --prefix=/usr \
        --bindir=/usr/bin \
        --sbindir=/usr/sbin \
        --sysconfdir=/etc \
        --libexecdir=/usr/libexec/sudo \
        --localstatedir=/var \
        --runstatedir=/run \
        --disable-shared \
        --disable-hardening \
        --disable-pie \
        --enable-static-sudoers \
        --disable-log-client \
        --disable-log-server \
        --disable-pam-session \
        --without-sendmail \
        --without-lecture \
        --without-insults
    # O tag libtool "disable-static" é voltado aos plugins dinâmicos; com o
    # sudoers incorporado ele retiraria -static justamente do frontend.
    make LTFLAGS= SUDO_LDFLAGS=-all-static -j"$(numero_trabalhos)"
    install -Dm0755 src/sudo "$saida.tmp/install/usr/bin/sudo"
)

binario="$saida.tmp/install/usr/bin/sudo"
[[ -x "$binario" ]] || erro "a compilação não produziu /usr/bin/sudo"
if readelf -l "$binario" | grep -q INTERP; then
    erro "sudo possui interpretador dinâmico"
fi
strip --strip-unneeded "$binario"

rm -rf -- "$saida"
mv -- "$saida.tmp/install" "$saida"
printf '%s\n' "$hash_config" > "$marca"
mensagem "sudo real compilado."
