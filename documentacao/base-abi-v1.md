# Corelabs Base ABI v1

Estado: implementada e validada em instalação descartável, com boot UEFI/GRUB,
provas C/C++, rede/HTTPS, autenticação e Emergency Shell. Resultados e limites
em [validacao-base-abi-v1.md](validacao-base-abi-v1.md).

## Contrato

| Item | Valor |
| --- | --- |
| Arquitetura | x86_64, little-endian, ELF64, GNU/glibc, somente 64 bits |
| Target GNU | `x86_64-corelabs-linux-gnu` |
| libc | glibc 2.44 + upstream_fixes-2 e FHS do LFS |
| Loader ELF | `/lib64/ld-linux-x86-64.so.2` |
| Compilador e runtime | GCC 16.2.0, C/C++, libgcc_s, libstdc++, libatomic |
| Binutils | 2.47 |
| Coreutils | 9.11 |
| Util-linux | 2.42.2, subset: lsblk e uuidgen |
| Shell de sessão | Bash 5.3, mantido estático |
| Headers Linux | 6.12.111, exportados do source controlado pelo projeto |
| Kernel mínimo da glibc | Linux 5.10; kernel ativo permanece 6.12.111 |

`corelabs` é o campo vendor do triple GNU, aceito pelo `config.sub` dos sources.
CPU e sistema permanecem `x86_64` e `linux-gnu`. O triple diferente do host força
compilação cruzada, mesmo quando ambos usam CPU x86_64. Nenhuma extensão própria
é adicionada à ABI ELF, à convenção de chamada ou ao formato das bibliotecas.

## Construção e separação do host

`./corelabs.sh base-abi` constrói a plataforma; `./corelabs.sh rootfs` a integra
automaticamente e regenera o initramfs. Logs ficam em
`compilacao/logs/base-abi-*.log`. As dependências adicionais do host são GNU awk,
Texinfo, patch e Python 3. GMP/MPFR/MPC são fontes fixadas e compiladas dentro do
GCC para bootstrap, sem bibliotecas desses componentes no runtime Corelabs.

O pipeline é:

1. Binutils cruzado com `--with-sysroot` e target Corelabs.
2. GCC C inicial sem headers/libc, libgcc estático para construir glibc,
   com PIE/SSP padrão e Binutils cruzado disponível durante configure e make.
3. `make headers_install` do kernel 6.12.111 no sysroot; não recompila o kernel.
4. glibc cruzada com os headers e o GCC inicial. Instalação com `DESTDIR`.
5. GCC C/C++ final cruzado, agora com libc/headers completos: libgcc_s,
   libstdc++ e libatomic compilados para Corelabs. PIE/SSP habilitados por padrão.
6. Coreutils e util-linux compilados pelo GCC final contra o sysroot.
7. Seleção dos runtimes e auditoria ELF antes de publicar o rootfs.

A toolchain executa no host para construir programas Corelabs. Ela não é um
compilador nativo instalado dentro do sistema; seus executáveis podem depender
do host. Seus **produtos target** usam exclusivamente o sysroot Corelabs.
Construir um GCC nativo dentro do Corelabs não faz parte deste contrato.

`compilacao/toolchain` e `compilacao/sysroot` são links para uma geração de
`compilacao/base-abi/<hash>/`. O hash inclui versões, hashes das fontes/patches e
kernel. Marcas encadeadas por receita invalidam a etapa alterada e suas
dependentes. Uma geração anterior continua disponível quando há falha antes da
publicação. Um build interrompido de GCC só é retomado quando os argumentos
configure normalizados coincidem; mudanças de opções refazem seu diretório.
Builds e fontes modificadas ficam dentro da geração; tarballs
verificados ficam em `fontes/`. Os sources extraídos originais não recebem os
patches/mudanças da toolchain.

Variáveis externas de include/busca de bibliotecas são removidas. O ambiente de
pkg-config aponta somente para o sysroot. Não se copia loader, libc, headers ou
runtime GCC do Ubuntu. Os trace logs das provas C/C++ verificam também os
arquivos efetivamente utilizados pelo linker, além dos SONAMEs do ELF.

## Layout

Sysroot de desenvolvimento:

- `usr/include`: headers Linux e glibc.
- `usr/lib`: glibc, startup objects, archives e runtime GCC.
- `lib -> usr/lib`.
- `lib64/ld-linux-x86-64.so.2 -> ../usr/lib/ld-linux-x86-64.so.2`.
- Toolchain separada contém compiladores, Binutils e headers C++ do target.

Rootfs de runtime:

- Mesmos paths de loader e bibliotecas, sem toolchain, headers ou archives `.a`.
- GNU Coreutils em `/usr/bin`, com links de applets existentes em `/bin`
  encaminhados à implementação GNU correspondente.
- BusyBox explícito em `/bin/busybox`; `/bin/sh` continua BusyBox ash.
- `lsblk`, `uuidgen` e libuuid/libblkid/libmount/libsmartcols de util-linux.
- `ldconfig` da glibc em `/usr/sbin`; busca padrão das bibliotecas em `/usr/lib`.
- `getconf`, `getent`, `iconv` e módulos `gconv` construídos com a glibc própria.
- `/etc/nsswitch.conf`: identidades por arquivos e hosts por arquivos/DNS.
- `/usr/share/corelabs/base-abi-v1.sha256`: fingerprints do runtime produzido.

Desde glibc 2.34, funções de libpthread/libdl estão integradas à libc. As
bibliotecas de compatibilidade `libpthread.so.0` e `libdl.so.2` continuam
presentes; um programa novo com pthread/dlopen pode declarar apenas libc em
DT_NEEDED. Isso não significa falta de suporte a threads/dlopen.

## Configurações de userspace

Coreutils usa `--prefix=/usr --libexecdir=/usr/libexec --disable-nls`, sem
GMP, libcap, ACLs, atributos estendidos, OpenSSL ou SELinux. `kill` e `uptime` permanecem BusyBox. São
instalados os demais comandos normais do pacote, sem substituir su/sudo ou os
wrappers de encerramento do Corelabs.

Util-linux usa `--disable-all-programs` e habilita somente libuuid, libblkid,
libmount (dependência obrigatória de lsblk), libsmartcols, uuidgen e lsblk. Bibliotecas compartilhadas,
`--disable-static --disable-nls`, sem systemd, Python, ncurses ou readline.
Não substitui mount, umount, login, getty, su, shutdown, reboot ou switch_root.
`flock` e `getopt` permanecem BusyBox: o configure de util-linux 2.42.2 não
oferece flags individuais para reativá-los com `--disable-all-programs`.
O sfdisk **do instalador** também passa à versão 2.42.2, continuando estático e
em diretório separado do util-linux de runtime.

Continuam estáticos: BusyBox, cópia dedicada SUID de su, Bash, sudo, curl
(OpenSSL incorporado), clsupervisor, clcontrold e clcontrol; as ferramentas e
BusyBox do instalador/transição/emergência. Emergency Shell continua independente
da base dinâmica e da rede.

## Fontes e autenticidade

Os hashes e URLs completos estão em `configuracao/compilacao.conf`.

| Fonte | SHA-256 |
| --- | --- |
| binutils-2.47.tar.xz | `154ab23b60070e8f27013c22977f1129425d67d1e8acd6e13010e617811e4cff` |
| gcc-16.2.0.tar.xz | `e6738e29597f733270731aa90600f37ffdc045079dfc27ec7e8192cc81085c3e` |
| glibc-2.44.tar.xz | `37f600f2bef3c5e8300147059568b2a2e40a7ad6ccc65ce942556d49429cc667` |
| coreutils-9.11.tar.xz | `394024eda0a5955217ceda9cd1201e65dc8fa3aa29c2951135a49521d57c3cc3` |
| util-linux-2.42.2.tar.xz | `03a05d3adf9602ef128f2da05b84b3205ce60c351e5737c0370f74000679ce8a` |
| glibc-2.44-upstream_fixes-2.patch | `c1a15efdb80d42bbda59382a16f242211f229f4f5be7381a60bd0c4b2a897f68` |
| glibc-fhs-1.patch | `643552db030e2f2d7ffde4f558e0f5f83d3fabf34a2e0e56ebdb49750ac27b0d` |

Tarballs GNU foram autenticados com `gpgv`, assinaturas detached oficiais e
`https://ftp.gnu.org/gnu/gnu-keyring.gpg`:

- Binutils: `3A24BC1E8FB409FA9F14371813FCEF89DD9E3C4F` (Nick Clifton).
- GCC: `7F74F97C103468EE5D750B583AB00996FC26A641` (Richard Guenther).
- glibc: `FD19E6D31B192EE4DC63EAD3DC2B16215ED5412A` (Andreas K. Hüttel).
- Coreutils: `6C37DC12121A5006BC1DB804DF6FD971306037D9` (Pádraig Brady).

Util-linux foi comparado a
`https://cdn.kernel.org/pub/linux/utils/util-linux/v2.42/sha256sums.asc`.
GMP/MPFR/MPC foram comparados ao SHA-512 oficial em
`https://sourceware.org/pub/gcc/infrastructure/sha512.sum` e então fixados por
SHA-256. Patches LFS foram comparados aos MD5 publicados pelo LFS via HTTPS
e então fixados por SHA-256. Builds subsequentes verificam todos os downloads
contra os SHA-256 fixados antes da extração.

## Auditoria e provas

`./corelabs.sh auditar-elf` usa readelf, sem executar `ldd` do host. Verifica
ELF64/x86_64, PT_INTERP exato, DT_NEEDED sem paths e resolvido somente no rootfs,
ausência de RPATH/RUNPATH externo e fingerprints do runtime. Somente os módulos
oficiais em `/usr/lib/gconv` podem usar o valor exato `$ORIGIN`, como previsto
na receita upstream da glibc, com dependências resolvidas no mesmo diretório
interno; não permite listas, `$ORIGIN/..` ou essa exceção em outros ELF.
Essa exceção exige módulo `.so` sem PT_INTERP e listado no manifest verificado.
Links resolvidos para fora do rootfs são rejeitados.

`scripts/testar-base-abi.sh` compila `testes/base-abi/hello-corelabs.c` e
`hello-corelabs-cpp.cc`, salva readelf e traces do linker em
`compilacao/testes-base-abi/`. As provas exercitam glibc 2.44, libm via dlopen,
sigaction/raise, pthread, libstdc++, threads C++ e exceções/unwind. Os executáveis de prova não
entram no rootfs de produção. Devem ser executados dentro da VM Corelabs.

`scripts/testar-auditoria-abi.sh` cria fixtures descartáveis e exige rejeição de
RUNPATH Ubuntu, ORIGIN fora de gconv, RPATH de build, loader estrangeiro, biblioteca ausente,
link para biblioteca externa e runtime adulterado.

Esta base não declara aprovação das suítes completas de GCC/glibc/Binutils nem
reprodutibilidade bit a bit entre hosts. Ela fixa sources/receitas e controla os
inputs da ABI. Pacotes CPM futuros x86_64 devem usar esta toolchain/sysroot e
passar pela auditoria; nenhuma função do CPM é adicionada nesta tarefa.
