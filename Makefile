.PHONY: all dependencias compilar kernel rootfs initramfs imagem instalar atualizar-identidade iniciar testar-persistencia verificar limpar ajuda

all: compilar
dependencias:
	./Lithos.sh dependencias
compilar:
	./Lithos.sh compilar
kernel:
	./Lithos.sh kernel
rootfs:
	./Lithos.sh rootfs
initramfs:
	./scripts/initramfs.sh
imagem:
	./Lithos.sh imagem
instalar:
	./Lithos.sh instalar
atualizar-identidade:
	./Lithos.sh atualizar-identidade
iniciar:
	./Lithos.sh iniciar
testar-persistencia:
	./Lithos.sh testar-persistencia
verificar:
	./Lithos.sh verificar
limpar:
	./Lithos.sh limpar
ajuda:
	./Lithos.sh ajuda
