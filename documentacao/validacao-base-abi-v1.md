# Validação da Corelabs Base ABI v1

Registro da implementação e dos testes de 2026-10-01. O contrato, layout,
pipeline, opções e hashes completos estão em [base-abi-v1.md](base-abi-v1.md).

## Auditoria inicial

O trabalho foi limitado a `/arsenal/projetos/corelabs/CorelabsOS`. Foram lidos
`compilacao.conf`, `fontes-lfs.csv`, `biblioteca.sh`, `rootfs.sh`,
`dependencias.sh` e os compiladores existentes de Bash/OpenSSL/curl/sudo.
Também foram inspecionados `compilacao/rootfs`, builds e fontes disponíveis.

O rootfs inicial usava BusyBox e os componentes estáticos já funcionais; ainda
não tinha o loader/runtime GNU próprio. O instalador usava util-linux 2.41.1.
O pipeline existente fixa sources por SHA-256, usa diretórios de build em
`compilacao`, logs e cache por configuração. Essas convenções foram mantidas.

O worktree já estava modificado: configuração, instalação/UEFI, rede, suporte
a sudo/curl/OpenSSL, Emergency Shell e arquivos CPM. Não houve reset, commit,
push ou reversão de alterações locais. A alteração local de CPM observada
durante o build foi preservada, sem implementação funcional de CPM nesta tarefa.

GNU awk e Texinfo ausentes no host foram obtidos por extração de pacotes dentro
de `compilacao/abi-host-deps`, sem instalação global ou sudo do host.
O pipeline normal declara essas ferramentas em `scripts/dependencias.sh`.
GMP/MPFR/MPC usados pelo GCC foram compilados das fontes autenticadas e fixadas.

## Arquivos desta implementação

Criados:

- `scripts/compilar-toolchain.sh` e `scripts/compilar-base-abi.sh`.
- `scripts/auditar-elf.sh`, `scripts/testar-base-abi.sh` e
  `scripts/testar-auditoria-abi.sh`.
- `testes/base-abi/hello-corelabs.c`, `hello-corelabs-cpp.cc` e
  `verificar-sistema.sh`.
- `sistema/etc/nsswitch.conf` e `sistema/etc/ld.so.conf`.
- Os dois documentos da Base ABI.
- `.vscode/settings.json`: exclui fontes GNU/builds gerados da indexação C++,
  que estava consumindo memória em paralelo à compilação. Não altera o sistema.

Modificados nesta tarefa:

- `configuracao/compilacao.conf`, `configuracao/fontes-lfs.csv`.
- `corelabs.sh`, `scripts/rootfs.sh`, `scripts/dependencias.sh`.
- `scripts/ferramentas-instalador.sh`, referência ao novo sfdisk em
  `scripts/preparar-instalador.sh`.
- `documentacao/toolchain.md`.

As outras alterações visíveis no status pertencem ao trabalho anterior ou a
edições locais preservadas, não à implementação funcional desta ABI.

## Inspeção ELF e separação do host

Os dois programas de prova usam:

```text
PT_INTERP: /lib64/ld-linux-x86-64.so.2
C DT_NEEDED: libm.so.6, libc.so.6
C++ DT_NEEDED: libstdc++.so.6, libm.so.6, libgcc_s.so.1, libc.so.6
```

Pthread/dlopen são exercitados pelo programa C; desde glibc 2.34 fazem parte
da libc, sem exigir DT_NEEDED separado de libpthread/libdl. As bibliotecas de
compatibilidade continuam presentes. `readelf -n libc.so.6` declara ISA
necessária x86-64-baseline e ABI Linux 5.10.0. Variantes SIMD da glibc não
mudam essa ISA mínima, pois são selecionadas por dispatch em runtime.

Os logs de include/link são verificados contra os paths reais da toolchain e
do sysroot. Não foi usado `ldd` nem execução no Ubuntu como prova de runtime.
A auditoria aceita somente bibliotecas internas e rejeita paths externos.
A única exceção de RPATH é `$ORIGIN` exato nos módulos gconv manifestados,
sem PT_INTERP, resolvendo as bibliotecas auxiliares no próprio diretório.

Identificação da toolchain final:

```text
gcc -dumpmachine: x86_64-corelabs-linux-gnu
gcc -dumpfullversion: 16.2.0
ld --version: GNU ld (GNU Binutils) 2.47.20260726
```

O sufixo de revisão do Binutils acima é a identificação emitida pelo source
autenticado `binutils-2.47.tar.xz`, não uma ferramenta Ubuntu usada no lugar dele.

## Resultados

Todos os testes específicos abaixo concluíram com sucesso. A VM usa somente
o disco novo `maquinas/testes/corelabs-base-abi-v1.hhivxC/disco-descartavel.qcow2`,
QCOW2 de 40 GiB sem backing image, e uma cópia descartável de OVMF VARS. Imagens
de referência não foram usadas como alvo de instalação ou boot gravável.

| Verificação | Resultado observado |
| --- | --- |
| Pipeline oficial `./corelabs.sh rootfs` | Rootfs e initramfs construídos; auditoria final aprovada |
| Build incremental `./corelabs.sh base-abi` | Seis etapas da toolchain e runtime reaproveitados após validação |
| Auditoria runtime/rootfs | 390/398 ELF x86_64; 108 executáveis dinâmicos; 14 módulos gconv com ORIGIN local controlado |
| Provas de link/includes | Apenas toolchain/sysroot Corelabs nos inputs verificados |
| Sete fixtures negativas | Ubuntu RUNPATH, ORIGIN fora de gconv, RPATH de build, loader estrangeiro, dependência ausente, link externo e corrupção rejeitados |
| Instalador real | `CORELABS_INSTALACAO_OK`, GPT/ESP/ext4, saída QEMU 0 |
| Boot instalado | UEFI/GRUB, root por UUID canônico, login serial e getty tty1 |
| Identidade/ownership | girelli UID 1000, GID 100, wheel 10; home 1000:100:755 |
| SUID | su/sudo root:root 4755, BusyBox 755, sudoers 440 |
| Loader/glibc | `ld.so ... stable release version 2.44`; `getconf`: glibc 2.44 |
| Bash/Coreutils/util-linux | Bash 5.3.0; ls/sort 9.11; lsblk/uuidgen 2.42.2 |
| Comandos de userspace | sort, SHA-256, iconv UTF-16LE, lsblk, uuidgen e os fallbacks getopt/flock funcionais |
| Programa C dentro do Corelabs | NSS files/DNS, glibc 2.44, signal, pthread, dlopen/libm OK |
| Programa C++ dentro do Corelabs | Resultado 42, exception/unwind, libstdc++/thread OK |
| Runtime carregado | Loader `--list` resolve libc/libm/libstdc++/libgcc_s em `/usr/lib` |
| DHCP/DNS | eth0 10.0.2.15/24, gateway 10.0.2.2, DNS 10.0.2.3 no teste QEMU; resolução real de example.com |
| Rede/HTTPS | Ping 2/2; HTTP 200; HTTPS 200; certificado expirado rejeitado com curl 60 |
| sudo/su | Ambos pediram senha e produziram UID/GID 0; su retornou à sessão girelli |
| Reboot controlado | Pedido ao clcontrold, serviços encerrados, falhas 0; saída QEMU 0 |
| Boot sem NIC | Login girelli alcançado; glibc/Coreutils funcionais; rede indisponível não impede boot |
| Poweroff controlado | Encerramento normal via sudo, falhas 0; saída QEMU 0 |
| Emergency Shell pelo GRUB | Terceira entrada selecionada, BusyBox independente, shell root em ttyS0, raiz ext4 não montada; blkid/fdisk funcionais; poweroff 0 |
| Qualidade | bash -n em todos os scripts Bash; sh -n nos init/scripts ash e no teste POSIX; git diff --check aprovado |
| Verificação geral existente | `./corelabs.sh verificar` aprovado, boot de initramfs até login por 90 s |

Saída do teste executado como girelli no sistema instalado:

```text
hello-corelabs C: NSS files/DNS OK
hello-corelabs C: glibc 2.44; signal/pthread/dlopen/libm OK
hello-corelabs C++: 42; exception/unwind OK; libstdc++/thread OK
HTTP 200
HTTPS 200
curl: (60) ... certificate has expired (10)
CORELABS_BASE_ABI_V1_SISTEMA_OK
VERIFICACAO_EXIT=0
```

Os endereços 10.0.2.x são atribuídos pelo ambiente QEMU de teste, não configurados
como IP/gateway/DNS de produção. A senha da instalação descartável foi gerada
somente para o teste, enviada nos prompts sem eco e não gravada em scripts/docs.
O servidor local temporário usado para entregar as provas à VM foi encerrado.
Nenhuma prova foi adicionada ao rootfs de produção.

Logs e evidências locais preservados:

- `compilacao/logs/base-abi-assinaturas.log` e `base-abi-*.log` de cada etapa.
- `compilacao/logs/base-abi-provas.log`, `base-abi-testes-negativos.log`,
  `base-abi-incremental.log`, `base-abi-verificacao-geral.log`.
- `compilacao/testes-base-abi/`: ELF das provas, readelf, include/link traces.
- `maquinas/testes/corelabs-base-abi-v1.hhivxC/instalacao.serial.log`.
- No mesmo diretório: `boot-rede.serial.log`, `boot-sem-rede.serial.log`,
  `emergency-grub.serial.log`, `tty1-login.png`.

Warnings restantes de configure são as decisões explícitas de subset/libcap,
checks cruzados estimados por upstream e a busca irrelevante de `mt` (manifest
Windows) pelo libtool. `crypt()` e hwclock não são necessários aos programas
selecionados. Warnings do GCC bootstrap são do source upstream com o compilador
do host; não foram ocultados nem tratados como aprovação das suítes GNU.

## Limitações

Não foram executadas as suítes GNU completas, nem comprovada reprodução bit a
bit entre hosts. A toolchain é cruzada e executa no host, não foi instalada
como GCC nativo no Corelabs. Não há multilib/32 bits. Bash, sudo, curl/OpenSSL,
BusyBox e componentes próprios continuam estáticos. Coreutils não fornece
suporte ACL/xattr/libcap/SELinux nesta base. Locales adicionais não foram
gerados; os módulos de conversão gconv estão presentes.

Nenhum KDE/Qt/Mesa/Wayland/NetworkManager/systemd foi ativado. O UUID canônico
permanece `434f5245-4c41-4253-9f01-000000000001`. Não houve alteração do archive.

## Status final do worktree

Snapshot de `git status --short`, incluindo alterações pré-existentes preservadas:

```text
 M configuracao/compilacao.conf
 M configuracao/fontes-lfs.csv
 M configuracao/vm.conf
 M corelabs.sh
 M documentacao/toolchain.md
 M scripts/dependencias.sh
 M scripts/ferramentas-instalador.sh
 M scripts/instalar.sh
 M scripts/preparar-instalador.sh
 M scripts/preparar-uefi.sh
 M scripts/rootfs.sh
 M scripts/testar-persistencia.sh
 M scripts/vm.sh
 M sistema-boot/init
 M sistema-instalador/init
 M sistema/usr/lib/corelabs/rede/dhcp
?? .vscode/
?? documentacao/base-abi-v1.md
?? documentacao/validacao-base-abi-v1.md
?? scripts/auditar-elf.sh
?? scripts/compilar-base-abi.sh
?? scripts/compilar-curl.sh
?? scripts/compilar-openssl.sh
?? scripts/compilar-sudo.sh
?? scripts/compilar-toolchain.sh
?? scripts/preparar-emergencia.sh
?? scripts/testar-auditoria-abi.sh
?? scripts/testar-base-abi.sh
?? sistema-emergencia/
?? sistema/etc/cpm/
?? sistema/etc/ld.so.conf
?? sistema/etc/nsswitch.conf
?? sistema/etc/sudoers
?? sistema/root/
?? sistema/usr/bin/cpm
?? testes/base-abi/
```
