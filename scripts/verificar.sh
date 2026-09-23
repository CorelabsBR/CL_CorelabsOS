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

dependencias=(bash make gcc bison flex m4 curl sha256sum tar cpio gzip qemu-system-x86_64 qemu-img file rsync)
for comando in "${dependencias[@]}"; do
    command -v "$comando" >/dev/null 2>&1 && ok "dependência: $comando" || falhou "dependência ausente: $comando"
done
if printf '#include <libelf.h>\n' | gcc -E - >/dev/null 2>&1; then
    ok "cabeçalhos de desenvolvimento: libelf"
else
    falhou "cabeçalhos de desenvolvimento ausentes: libelf-dev"
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

kernel="$COMPILACAO/kernel/bzImage"
initramfs="$IMAGENS/corelabs-initramfs.cpio.gz"
disco="$MAQUINAS/corelabs.qcow2"
[[ -s "$kernel" ]] && file "$kernel" | grep -q 'Linux kernel x86 boot executable' \
    && ok "kernel x86 válido" || falhou "kernel compilado inválido ou ausente"
if [[ -s "$initramfs" ]] && gzip -t "$initramfs"; then
    if gzip -dc "$initramfs" | cpio -t 2>/dev/null | grep -Eq '^(\./)?init$'; then
        ok "initramfs newc válido com /init"
    else
        falhou "initramfs não contém /init"
    fi
else
    falhou "initramfs inválido ou ausente"
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
    { sleep 3; printf 'echo CONSOLE_CORELABS_OK\npoweroff -f\n'; } | timeout --signal=TERM "$VM_TIMEOUT_TESTE" \
        qemu-system-x86_64 -machine q35 "${aceleracao[@]}" -m 512 -smp 1 \
        -kernel "$kernel" -initrd "$initramfs" \
        -append "console=ttyS0,115200 rdinit=/init panic=-1" \
        -nodefaults -serial stdio -display none -no-reboot >"$log_teste" 2>&1
    codigo=$?
    set -e
    grep -q 'Corelabs OS' "$log_teste" && ok "banner exibido" || falhou "banner não apareceu no boot"
    tr -d '\r' < "$log_teste" | grep -qx 'CONSOLE_CORELABS_OK' \
        && ok "console interativo executou um comando" || falhou "console não executou o comando de teste"
    grep -Eq 'Power down|reboot: Power down' "$log_teste" && ok "desligamento concluído" || falhou "desligamento não foi confirmado"
    (( codigo == 0 )) || falhou "QEMU terminou com código $codigo"
fi

(( falhas == 0 )) || erro "$falhas verificação(ões) falharam"
mensagem "Todas as verificações passaram"
