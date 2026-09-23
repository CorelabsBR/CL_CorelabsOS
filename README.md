# Corelabs OS

Corelabs OS é uma base Linux independente e experimental. A Fase 1 compila um kernel Linux oficial e um BusyBox estático, monta um rootfs mínimo em initramfs e o inicializa diretamente no QEMU/KVM. Nenhum rootfs da distribuição hospedeira é copiado.

## Primeira compilação

Em Kubuntu 24.04:

```bash
./corelabs.sh dependencias
./corelabs.sh compilar
./corelabs.sh verificar
./corelabs.sh iniciar
```

A primeira compilação baixa aproximadamente as fontes do Linux e do BusyBox e pode demorar. Downloads são aceitos apenas após validação SHA-256. Compilações seguintes reutilizam fontes e objetos. Para refazer o kernel por completo, use `./corelabs.sh kernel --forcar`.

O console usa a porta serial. Para desligar, execute `poweroff`; para reiniciar, `reboot`. O monitor QEMU compartilha o terminal e pode ser acessado com `Ctrl+A`, seguido de `C`; `Ctrl+A`, seguido de `X`, encerra a VM. A opção `./corelabs.sh iniciar --grafico` abre uma janela de vídeo, mas o terminal continua na serial.

O disco `maquinas/corelabs.qcow2` tem 40 GB e é preservado entre boots. Nesta fase ele está vazio: arquivos alterados no rootfs em memória não persistem.

Configurações de compilação ficam em `configuracao/compilacao.conf`; memória, vCPUs, tamanho inicial do disco e timeout ficam em `configuracao/vm.conf`. Consulte [a documentação técnica](documentacao/fase1.md) para arquitetura, atualização e diagnóstico.

## Comandos

Execute `./corelabs.sh ajuda` para ver a interface completa. Os alvos equivalentes também estão disponíveis no `Makefile`.

