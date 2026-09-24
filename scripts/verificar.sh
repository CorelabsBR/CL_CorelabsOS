#!/usr/bin/env bash
set -Eeuo pipefail
RAIZ="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=biblioteca.sh
source "$RAIZ/scripts/biblioteca.sh"
# shellcheck source=../configuracao/vm.conf
source "$RAIZ/configuracao/vm.conf"

falhas=0
ok() { printf '[ OK ] %s\n' "$*"; }
falhou() { printf '[FALHA] %s\n' "$*" >&2; falhas=$((falhas + 1)); }
aviso() { printf '[AVISO] %s\n' "$*" >&2; }

dependencias=(bash make gcc curl sha256sum tar cpio gzip qemu-system-x86_64 qemu-img grub-mkstandalone file rsync)
for comando in "${dependencias[@]}"; do
    command -v "$comando" >/dev/null 2>&1 && ok "dependência: $comando" || falhou "dependência ausente: $comando"
done
for comando in bison flex m4; do
    command -v "$comando" >/dev/null 2>&1 \
        && ok "dependência de reconstrução: $comando" \
        || aviso "dependência de reconstrução ausente: $comando"
done
if printf '#include <libelf.h>\n' | gcc -E - >/dev/null 2>&1; then
    ok "cabeçalhos de desenvolvimento: libelf"
else
    aviso "cabeçalhos de reconstrução ausentes: libelf-dev"
fi

verificar_hash() {
    local arquivo="$1" hash="$2"
    if [[ -f "$arquivo" ]]; then
        printf '%s  %s\n' "$hash" "$arquivo" | sha256sum --check --status \
            && ok "fonte íntegra: $(basename -- "$arquivo")" \
            || falhou "fonte corrompida: $(basename -- "$arquivo")"
    else
        falhou "fonte ausente: $(basename -- "$arquivo")"
    fi
}
verificar_hash "$FONTES/linux-$KERNEL_VERSAO.tar.xz" "$KERNEL_SHA256"
verificar_hash "$FONTES/busybox-$BUSYBOX_VERSAO.tar.bz2" "$BUSYBOX_SHA256"
[[ ! -f "$FONTES/e2fsprogs-$E2FSPROGS_VERSAO.tar.xz" ]] || \
    verificar_hash "$FONTES/e2fsprogs-$E2FSPROGS_VERSAO.tar.xz" "$E2FSPROGS_SHA256"
[[ ! -f "$FONTES/util-linux-$UTIL_LINUX_VERSAO.tar.xz" ]] || \
    verificar_hash "$FONTES/util-linux-$UTIL_LINUX_VERSAO.tar.xz" "$UTIL_LINUX_SHA256"

kernel="$COMPILACAO/kernel/bzImage"
initramfs="$IMAGENS/corelabs-initramfs.cpio.gz"
disco="$MAQUINAS/corelabs.qcow2"
[[ -s "$kernel" ]] && file "$kernel" | grep -q 'Linux kernel x86 boot executable' \
    && ok "kernel x86 válido" || falhou "kernel compilado inválido ou ausente"
if [[ -s "$initramfs" ]] && gzip -t "$initramfs"; then
    conteudo_initramfs="$(gzip -dc "$initramfs" | cpio -t 2>/dev/null)"
    if grep -Eq '^(\./)?init$' <<< "$conteudo_initramfs"; then
        ok "initramfs newc válido com /init"
    else
        falhou "initramfs não contém /init"
    fi
else
    falhou "initramfs inválido ou ausente"
fi
if [[ -s "$IMAGENS/corelabs-instalador.cpio.gz" ]]; then
    gzip -t "$IMAGENS/corelabs-instalador.cpio.gz" \
        && ok "initramfs instalador válido" || falhou "initramfs instalador corrompido"
fi
if [[ -s "$IMAGENS/corelabs-initramfs-disco.cpio.gz" ]]; then
    gzip -t "$IMAGENS/corelabs-initramfs-disco.cpio.gz" \
        && ok "initramfs de transição válido" || falhou "initramfs de transição corrompido"
fi
if [[ -f "$disco" ]] && qemu-img info --output=json "$disco" | grep -q '"format": "qcow2"'; then
    ok "disco QCOW2 válido"
else
    falhou "disco QCOW2 inválido ou ausente"
fi

if (( falhas == 0 )); then
    log_teste="$LOGS/teste-boot.log"
    aceleracao=(-accel tcg,thread=multi -cpu max)
    [[ -r /dev/kvm && -w /dev/kvm ]] && aceleracao=(-accel kvm -cpu host)
    mensagem "Executando boot real no QEMU (timeout de ${VM_TIMEOUT_TESTE}s)"
    set +e
    timeout --signal=TERM "$VM_TIMEOUT_TESTE" \
        qemu-system-x86_64 -machine q35 "${aceleracao[@]}" -m 512 -smp 1 \
        -kernel "$kernel" -initrd "$initramfs" \
        -append "console=ttyS0,115200 rdinit=/init panic=-1" \
        -nodefaults -serial stdio -display none -no-reboot </dev/null >"$log_teste" 2>&1
    codigo=$?
    set -e

    grep -q 'Corelabs OS' "$log_teste" \
        && ok "banner exibido" \
        || falhou "banner não apareceu no boot"

    grep -Eq 'corelabs login:|login:' "$log_teste" \
        && ok "getty/login disponível no console serial" \
        || falhou "prompt de login não apareceu no console serial"

    if (( codigo == 124 )); then
        ok "sistema permaneceu ativo aguardando autenticação"
    elif (( codigo == 0 )); then
        ok "QEMU encerrou normalmente"
    else
        falhou "QEMU terminou inesperadamente com código $codigo"
    fi
fi

(( falhas == 0 )) || erro "$falhas verificação(ões) falharam"
mensagem "Todas as verificações passaram"
