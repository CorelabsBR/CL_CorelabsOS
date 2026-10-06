# Entrega e validação CPM v0.2

## Hardening da fundação em 05/10/2026

A cadeia de confiança deixou o bootstrap Optional: o repositório oficial agora
usa `SigLevel=Required`. Índices e pacotes são autenticados antes de serem
interpretados/instalados por assinatura destacada RSA-PSS/SHA-256 via OpenSSL
3.5.4. A chave pública é específica por repositório em
`/etc/cpm/keyrings/<repo>.pem`; arquivo ausente, symlink, owner não-root, modo
gravável por grupo/outros, assinatura ausente/inválida, chave errada e falha de
rede abortam. Optional continua disponível somente como decisão explícita do
administrador e não ignora assinatura presente inválida.

Não foi criada chave privada oficial. Os testes geram uma chave RSA 3072 efêmera
na área descartável de `compilacao/`; ela não entra no Git, rootfs ou archive.
A geração/custódia da chave privada oficial, o provisionamento de sua chave
pública e a assinatura/publicação do archive são etapas externas bloqueadas por
credenciais e infraestrutura indisponíveis. Consequentemente o archive oficial
Required deve falhar fechado até esse provisionamento.

O rootfs passou a incluir somente a CLI estática `openssl` necessária à
verificação. `scripts/auditar-seguranca.sh` formaliza o gate de SUID/SGID,
capabilities, world-writable, `/tmp`, contas, shadow, sudoers, CPM e modos
críticos. A construção normaliza shadow 0600, sudoers 0440, passwd/group e repo
CPM 0644. As únicas entradas SUID aceitas são `/bin/su` e `/usr/bin/sudo`.

O ambiente comum fixa `LC_ALL=C`, `TZ=UTC`, umask 022 e
`SOURCE_DATE_EPOCH` (0 por padrão). Os principais tar/cpio/gzip passaram a usar
ordenação, owners numéricos, timestamps fixos, cpio reproducible e gzip sem
timestamp. Duas gerações consecutivas do initramfs produziram exatamente
`7ed091cf0bd0c0f13444e008b21c6ee84fb0e87acdaeb68e6eb2534ac35d4f55`.
Isto prova esse artefato nesse checkout/host, não reprodução bit a bit universal.

Resultados executados nesta rodada:

- `scripts/testar-cpm.sh`: 76 verificações aprovadas, incluindo assinatura
  válida, ausente, adulterada, chave errada e pacote/índice adulterados;
- `scripts/rootfs.sh`: 400 ELF x86_64, 109 executáveis dinâmicos, dependências
  internas e auditoria de segurança aprovada;
- `scripts/testar-auditoria-abi.sh`: sete fixtures host/loader/RPATH/runtime
  rejeitadas;
- `scripts/testar-base-abi.sh`: provas C/C++ compiladas somente com inputs target;
- `scripts/testar-seguranca.sh`: sudoers permissivo, SUID inesperado e diretório
  world-writable rejeitados;
- duas gerações de `scripts/initramfs.sh`: hashes idênticos acima;
- `scripts/preparar-instalador.sh`: rootfs, initramfs de transição/emergência,
  GRUB EFI e instalador reconstruídos sem tocar em disco;
- `scripts/verificar.sh`: fontes/archives validados e boot QEMU real até banner e
  getty/login, permanecendo ativo para autenticação.

Não foram executados nesta rodada: instalação/boot UEFI em nova QCOW2, login,
rede real, reboot/persistência, Emergency Shell e pacote Fastfetch oficial. Eles
permanecem BLOCKED para a validação final desta mudança até existir chave pública
oficial/archive assinado; as evidências anteriores sem assinatura não substituem
esse teste end-to-end.

Validação em 01/10/2026, exclusivamente em `/arsenal/projetos/Lithos/Lithos`.
Não houve commit, push, escrita no archive ou remoção de QCOW2 existente.

## 1. Auditoria inicial

Antes de editar foram lidos integralmente `documentacao/base-abi-v1.md`,
`documentacao/validacao-base-abi-v1.md`, `sistema/usr/bin/cpm`,
`sistema/etc/cpm/repos.d/Lithos.repo`, `scripts/rootfs.sh` e
`scripts/biblioteca.sh`; executado `git status --short`. O worktree já continha
alterações extensas da Base ABI e outras alterações locais. Foram preservadas.
CPM antiga era v0.1, usava repos.conf e rejeitava índice vazio. Cópia anterior
preservada em `compilacao/cpm/cpm-v0.1-antes-da-implementacao`.

## 2. Arquivos desta implementação

Alterados nesta missão: `.gitignore` (exceções limitadas para o código C próprio),
`scripts/rootfs.sh` (compilação/instalação do helper, modo executável CPM, keyring,
normalização de diretórios), `sistema/usr/bin/cpm` (v0.2) e
`sistema/etc/cpm/repos.d/Lithos.repo` (bootstrap Optional).

Criados: `fontes/cpm/arquivo.c`, `scripts/compilar-cpm.sh`,
`scripts/testar-cpm.sh`, `testes/cpm/testar.py`, doubles
`testes/cpm/mock-{curl.py,id.sh,stat.sh,mv.sh}`, `testes/cpm/preparar-vm.py`,
`testes/cpm/verificar-vm.sh`, `documentacao/cpm.md` e este relatório.
Não foram alterados init, DHCP, configuração/receitas da ABI ou manifesto ABI
nesta missão; seus diffs já existiam. A normalização de diretórios foi necessária:
a primeira VM comprovou que o checkout com umask 0002 gerava `/`, `/usr`, `/var`
em 775; a CPM corretamente recusou esses ancestrais. O pipeline agora remove
escrita de grupo/outros em diretórios, preserva modos restritivos e restaura /tmp
1777. Nenhum runtime do Ubuntu foi copiado.

## 3. CLI

Implementados update/search/info/list/install/remove/--version/--help.
Mutação exige root; consultas funcionam sem root e sem rede sobre índices locais.
Nome exato, busca case-insensitive, versão instalada e erros previsíveis.

## 4. Parser de repos

INI em repos.d, espaços em torno de `=`, comentários, seções múltiplas, Enabled,
Server, SigLevel. Expansão literal $arch, sem eval. Duplicatas, URL insegura e
campos desconhecidos rejeitados; desabilitados ignorados. uname x86_64 validado.
Update aceita índice vazio, valida sete campos/arquitetura/caminho/hash/NUL e
mantém índices anteriores em falhas, inclusive rollback de publicação múltipla.

## 5. SigLevel

Optional temporário: 404 em `.sig` permite objeto não assinado com aviso;
assinatura presente e outros erros falham. Required falha fechado, sem verificador
e chave operacional. `/etc/cpm/keyrings/` existe; nenhuma chave privada, TOFU,
confiança automática ou alegação de assinatura verificada. Procedimento e
pré-requisitos para Required em `cpm.md`.

## 6. Banco local

repos/<repo>/index, db/installed/<pacote>/{desc,files}, db/ownership em
/var/lib/cpm. Downloads/staging somente em /var/cache/cpm/packages. Desc inclui
hash do pacote e da lista; files registra tipo/caminho/dispositivo/inode.
List independe de configuração e rede.

## 7. Locking

flock real, existência confirmada, fd 9, aquisição não bloqueante. Arquivo de lock
persistente; liberação do kernel na saída/sinais, sem corrida por unlink. Teste
concorrente recusou a segunda mutação enquanto a primeira baixava o índice.

## 8. Instalação/transação

Download HTTPS, SHA, descompressão limitada, inspeção integral, MANIFEST, lista e
preflight precedem commit. Staging e journal com fsync, snapshot de ownership,
publicação sem sobrescrita, banco somente depois do payload. Testes simularam
falha de publicação e SIGKILL; nova mutação recuperou a transação pendente.

## 9. Ownership

Colisão com arquivo unmanaged ou de outro pacote é recusada. Diretórios existentes
compartilhados não mudam modo/owner. Caminhos de runtime ABI/arquivos essenciais
são protegidos, mesmo contra banco forjado. Ancestrais symlink ou graváveis por
grupo/outros são recusados; openat/O_NOFOLLOW na travessia.

## 10. Remoção segura

Valida integralmente hash/files/ownership/tipos/inodes, protege as raízes pedidas,
usa backups locais e rollback antes do commit; remove diretórios apenas próprios
e vazios. Registro malicioso `/`, com hash recalculado, foi rejeitado sem remoção.
Falha de publicação e interrupção de remove restauraram payload e banco.

## 11. Archive

Helper C inspeciona tar ustar inteiro antes de extrair para staging. Rejeita
traversal, absoluto, links inseguros, hardlinks, devices/FIFO/socket, membros fora
do schema, duplicatas, extensões e modos privilegiados/graváveis; valida checksum,
truncamento e manifesto. Não executa scripts/hooks. Symlink relativo seguro foi
instalado e removido nos testes. A fixture VM inicialmente herdou modo 775 do
binário de build e foi corretamente recusada; o gerador agora fixa modo 755.

## 12. Testes negativos e qualidade

`./scripts/testar-cpm.sh`: **74 verificações aprovadas**, helper compilado com
`-Wall -Wextra -Werror`. Evidência `compilacao/logs/cpm-unitarios.log`, área
preservada `compilacao/cpm-testes.hyd73i0p`.

Cobertos: índice vazio/válido, campos incorretos, arquitetura, release, basename,
NUL; pacote inexistente; SHA incorreto; archive truncado; manifesto ausente ou
divergente; ../; absoluto; symlink/hardlink malicioso; FIFO/device; hook fora do
schema; ancestral symlink; membro duplicado; unmanaged; ownership de outro pacote;
remove `/`; Required; assinatura presente; configuração injetável/desabilitada;
operações não-root; concorrência; rollback e recuperação install/remove;
falha na publicação do segundo índice restaura ambos. Snapshots comprovam ausência
de alteração de banco/payload nos casos negativos.

Executados com sucesso: `sh -n` no CPM e testes shell; `bash -n` nos três scripts
Bash alterados/criados; `git diff --check`; `scripts/testar-auditoria-abi.sh`
(rejeição de loaders/RPATH/dependências/runtime adulterados);
`scripts/testar-base-abi.sh` (inputs de C/C++ exclusivos do target).

## 13. Archive real

Endpoint oficial consultado somente para leitura. Index HTTP 200, **zero bytes**;
index.sig HTTP 404. Na VM instalada, `sudo cpm update` terminou com sucesso e
aviso Optional; `cpm search fastfetch`, `cpm search teste` e `cpm list` retornaram
sucesso sem ocorrências. `wc -c /var/lib/cpm/repos/Lithos/index` confirmou zero.
Não foram publicados pacotes nem chaves no servidor.

## 14. VM e pipeline

Reconstruído por `scripts/preparar-instalador.sh`, incluindo rootfs, helper,
auditoria ELF, initramfs, GRUB EFI e instalador oficiais.
Host deps previamente disponíveis em compilacao/abi-host-deps via PATH/PERL5LIB,
sem instalar dependências globais. Log: `compilacao/logs/cpm-instalador.log`.

VM final QEMU/KVM, OVMF, 2 vCPU, 2 GiB, QCOW2 novo 40 GiB:
`maquinas/testes/cpm-v0.2-final.O7Yqak/`. Instalação real terminou
`Lithos_INSTALACAO_OK`. CLI instalada tem SHA-256
`797000576665ace73cd290eca2e49ce68fd61a0d92c826e4e01adc2e06e2f3e9`,
idêntico ao código fonte shell final.

Evidências nesse diretório:

- `instalacao.serial.log`: instalação e UUID canônico;
- `boot-rede.serial.log`: CLI, archive, instalação/execução/remoção fixture,
  testes Base ABI, su/sudo, reboot;
- `reboot-offline.serial.log`: novo boot/login sem NIC, consultas offline, poweroff;
- `emergency.serial.log`: seleção GRUB, ambiente independente e poweroff.

`testes/cpm/verificar-vm.sh` terminou `CPM_VM_INSTALACAO_REMOCAO_OK`: pacote
C++ instalado numa raiz descartável isolada, listado, consultado, executado com
libstdc++/libgcc/glibc Lithos e removido, deixando ownership vazio e sem registro.
Esse transporte é um double local explícito, não teste HTTPS real. HTTPS real foi
testado separadamente contra o archive oficial. Python apenas no host.
As áreas de instalação intermediárias também foram preservadas, assim como todos
os discos anteriores à missão. Senha temporária não consta deste relatório.

## 15. Regressões

Boot UEFI/GRUB e login girelli; su root e sudo uid0; DHCP 10.0.2.15, gateway e DNS;
HTTP/HTTPS 200; certificado expirado recusado com curl 60; glibc 2.44,
Coreutils/util-linux; SUID exclusivo su/sudo e BusyBox sem SUID; manifesto ABI
integral; C NSS/DNS/signal/pthread/dlopen/libm; C++ exception/unwind/thread.
`Lithos_BASE_ABI_V1_SISTEMA_OK` no guest.

Reboot e shutdown limpos, **Falhas: 0**; novo boot sem NIC com
`CPM_OFFLINE_OK`. Emergency Shell root, sem montar raiz instalada e sem loader
glibc do sistema, terminou `CPM_EMERGENCY_INDEPENDENTE_OK`.
UUID confirmado em instalação, sistema e Emergency:
`434f5245-4c41-4253-9f01-000000000001`.
Auditoria final: 399 ELF x86_64, 109 executáveis dinâmicos, dependências internas;
14 módulos gconv com ORIGIN local permitido. Acréscimo CPM: um helper dinâmico.

## 16. Limitações

Sem verificador de assinatura operacional (Required deliberadamente fechado),
solver, upgrades ou hooks. Ustar conservador, ASCII sem espaços, sem PAX/GNU,
hardlinks, SUID ou ACL/xattr. Depends/Conflicts/Replaces não vazios recusados.
Rollback razoável não promete atomicidade universal sob queda de energia; update
não fornece snapshot para leitores concorrentes nem recuperação de SIGKILL.
Inode substituído durante recuperação bloqueia mutações e preserva evidência.
Archive oficial vazio impede teste de pacote oficial real; fixture dinâmica
supre instalação/remoção, sem afirmar autenticidade criptográfica.

## 17. Git status --short

Estado após implementação (inclui alterações pré-existentes; não confundir com
arquivos alterados nesta missão, enumerados no item 2):

```text
 M .gitignore
 M configuracao/compilacao.conf
 M configuracao/fontes-lfs.csv
 M configuracao/vm.conf
 M Lithos.sh
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
 M sistema/usr/lib/Lithos/rede/dhcp
?? .vscode/
?? documentacao/base-abi-v1.md
?? documentacao/cpm.md
?? documentacao/validacao-base-abi-v1.md
?? documentacao/validacao-cpm-v0.2.md
?? fontes/cpm/
?? scripts/auditar-elf.sh
?? scripts/compilar-base-abi.sh
?? scripts/compilar-cpm.sh
?? scripts/compilar-curl.sh
?? scripts/compilar-openssl.sh
?? scripts/compilar-sudo.sh
?? scripts/compilar-toolchain.sh
?? scripts/preparar-emergencia.sh
?? scripts/testar-auditoria-abi.sh
?? scripts/testar-base-abi.sh
?? scripts/testar-cpm.sh
?? sistema-emergencia/
?? sistema/etc/cpm/
?? sistema/etc/ld.so.conf
?? sistema/etc/nsswitch.conf
?? sistema/etc/sudoers
?? sistema/root/
?? sistema/usr/bin/cpm
?? testes/base-abi/
?? testes/cpm/
```
