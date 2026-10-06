# Toolchain GNU do Lithos

## Estado real

O pipeline atual implementa a [Lithos Base ABI v1](base-abi-v1.md): toolchain cruzada GNU própria, sysroot e runtime glibc/GCC, Coreutils e um subset do util-linux dinâmicos. BusyBox 1.36.1, Bash e os componentes administrativos existentes continuam estáticos. O PID 1, supervisor e consoles próprios são preservados. As ferramentas do instalador continuam estáticas, com util-linux alinhado à versão 2.42.2.

A toolchain executa no host, mas produz binários para o sysroot Lithos. O manifesto descreve o bootstrap, hashes, layout, auditoria de ELF e os limites da validação. A instalação de uma toolchain nativa dentro do Lithos e a execução integral das suítes GNU não estão implícitas nesta base.

## Referência histórica de expansão

A referência de versões é o Linux From Scratch 13.1. As versões estão registradas em `configuracao/fontes-lfs.csv`. O planejamento anterior de uma distribuição completa com systemd abaixo é histórico e não faz parte da implementação da Base ABI v1.

A implementação deverá seguir estas barreiras verificáveis:

1. Baixar cada arquivo das origens oficiais e registrar SHA-256 antes da extração.
2. Construir Binutils e GCC do primeiro passe com alvo `x86_64-Lithos-linux-gnu` em um prefixo isolado.
3. Instalar cabeçalhos do kernel e construir glibc contra esses cabeçalhos.
4. Construir libstdc++ e as ferramentas temporárias sem buscar bibliotecas do host em tempo de execução.
5. Entrar em um ambiente isolado com `/dev`, `/proc`, `/sys` e `/run` próprios para construir o sistema final.
6. Executar as suítes de teste de Binutils, GCC e glibc e registrar os resultados.
7. Construir Bash, Coreutils, util-linux e bibliotecas fundamentais no novo sysroot.
8. Construir e testar systemd, D-Bus, kmod, libcap, util-linux e demais dependências antes de trocar o PID 1.

Os arquivos em `sistema-systemd/` preparam console serial, rede DHCP e identidade do host. Eles permanecem fora do rootfs ativo enquanto o binário e suas dependências não forem compilados e testados.

## Recursos

O LFS recomenda ao menos quatro núcleos e 8 GB de memória para uma construção confortável. O repositório mantém o limite de paralelismo configurável; o bootstrap também limita trabalhos pela memória disponível. A Base ABI é compilada de fontes reais, mas não declara aprovação das suítes GNU completas nem ativa os componentes da expansão histórica.
