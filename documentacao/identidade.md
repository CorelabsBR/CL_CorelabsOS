# Identidade oficial Corelabs OS 0.3 Forge

A identidade é mantida nos arquivos de origem do rootfs e aplicada tanto a novas instalações quanto a sistemas persistentes existentes.

## Arquivos instalados

- `/usr/lib/os-release`: identificação oficial e URLs do projeto.
- `/etc/os-release`: link relativo para `../usr/lib/os-release` em instalações sem sobreposição administrativa.
- `/etc/hostname`: hostname padrão `corelabs`.
- `/etc/corelabs/logo.ascii`: cópia exata de `branding/system/ascii.txt`.
- `/usr/share/pixmaps/corelabs-logo.svg`: cópia exata de `branding/system/oslogo.svg`.
- `/usr/lib/corelabs/banner`: renderizador do banner.
- `/etc/corelabs/banner.conf`: configuração local das cores.
- `/etc/issue` e `/etc/motd`: identificação textual sem duplicação da logo.

O banner não usa cores por padrão. Para habilitar o vermelho Corelabs para `@` e o vermelho-claro para `%`, defina `cores=1` em `/etc/corelabs/banner.conf`. As sequências ANSI só são emitidas quando a saída é um terminal.

## Construção e atualização

`scripts/rootfs.sh` copia os ativos oficiais para todo rootfs novo. Para atualizar uma instalação existente sem modificar GPT, partições, filesystems ou UUIDs:

```bash
./corelabs.sh atualizar-identidade
```

O atualizador inicializa um ambiente temporário, monta a partição ext4 existente pelo UUID e altera somente arquivos de identidade gerenciados. Um `/etc/os-release` administrativo, hostname personalizado, `motd`, `issue` ou ASCII diferente é preservado. Arquivos em `/usr/lib` e `/usr/share` são os padrões fornecidos pelo sistema.

O instalador destrutivo não participa dessa atualização.

