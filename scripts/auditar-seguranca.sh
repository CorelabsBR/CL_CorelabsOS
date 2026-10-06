#!/usr/bin/env bash
set -Eeuo pipefail

RAIZ_PROJETO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=biblioteca.sh
source "$RAIZ_PROJETO/scripts/biblioteca.sh"

rootfs="$(realpath -- "${1:-$COMPILACAO/rootfs}")"
[[ "$rootfs" != / && -d "$rootfs" ]] || erro "rootfs inválido para auditoria de segurança"
export LC_ALL=C

falhar() { erro "auditoria de segurança: $*"; }
modo() { stat -c %a "$rootfs$1"; }
dono() { stat -c %u:%g "$rootfs$1"; }

for diretorio in /etc/cpm /etc/cpm/keyrings /etc/cpm/repos.d; do
    [[ -d "$rootfs$diretorio" && ! -L "$rootfs$diretorio" ]] ||
        falhar "diretório da trust store ausente, inválido ou symlink: $diretorio"
    [[ "$(modo "$diretorio")" == 755 ]] ||
        falhar "diretório da trust store deve ser 0755: $diretorio"
done

# A chave oficial ainda não é obrigatória. Porém, qualquer PEM provisionado
# passa imediatamente a fazer parte da trust store e precisa ser protegido.
for chave in "$rootfs/etc/cpm/keyrings/"*.pem; do
    [[ -e "$chave" || -L "$chave" ]] || continue
    caminho="${chave#"$rootfs"}"
    [[ -f "$chave" && ! -L "$chave" ]] ||
        falhar "chave pública deve ser arquivo regular e não symlink: $caminho"
    if [[ "${2:-}" == --installed ]]; then
        [[ "$(stat -c %u:%g "$chave")" == 0:0 ]] ||
            falhar "ownership da chave pública deve ser root:root: $caminho"
    fi
    modo_chave="$(stat -c %a "$chave")"
    (( (8#$modo_chave & 0022) == 0 )) ||
        falhar "chave pública não pode ser gravável por grupo/outros: $caminho"
done

for arquivo in /etc/passwd /etc/group /etc/shadow /etc/sudoers /etc/cpm/repos.d/Lithos.repo \
    /usr/bin/cpm /usr/bin/sudo /bin/su; do
    [[ -e "$rootfs$arquivo" && ! -L "$rootfs$arquivo" ]] || falhar "arquivo crítico ausente ou symlink: $arquivo"
    [[ "${2:-}" != --installed ]] || [[ "$(dono "$arquivo")" == 0:0 ]] || falhar "ownership crítico deve ser root:root: $arquivo"
done

[[ "$(modo /etc/passwd)" == 644 && "$(modo /etc/group)" == 644 ]] || falhar "passwd/group devem ser 0644"
[[ "$(modo /etc/shadow)" == 600 ]] || falhar "shadow deve ser 0600"
[[ "$(modo /etc/sudoers)" == 440 ]] || falhar "sudoers deve ser 0440"
[[ "$(modo /tmp)" == 1777 ]] || falhar "/tmp deve ser 1777"
[[ "$(modo /usr/bin/cpm)" == 755 ]] || falhar "cpm deve ser 0755"
[[ "$(modo /etc/cpm/repos.d/Lithos.repo)" == 644 ]] || falhar "configuração CPM deve ser 0644"
grep -Eq '^root:x:0:0:' "$rootfs/etc/passwd" || falhar "entrada root inválida em passwd"
grep -Eq '^girelli:x:1000:100:' "$rootfs/etc/passwd" || falhar "entrada girelli inválida em passwd"
grep -Eq '^wheel:x:10:girelli$' "$rootfs/etc/group" || falhar "grupo wheel inválido"
grep -Eq '^[[:space:]]*SigLevel[[:space:]]*=[[:space:]]*Required[[:space:]]*$' \
    "$rootfs/etc/cpm/repos.d/Lithos.repo" || falhar "repositório oficial não exige assinatura"

mapfile -d '' suid < <(find "$rootfs" -xdev -type f -perm /6000 -print0 | sort -z)
esperados=("$rootfs/bin/su" "$rootfs/usr/bin/sudo")
[[ "${#suid[@]}" -eq 2 ]] || falhar "quantidade inesperada de SUID/SGID: ${#suid[@]}"
for arquivo in "${esperados[@]}"; do
    printf '%s\0' "${suid[@]}" | grep -Fzx -- "$arquivo" >/dev/null || falhar "SUID esperado ausente: ${arquivo#"$rootfs"}"
    [[ "$(stat -c %a "$arquivo")" == 4755 ]] || falhar "modo SUID incorreto: ${arquivo#"$rootfs"}"
done

while IFS= read -r -d '' arquivo; do
    [[ "$arquivo" == "$rootfs/tmp" ]] || falhar "arquivo/diretório world-writable inesperado: ${arquivo#"$rootfs"}"
done < <(find "$rootfs" -xdev \( -type f -o -type d \) -perm -0002 -print0)

command -v getcap >/dev/null 2>&1 || falhar "getcap ausente; não foi possível auditar file capabilities"
arquivo_erro="$(mktemp)"
trap 'rm -f -- "$arquivo_erro"' EXIT
if ! capacidades="$(getcap -r "$rootfs" 2>"$arquivo_erro")"; then
    detalhe="$(tr '\n' ' ' < "$arquivo_erro")"
    falhar "não foi possível auditar file capabilities: ${detalhe:-getcap falhou}"
fi
if [[ -s "$arquivo_erro" ]]; then
    detalhe="$(tr '\n' ' ' < "$arquivo_erro")"
    falhar "auditoria de file capabilities foi incompleta: $detalhe"
fi
rm -f -- "$arquivo_erro"
trap - EXIT
[[ -z "$capacidades" ]] || falhar "file capabilities inesperadas: $capacidades"

# O tar do instalador normaliza tudo para root:root. Uma árvore já instalada
# deve portanto ter ownership integral de root, exceto a home do usuário.
if [[ "${2:-}" == --installed ]]; then
    while IFS= read -r -d '' arquivo; do
        case "$arquivo" in "$rootfs/home/girelli"|"$rootfs/home/girelli/"*) continue;; esac
        [[ "$(stat -c %u:%g "$arquivo")" == 0:0 ]] || falhar "ownership não-root: ${arquivo#"$rootfs"}"
    done < <(find "$rootfs" -xdev -print0)
fi

mensagem "Auditoria de segurança aprovada: somente su/sudo SUID, sem SGID/capabilities/world-writable inesperados; contas e arquivos críticos válidos."
