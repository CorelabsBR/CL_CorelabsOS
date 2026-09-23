#!/usr/bin/env bash
set -Eeuo pipefail
RAIZ="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=biblioteca.sh
source "$RAIZ/scripts/biblioteca.sh"

command -v apt-get >/dev/null 2>&1 || erro "instalação automática disponível apenas em hosts Debian/Ubuntu"
pacotes=(build-essential bc bison flex m4 libelf-dev libssl-dev cpio curl xz-utils bzip2 qemu-system-x86 qemu-utils file rsync)
executor=()
if (( EUID != 0 )); then
    command -v sudo >/dev/null 2>&1 || erro "sudo é necessário apenas para instalar pacotes do host"
    executor=(sudo)
fi
mensagem "Instalando dependências de compilação e virtualização"
"${executor[@]}" apt-get update
"${executor[@]}" apt-get install --no-install-recommends "${pacotes[@]}"
