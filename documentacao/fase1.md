# Corelabs OS — arquitetura da Fase 1

## Componentes e fluxo de boot

`corelabs.sh` encaminha cada operação aos scripts em `scripts/`. As fontes oficiais verificadas ficam em `fontes/`, objetos e logs em `compilacao/`, o initramfs em `imagens/` e o disco da VM em `maquinas/`. Esses diretórios de artefatos não são versionados.

O kernel x86_64 parte de `x86_64_defconfig` e recebe o fragmento `configuracao/kernel.config`. Drivers essenciais ao boot são embutidos: initramfs, devtmpfs, ext4, virtio block/rede, procfs, sysfs, tmpfs e console serial 8250. Módulos estão desativados nesta fase.

O BusyBox é compilado estaticamente. `scripts/rootfs.sh` instala seus applets e sobrepõe os arquivos próprios de `sistema/`. O PID 1, `sistema/init`, monta `/dev`, `/proc`, `/sys`, `/run` e `/tmp`, define o hostname, exibe o banner e abre um shell com terminal de controle. Ao sair do shell, o sistema sincroniza e desliga.

QEMU carrega diretamente `compilacao/kernel/bzImage` e `imagens/corelabs-initramfs.cpio.gz`. Usa KVM quando `/dev/kvm` está acessível e TCG nos demais casos. A rede é NAT do tipo user networking. O QCOW2 é ligado via virtio, mas ainda não é montado pelo sistema.

## Dependências do host

No Kubuntu 24.04, `./corelabs.sh dependencias` instala compilador, ferramentas do kernel, cpio, utilitários de compactação e QEMU. O script usa privilégios somente para `apt-get`; compilação e VM rodam como usuário comum. Para conferir manualmente, execute `./corelabs.sh verificar`.

## Compilação e execução

```bash
./corelabs.sh compilar
./corelabs.sh verificar
./corelabs.sh iniciar
```

Use `./corelabs.sh iniciar --grafico` se desejar a janela QEMU. Edite `VM_MEMORIA_MB` e `VM_CPUS` em `configuracao/vm.conf` para ajustar os recursos. `LIMITE_NUCLEOS` em `configuracao/compilacao.conf` limita o paralelismo; zero usa todos os núcleos disponíveis.

## Atualização do kernel

Consulte `kernel.org`, escolha uma versão estável ou LTS e altere `KERNEL_VERSAO`, `KERNEL_URL` e `KERNEL_SHA256` juntos. Obtenha o hash no arquivo `sha256sums.asc` do mesmo diretório oficial. Depois execute:

```bash
./corelabs.sh kernel --forcar
./scripts/initramfs.sh
./corelabs.sh verificar
```

Opções adicionais do kernel devem entrar em `configuracao/kernel.config`. A compilação normal compara a configuração e preserva objetos; `--forcar` descarta apenas os objetos do kernel daquela versão.

## Estrutura do rootfs

Os arquivos mantidos pelo projeto ficam em `sistema/`. O rootfs gerado fica em `compilacao/rootfs` e também contém os applets instalados pelo BusyBox. Para reconstruí-lo e atualizar o initramfs, execute `./corelabs.sh rootfs`.

## Verificação e diagnóstico

`./corelabs.sh verificar` confere comandos do host, hashes dos downloads, formato do kernel, conteúdo do initramfs, formato do QCOW2 e um boot real com timeout. O teste envia um marcador ao shell e solicita desligamento; sua saída fica em `compilacao/logs/teste-boot.log`.

Falhas de compilação ficam em `compilacao/logs/kernel.log` e `compilacao/logs/rootfs.log`. Se o KVM não for usado, confira permissões de `/dev/kvm` e participação no grupo `kvm`; TCG funciona sem isso, com menor desempenho. Para recuperar artefatos inconsistentes, use `./corelabs.sh limpar` e recompile. A limpeza pede confirmação e preserva fontes e o disco.

## Próximas etapas

Fases futuras podem particionar e montar o disco persistente, criar uma instalação em disco, adotar um init mais completo e adicionar gerenciamento de pacotes e ambiente gráfico. Esses componentes estão deliberadamente fora da Fase 1.

