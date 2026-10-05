#!/usr/bin/env bash
set -Eeuo pipefail

RAIZ="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=biblioteca.sh
source "$RAIZ/scripts/biblioteca.sh"
origem="$COMPILACAO/rootfs"
[[ -d "$origem" ]] || erro "rootfs ausente; execute ./Lithos.sh rootfs"

# Prova de ownership separada: fakeroot fornece uma visão 0:0 completa da
# árvore e muda somente /etc/passwd para 1:1. Não é aninhado no user namespace.
if [[ "${Lithos_SECURITY_OWNERSHIP_TESTED:-}" != 1 ]]; then
    ownership_area="$(mktemp -d "$COMPILACAO/seguranca-ownership.XXXXXX")"
    trap 'rm -rf -- "$ownership_area"' EXIT
    cp -a --reflink=auto "$origem" "$ownership_area/rootfs"
    command -v fakeroot >/dev/null 2>&1 || erro "fakeroot ausente; fixture de ownership não pode ser executada"
    if ! fakeroot -- sh -ec '
        chown -R 0:0 "$1"
        chown 1:1 "$1/etc/passwd"
        "$2" "$1" >"$3" 2>&1
        if "$2" "$1" --installed >"$4" 2>&1; then exit 90; fi
        grep -Fq "ownership crítico deve ser root:root: /etc/passwd" "$4"
    ' sh "$ownership_area/rootfs" "$RAIZ/scripts/auditar-seguranca.sh" \
        "$ownership_area/ownership-build.log" \
        "$ownership_area/ownership-installed.log"; then
        erro "fixture de ownership crítico não observou normal versus --installed"
    fi

    # No modo de build, um PEM seguro pode pertencer ao usuário do checkout.
    # A mesma visão de ownership precisa falhar explicitamente em --installed.
    printf '%s\n' 'fixture-public-key' > "$ownership_area/rootfs/etc/cpm/keyrings/build-user.pem"
    chmod 0644 "$ownership_area/rootfs/etc/cpm/keyrings/build-user.pem"
    if ! fakeroot -- sh -ec '
        chown -R 0:0 "$1"
        chown 1:1 "$1/etc/cpm/keyrings/build-user.pem"
        "$2" "$1" >"$3" 2>&1
        if "$2" "$1" --installed >"$4" 2>&1; then exit 90; fi
        grep -Fq "ownership da chave pública deve ser root:root: /etc/cpm/keyrings/build-user.pem" "$4"
    ' sh "$ownership_area/rootfs" "$RAIZ/scripts/auditar-seguranca.sh" \
        "$ownership_area/pem-build-user-normal.log" \
        "$ownership_area/pem-build-user-installed.log"; then
        erro "fixtures de ownership do PEM não observaram normal versus --installed"
    fi
    rm -rf -- "$ownership_area"
    trap - EXIT
    export Lithos_SECURITY_OWNERSHIP_TESTED=1
fi

# A árvore de build pertence ao usuário do checkout; o archive instalado a
# normaliza para root:root. Um user namespace reproduz essa visão sem sudo e
# permite criar uma capability somente na cópia descartável.
if [[ "${Lithos_SECURITY_USERNS:-}" != 1 && "$EUID" -ne 0 ]]; then
    command -v unshare >/dev/null 2>&1 || erro "fixture requer root ou unshare -Ur"
    exec unshare -Ur env Lithos_SECURITY_USERNS=1 "$0" "$@"
fi

area="$(mktemp -d "$COMPILACAO/seguranca-testes.XXXXXX")"
trap 'rm -rf -- "$area"' EXIT
cp -a --reflink=auto "$origem" "$area/rootfs"

rejeitar() {
    local caso="$1" esperado="${2:-}"
    if "$RAIZ/scripts/auditar-seguranca.sh" "$area/rootfs" >"$area/$caso.log" 2>&1; then
        erro "auditoria aceitou fixture insegura: $caso"
    fi
    [[ -z "$esperado" ]] || grep -Fq -- "$esperado" "$area/$caso.log" ||
        erro "fixture $caso falhou por motivo inesperado"
}

chmod 0644 "$area/rootfs/etc/sudoers"
rejeitar sudoers-permissivo
chmod 0440 "$area/rootfs/etc/sudoers"

cp "$area/rootfs/bin/true" "$area/rootfs/usr/bin/suid-inesperado"
chmod 4755 "$area/rootfs/usr/bin/suid-inesperado"
rejeitar suid-inesperado
rm -- "$area/rootfs/usr/bin/suid-inesperado"

chmod 0777 "$area/rootfs/etc/cpm"
rejeitar diretorio-world-writable
chmod 0755 "$area/rootfs/etc/cpm"

chmod 0775 "$area/rootfs/etc/cpm/keyrings"
rejeitar keyrings-group-writable 'diretório da trust store deve ser 0755: /etc/cpm/keyrings'
chmod 0755 "$area/rootfs/etc/cpm/keyrings"

printf '%s\n' 'fixture-public-key' > "$area/rootfs/etc/cpm/keyrings/group-writable.pem"
chmod 0664 "$area/rootfs/etc/cpm/keyrings/group-writable.pem"
rejeitar pem-group-writable 'chave pública não pode ser gravável por grupo/outros: /etc/cpm/keyrings/group-writable.pem'
rm -- "$area/rootfs/etc/cpm/keyrings/group-writable.pem"

capability_status=EXECUTADA
if ! command -v setcap >/dev/null 2>&1; then
    capability_status="IMPOSSIBILITADA: setcap ausente"
else
    cp "$area/rootfs/bin/busybox" "$area/rootfs/usr/bin/com-capability"
    if setcap cap_net_bind_service=ep "$area/rootfs/usr/bin/com-capability" 2>"$area/setcap.log"; then
        rejeitar file-capability 'file capabilities inesperadas'
        setcap -r "$area/rootfs/usr/bin/com-capability"
    else
        detalhe="$(tr '\n' ' ' < "$area/setcap.log")"
        capability_status="IMPOSSIBILITADA: filesystem/ambiente recusou setcap (${detalhe:-sem detalhe})"
    fi
    rm -f -- "$area/rootfs/usr/bin/com-capability"
fi

mensagem "Fixtures executadas e rejeitadas: sudoers-permissivo, suid-inesperado, diretorio-world-writable, keyrings-group-writable, ownership-nao-root, pem-build-user-installed, pem-group-writable."
mensagem "Fixture segura aceita: pem-build-user-normal."
if [[ "$capability_status" == EXECUTADA ]]; then
    mensagem "Fixture executada e rejeitada: file-capability."
else
    mensagem "Fixture file-capability $capability_status; não contada como rejeição comprovada."
fi
