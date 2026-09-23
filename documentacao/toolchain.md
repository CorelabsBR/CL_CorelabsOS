# Estratégia da toolchain GNU e adoção do systemd

## Estado real

O sistema persistente validado nesta etapa ainda usa o BusyBox 1.36.1 estático como espaço de usuário e o PID 1 experimental da Fase 0. Ele não copia bibliotecas ou executáveis da distribuição hospedeira. O e2fsprogs 1.47.2 e o util-linux 2.41.1 são compilados de fontes oficiais como executáveis estáticos usados somente pelo instalador.

A toolchain GNU completa e o systemd não foram ativados. Construí-los de forma auditável exige os passes de compilação cruzada, ferramentas temporárias, chroot e suítes de teste descritos pelo Linux From Scratch. Substituir o PID 1 antes desse processo contrariaria a exigência de manter a implementação comprovadamente inicializável.

## Referência reprodutível

A referência adotada é o Linux From Scratch 13.1-systemd. As versões centrais estão registradas em `configuracao/fontes-lfs.csv`: Binutils 2.47, GCC 16.2.0, glibc 2.44, Bash 5.3, Coreutils 9.11, util-linux 2.42.2 e systemd 261.3.

A implementação deverá seguir estas barreiras verificáveis:

1. Baixar cada arquivo das origens oficiais e registrar SHA-256 antes da extração.
2. Construir Binutils e GCC do primeiro passe com alvo `x86_64-corelabs-linux-gnu` em um prefixo isolado.
3. Instalar cabeçalhos do kernel e construir glibc contra esses cabeçalhos.
4. Construir libstdc++ e as ferramentas temporárias sem buscar bibliotecas do host em tempo de execução.
5. Entrar em um ambiente isolado com `/dev`, `/proc`, `/sys` e `/run` próprios para construir o sistema final.
6. Executar as suítes de teste de Binutils, GCC e glibc e registrar os resultados.
7. Construir Bash, Coreutils, util-linux e bibliotecas fundamentais no novo sysroot.
8. Construir e testar systemd, D-Bus, kmod, libcap, util-linux e demais dependências antes de trocar o PID 1.

Os arquivos em `sistema-systemd/` preparam console serial, rede DHCP e identidade do host. Eles permanecem fora do rootfs ativo enquanto o binário e suas dependências não forem compilados e testados.

## Recursos

O LFS recomenda ao menos quatro núcleos e 8 GB de memória para uma construção confortável. O repositório mantém o limite de paralelismo configurável, mas uma toolchain completa requer várias horas, dezenas de gigabytes temporários e revisão dos resultados das suítes. Esta etapa não simula essa construção nem marca os pacotes planejados como instalados.

