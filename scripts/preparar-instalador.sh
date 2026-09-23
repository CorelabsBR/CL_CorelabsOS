#!/usr/bin/env bash
set -Eeuo pipefail
RAIZ="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=biblioteca.sh
source "$RAIZ/scripts/biblioteca.sh"
# shellcheck source=../configuracao/vm.conf
source "$RAIZ/configuracao/vm.conf"
trap 'erro "a preparação do instalador falhou; consulte $LOGS/preparar-instalador.log"' ERR

for comando in cpio gzip tar grub-mkstandalone sed file; do exigir_comando "$comando"; done
preparar_diretorios
"$RAIZ/scripts/rootfs.sh"
"$RAIZ/scripts/kernel.sh"
"$RAIZ/scripts/ferramentas-instalador.sh"

log="$LOGS/preparar-instalador.log"
: > "$log"
saida="$COMPILACAO/instalador"
rm -rf -- "$saida.tmp"
mkdir -p -- "$saida.tmp" "$IMAGENS"

montar_busybox() {
    local destino="$1"
    mkdir -p -- "$destino"/{dev,proc,sys,run,tmp,root,mnt,etc,usr,var,home,opt}
    make -C "$FONTES/busybox-$BUSYBOX_VERSAO" O="$COMPILACAO/busybox" \
        CONFIG_PREFIX="$destino" install >> "$log" 2>&1
    chmod 1777 "$destino/tmp"
}

mensagem "Criando initramfs de transição para a raiz persistente"
transicao="$saida.tmp/transicao"
montar_busybox "$transicao"
cp -- "$RAIZ/sistema-boot/init" "$transicao/init"
chmod 0755 "$transicao/init"
(
    cd "$transicao"
    find . -print0 | LC_ALL=C sort -z | cpio --null -o --format=newc --owner=0:0 2>/dev/null | gzip -9
) > "$IMAGENS/corelabs-initramfs-disco.cpio.gz"

mensagem "Criando carregador GRUB EFI autônomo"
grub_cfg="$saida.tmp/grub.cfg"
cat > "$grub_cfg" <<EOF
serial --unit=0 --speed=115200
terminal_input serial
terminal_output serial
set timeout=0
set default=0
menuentry 'Corelabs OS' {
    search --no-floppy --fs-uuid --set=raiz $VM_RAIZ_UUID
    linux (\$raiz)/boot/vmlinuz-corelabs root=UUID=$VM_RAIZ_UUID rw console=ttyS0,115200
    initrd (\$raiz)/boot/initramfs-corelabs.cpio.gz
}
EOF
grub-mkstandalone -O x86_64-efi -o "$saida.tmp/BOOTX64.EFI" \
    --modules="part_gpt fat ext2 normal linux search search_fs_uuid serial terminal" \
    "boot/grub/grub.cfg=$grub_cfg" >> "$log" 2>&1

mensagem "Empacotando rootfs instalado"
rootfs_pacote="$saida.tmp/rootfs.tar.gz"
tar --sort=name --numeric-owner --owner=0 --group=0 -czf "$rootfs_pacote" \
    -C "$COMPILACAO/rootfs" .

mensagem "Criando ambiente instalador"
ambiente="$saida.tmp/ambiente"
montar_busybox "$ambiente"
cp -- "$RAIZ/sistema-instalador/init" "$ambiente/init"
sed -i "s/@RAIZ_UUID@/$VM_RAIZ_UUID/g" "$ambiente/init"
chmod 0755 "$ambiente/init"
rm -f -- "$ambiente/sbin/mke2fs" "$ambiente/sbin/sfdisk"
cp -- "$COMPILACAO/e2fsprogs/misc/mke2fs.static" "$ambiente/sbin/mke2fs"
cp -- "$COMPILACAO/util-linux/sfdisk.static" "$ambiente/sbin/sfdisk"
cp -- "$COMPILACAO/e2fsprogs/misc/mke2fs.conf" "$ambiente/etc/mke2fs.conf"
mkdir -p -- "$ambiente/opt/corelabs"
cp -- "$rootfs_pacote" "$ambiente/opt/corelabs/rootfs.tar.gz"
cp -- "$COMPILACAO/kernel/bzImage" "$ambiente/opt/corelabs/vmlinuz"
cp -- "$IMAGENS/corelabs-initramfs-disco.cpio.gz" "$ambiente/opt/corelabs/initramfs-disco.cpio.gz"
cp -- "$saida.tmp/BOOTX64.EFI" "$ambiente/opt/corelabs/BOOTX64.EFI"
(
    cd "$ambiente"
    find . -print0 | LC_ALL=C sort -z | cpio --null -o --format=newc --owner=0:0 2>/dev/null | gzip -9
) > "$IMAGENS/corelabs-instalador.cpio.gz"

rm -rf -- "$saida"
mv -- "$saida.tmp" "$saida"
mensagem "Instalador preparado: $IMAGENS/corelabs-instalador.cpio.gz"
