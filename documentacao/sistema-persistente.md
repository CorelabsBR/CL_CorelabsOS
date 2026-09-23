# Sistema persistente e boot UEFI

## Construção e instalação

```bash
./corelabs.sh dependencias
./corelabs.sh compilar
./corelabs.sh instalar
```

`instalar` prepara ferramentas estáticas, initramfs e GRUB, inspeciona o disco em uma VM com modo snapshot e mostra o conteúdo encontrado. Só depois solicita a frase `INSTALAR CORELABS`. A confirmação autoriza o reparticionamento exclusivo de `maquinas/corelabs.qcow2`.

O instalador cria GPT com uma ESP FAT32 de 256 MiB e uma partição ext4 ocupando o restante. A raiz usa o UUID fixo configurado em `configuracao/vm.conf`. O GRUB EFI é instalado no caminho removível `EFI/BOOT/BOOTX64.EFI`, encontra a raiz pelo UUID e carrega o kernel e o initramfs de transição.

O initramfs de transição monta `devtmpfs`, procura o UUID com `blkid`, monta a raiz ext4 em modo leitura e escrita e executa `switch_root`. A partir desse ponto, `/init` do disco assume como PID 1.

## Inicialização e recuperação

```bash
./corelabs.sh iniciar
./corelabs.sh iniciar --grafico
./corelabs.sh iniciar --recuperacao
```

O boot normal usa OVMF e preserva as variáveis UEFI em `maquinas/OVMF_VARS.fd`. Recuperação mantém o boot direto do kernel e do initramfs da Fase 0.

## Teste de persistência

```bash
./corelabs.sh testar-persistencia
```

O teste faz dois boots UEFI completos. No primeiro cria `/root/prova-persistencia`, sincroniza e desliga. No segundo lê o arquivo e exige o mesmo token. Logs separados ficam em `compilacao/logs/persistencia-gravacao.log` e `compilacao/logs/persistencia-leitura.log`.

## Segurança

Nenhum `loop device`, NBD ou disco físico do host é usado. A imagem aparece como `/dev/vda` somente dentro da VM instaladora. O caminho do QCOW2 é validado antes do processo, a inspeção usa snapshot e a confirmação não aceita respostas abreviadas.

