#!/usr/bin/env bash
set -Eeuo pipefail
RAIZ="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$RAIZ/scripts/biblioteca.sh"
for cmd in gcc python3 sh; do exigir_comando "$cmd"; done
mkdir -p "$COMPILACAO/cpm" "$LOGS"
# Native host test helper is never installed. Production uses compilar-cpm.sh.
gcc -std=c11 -O2 -Wall -Wextra -Werror -o "$COMPILACAO/cpm/arquivo-host-testes" "$FONTES/cpm/arquivo.c"
python3 "$RAIZ/testes/cpm/testar.py" | tee "$LOGS/cpm-unitarios.log"
