<div align="center">

<img src="./branding/system/oslogo.svg" alt="Corelabs OS" width="220" />

# Corelabs OS

**Linux independente, open source e experimental.**

*Versão 0.3 "Forge"*

</div>

---

## Sobre

Corelabs OS é uma base Linux construída do zero, sem copiar o rootfs da distribuição hospedeira. A **Fase 1** entrega:

- 🐧 kernel Linux oficial compilado a partir das fontes;
- 🧰 BusyBox estático como userland;
- 💾 rootfs em **ext4** dentro de um disco **QCOW2** persistente;
- 🚀 boot via **GRUB** e firmware UEFI (**OVMF**), rodando no QEMU.

> ⚠️ **Status: experimental.** Não é pensado para uso em produção.

## Início rápido

Testado em **Kubuntu 24.04**.

```bash
./corelabs.sh dependencias         # instala as dependências do host
./corelabs.sh compilar             # compila kernel e BusyBox
./corelabs.sh verificar            # confere os artefatos gerados
./corelabs.sh instalar             # cria o disco e instala o sistema
./corelabs.sh iniciar              # inicia a VM
./corelabs.sh testar-persistencia  # valida que os dados sobrevivem ao reboot
```

**Sobre a primeira compilação**

- Ela baixa as fontes do Linux e do BusyBox, então pode demorar.
- Todo download só é aceito após validação **SHA-256**.
- As próximas compilações reaproveitam fontes e objetos.
- Para refazer o kernel por completo: `./corelabs.sh kernel --forcar`.

## Usando a VM

O console funciona pela **porta serial**. Dentro da VM, use `poweroff` para desligar e `reboot` para reiniciar.

| Atalho | Ação |
|---|---|
| `Ctrl+A`, depois `C` | Abre o monitor QEMU (compartilha o terminal) |
| `Ctrl+A`, depois `X` | Encerra a VM |

Para abrir uma janela de vídeo, use `./corelabs.sh iniciar --grafico`. O terminal continua na serial.

## Disco e instalação

- O disco `maquinas/corelabs.qcow2` tem **40 GB** e é preservado entre boots.
- O comando `instalar` pede **confirmação explícita** antes de criar a tabela GPT, a ESP (FAT32) e a raiz (ext4).

## Configuração

| Arquivo | Controla |
|---|---|
| `configuracao/compilacao.conf` | Parâmetros de compilação |
| `configuracao/vm.conf` | Memória, vCPUs, tamanho inicial do disco e timeout |

## Documentação

| Documento | Assunto |
|---|---|
| [Fase 1](documentacao/fase1.md) | Documentação técnica |
| [Toolchain](documentacao/toolchain.md) | Estratégia de toolchain |
| [Sistema persistente](documentacao/sistema-persistente.md) | Disco, partições e persistência |
| [Identidade](documentacao/identidade.md) | Arquivos instalados, cores opcionais e atualização não destrutiva |

## Comandos

Execute `./corelabs.sh ajuda` para ver a interface completa. Os alvos equivalentes também estão no `Makefile`.