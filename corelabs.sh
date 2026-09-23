#!/usr/bin/env bash
set -Eeuo pipefail

RAIZ="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

mostrar_ajuda() {
    cat <<'EOF'
Uso: ./corelabs.sh <comando> [opções]

Comandos:
  dependencias       Instala as dependências no host Debian/Ubuntu
  compilar           Compila kernel, rootfs, initramfs e cria o disco
  kernel [--forcar]  Compila o kernel; --forcar refaz a compilação
  rootfs             Compila o BusyBox e monta o sistema mínimo
  imagem             Cria o disco QCOW2 persistente, se estiver ausente
  instalar           Instala o sistema no QCOW2 após confirmação explícita
  iniciar [--grafico] Inicializa o sistema instalado por UEFI
  iniciar --recuperacao Inicializa diretamente a Fase 0
  testar-persistencia Testa gravação e leitura após reinicialização
  verificar          Verifica artefatos e realiza o teste de boot
  limpar             Remove artefatos gerados após confirmação
  ajuda               Mostra esta ajuda
EOF
}

comando="${1:-ajuda}"
shift || true

case "$comando" in
    dependencias) exec "$RAIZ/scripts/dependencias.sh" "$@" ;;
    compilar)
        "$RAIZ/scripts/kernel.sh"
        "$RAIZ/scripts/rootfs.sh"
        "$RAIZ/scripts/initramfs.sh"
        "$RAIZ/scripts/imagem.sh"
        ;;
    kernel) exec "$RAIZ/scripts/kernel.sh" "$@" ;;
    rootfs)
        "$RAIZ/scripts/rootfs.sh" "$@"
        "$RAIZ/scripts/initramfs.sh"
        ;;
    imagem) exec "$RAIZ/scripts/imagem.sh" "$@" ;;
    instalar) exec "$RAIZ/scripts/instalar.sh" "$@" ;;
    iniciar) exec "$RAIZ/scripts/vm.sh" "$@" ;;
    testar-persistencia) exec "$RAIZ/scripts/testar-persistencia.sh" "$@" ;;
    verificar) exec "$RAIZ/scripts/verificar.sh" "$@" ;;
    limpar) exec "$RAIZ/scripts/limpar.sh" "$@" ;;
    ajuda|-h|--help) mostrar_ajuda ;;
    *) printf 'Erro: comando desconhecido: %s\n\n' "$comando" >&2; mostrar_ajuda >&2; exit 2 ;;
esac
