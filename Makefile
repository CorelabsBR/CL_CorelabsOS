.PHONY: all dependencias compilar kernel rootfs initramfs imagem instalar iniciar testar-persistencia verificar limpar ajuda

all: compilar
dependencias:
	./corelabs.sh dependencias
compilar:
	./corelabs.sh compilar
kernel:
	./corelabs.sh kernel
rootfs:
	./corelabs.sh rootfs
initramfs:
	./scripts/initramfs.sh
imagem:
	./corelabs.sh imagem
instalar:
	./corelabs.sh instalar
iniciar:
	./corelabs.sh iniciar
testar-persistencia:
	./corelabs.sh testar-persistencia
verificar:
	./corelabs.sh verificar
limpar:
	./corelabs.sh limpar
ajuda:
	./corelabs.sh ajuda
