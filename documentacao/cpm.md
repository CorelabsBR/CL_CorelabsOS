# Lithos Package Manager 0.2

A CPM usa a Lithos Base ABI v1, x86_64. O frontend é POSIX sh e o auxiliar
`/usr/libexec/cpm/arquivo` é C, compilado pela toolchain Lithos, ligado à glibc
do próprio sistema. Não instala runtime do host nem requer Python no alvo.

## Comandos

`cpm --help`, `cpm --version`, `cpm update`, `cpm search <termo>`,
`cpm info <nome>`, `cpm list`, `cpm install <nome>` e `cpm remove <nome>`.
Update/install/remove exigem root. Search pesquisa nome e descrição sem distinguir
maiúsculas; info identifica candidato exato e informa a versão instalada
separadamente. List lê somente o banco instalado e funciona offline. Índice vazio
é válido; busca/lista vazias não são erros. Nome inexistente ou ambíguo falha.

## Configuração e autenticidade

São lidos `/etc/cpm/repos.d/*.repo`, com seções INI e chaves Server, Enabled e
SigLevel. Há suporte a espaços ao redor de `=`, comentários e múltiplas seções.
Não há execução de configuração/eval. Enabled=yes/no, identificadores duplicados
e chaves desconhecidas são validados. Repositório desabilitado é ignorado.
Somente a variável literal `$arch` é expandida, usando `uname -m` (x86_64).
Servidores devem ser HTTPS, sem credenciais, query ou construções de shell.

```ini
[Lithos]
Server = https://archive.corelabs.dev.br/cpm/v1/$arch
Enabled = yes
SigLevel = Required
```

Cada repositório usa a chave pública PEM
`/etc/cpm/keyrings/<identificador>.pem`. Ela deve ser arquivo regular de root,
com modo no máximo 0644. A chave não é baixada pelo próprio repositório, não há
TOFU e uma chave ausente, incorreta ou insegura aborta a operação.

`<objeto>.sig` é uma assinatura destacada RSA-PSS/SHA-256 dos bytes exatos do
objeto, com salt de 32 bytes. O CPM baixa o objeto e a assinatura para staging,
verifica com OpenSSL 3.5.4 e somente então interpreta o índice ou confere o
SHA-256 do pacote. Assinatura ausente ou inválida sob Required aborta sem publicar
estado. Optional só aceita ausência quando o servidor responde 404 e emite aviso;
assinatura presente sempre precisa ser válida. Falha de rede/status diferente de
200/404 nunca vira downgrade. Nunca se usa `curl -k`.

### Operação externa de release

A chave privada deve ser criada e guardada em infraestrutura de release separada;
ela não pode entrar no Git, imagem, archive público, cliente, pacote ou logs. Exemplo
de assinatura (os paths da chave são deliberadamente externos ao projeto):

```sh
openssl pkeyutl -sign -inkey /cofre/release-private.pem -rawin -digest sha256 \
  -pkeyopt rsa_padding_mode:pss -pkeyopt rsa_pss_saltlen:digest \
  -in index -out index.sig
```

O mesmo procedimento assina cada `.cpm`. Publique o objeto e seu `.sig`; provisione
previamente apenas a chave pública correspondente como `Lithos.pem` por canal
confiável da imagem/release. A chave oficial ainda não está disponível neste
repositório: por isso o cliente oficial Required falha fechado até a etapa externa.

## Índice, banco e cache

Endpoint: `https://archive.corelabs.dev.br/cpm/v1/x86_64/index`.
Cada linha não vazia contém exatamente sete campos:

```text
nome|versao|release|arquitetura|arquivo.cpm|sha256|descricao
```

Nome/versão, release inteiro positivo, arquitetura x86_64, basename seguro,
SHA-256 hexadecimal minúsculo e descrição sem controles são verificados. Não há
caminhos de download arbitrários. Índices limitados a 8 MiB; NUL é recusado.
Todos os downloads/validações precedem publicação. Cada índice é publicado por
rename atômico, sem truncar o anterior. Uma falha de download/validação preserva
todos os índices. Snapshots restauram os anteriores em falha de publicação ou sinal
tratável, inclusive para múltiplos repositórios. Não há snapshot consistente para
leitores concorrentes nem recuperação de update interrompido por SIGKILL/queda de energia.

Estado:

- `/var/lib/cpm/repos/<repo>/index`: índices locais;
- `/var/lib/cpm/db/installed/<nome>/desc`: metadados e hashes;
- `/var/lib/cpm/db/installed/<nome>/files`: tipo, caminho, dispositivo e inode;
- `/var/lib/cpm/db/ownership`: `/caminho/absoluto|pacote`;
- `/var/lib/cpm/transactions/`: journals e snapshots privados;
- `/var/cache/cpm/packages/`: downloads SHA-qualified e staging temporário.

Arquivos novos não substituem arquivos unmanaged nem de outros pacotes.
Diretórios existentes podem ser compartilhados, sem mudança de modo ou ownership.
Somente diretórios novos efetivamente criados são atribuídos ao pacote.

## Pacotes

Tar ustar comprimido com gzip, xz ou bzip2, contendo `CPM/MANIFEST` regular e
`payload/...`. Exemplo mínimo:

```text
Name=exemplo
Version=1.0
Release=1
Architecture=x86_64
Description=Exemplo
Depends=
Provides=
Conflicts=
Replaces=
```

Os quatro campos obrigatórios devem corresponder ao índice, não ao nome do arquivo.
Metadados desconhecidos/duplicados são recusados. Depends/Conflicts/Replaces não
vazios são rejeitados: não há solver. Provides é metadado, não resolução.

```sh
tar --format=ustar -czf exemplo.cpm -C staging CPM/MANIFEST payload
sha256sum exemplo.cpm
```

O auxiliar inspeciona o tar completo antes da extração em staging. Rejeita caminho
absoluto, componentes `.`/`..`, controles, nomes não ASCII/espaços, membros fora
do schema, duplicatas, manifesto ausente, truncamento/checksum incorreto, dados
extras após terminador, devices/FIFO/socket, todos os hardlinks, extensões GNU/PAX,
SUID/SGID/sticky e arquivos/diretórios graváveis por grupo/outros. Symlinks relativos
seguros são permitidos (modo usual 0777); não podem escapar lexicalmente da raiz
nem ser ancestrais de outro membro. Limites: 10 mil membros, caminhos 1024 bytes,
manifesto 64 KiB, tar descomprimido 512 MiB, além de limite de descompressão do shell.
Não há hooks, scripts, ACLs/xattrs ou restauração de proprietários do archive.

## Transações e proteção

O lock usa `flock -n` em fd 9 após verificar a existência do comando. O inode do
arquivo de lock permanece; o lock do kernel é liberado na saída, inclusive sinais
tratáveis. Isso evita a corrida de apagar/recriar lockfiles. Operações concorrentes
falham imediatamente. Transações pendentes são recuperadas sob o mesmo lock.

SHA-256, manifesto, todos os destinos, ownership e colisões são verificados antes
de escrever payload. O auxiliar percorre ancestrais com openat/O_NOFOLLOW e exige
diretórios confiáveis, não graváveis por grupo/outros. Arquivos são preparados no
diretório destino e publicados por rename sem substituição. Journal registra
dispositivo/inode; arquivos instalados precedem a publicação do registro no banco.
Snapshots de ownership e marcador de commit permitem rollback e recuperação.

Remove verifica integralmente o banco, hash da lista, ownership, tipos e inodes
antes de agir. Arquivos são renomeados para backups no próprio diretório; o commit
retira ownership/registro e então elimina backups. Diretórios próprios somente
são removidos vazios. Registros maliciosos não podem atingir `/`, `/bin`, `/sbin`,
`/lib`, `/lib64`, `/usr`, `/usr/bin`, `/usr/sbin`, `/usr/lib`, `/etc`, `/var`,
`/home`, `/root`, `/boot`, `/dev`, `/proc`, `/sys` ou `/run`.
Áreas de estado CPM/boot/kernel/users e arquivos essenciais/runtime listados no
manifesto Base ABI também são protegidos. Falha de rollback por inode alterado
preserva o journal e bloqueia novas mutações, em vez de remover arquivo estranho.

Há fsync de journals/diretórios e sync do estado. Isto é rollback razoável, não
garantia de atomicidade completa contra perda de energia: uma interrupção no
intervalo entre criação de diretório/temporário e journal pode deixar um diretório
vazio/arquivo oculto. Não há upgrades, dependências automáticas, hooks ou reparo
automático de corrupção. CPM_ROOT/CPM_ARCHIVER destinam-se a raízes isoladas/testes;
não dispensam checagens de proprietário, root, ancestral ou archive.

## Dependências auditadas e testes

No alvo: sh, awk, grep, sed, stat, realpath, mkdir, mv, cp, rm, rmdir, mktemp,
cat, chmod, tr, uname, id, od, cmp, wc, gzip, xz, bzip2, sha256sum, sync e flock,
todos do userspace existente (Coreutils/util-linux/BusyBox), mais curl e openssl da própria
Base ABI. Não requer tar externo para extrair pacotes. O pipeline compila e audita
o helper ELF; a normalização de diretórios no rootfs evita herdar umask do checkout.

`scripts/testar-cpm.sh` executa fixtures negativas descartáveis com Python **somente
no host** e helper nativo separado, nunca instalado. `testes/cpm/preparar-vm.py`
gera fixture ABI para `testes/cpm/verificar-vm.sh`, que roda no sistema alvo sem
Python. Esse teste usa transporte local explicitamente simulado; o teste do
archive oficial usa curl HTTPS real, separadamente. Evidências e entrega em
[validacao-cpm-v0.2.md](validacao-cpm-v0.2.md).
