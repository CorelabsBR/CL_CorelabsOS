#define _GNU_SOURCE

#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

#define CAMINHO_SOCKET "/run/Lithos/control.sock"
#define TAMANHO_RESPOSTA 32

static int operacao_valida(const char *operacao)
{
    return strcmp(operacao, "poweroff") == 0 ||
           strcmp(operacao, "reboot") == 0 ||
           strcmp(operacao, "halt") == 0;
}

static int conectar(void)
{
    int fd = socket(
        AF_UNIX,
        SOCK_SEQPACKET | SOCK_CLOEXEC,
        0);

    if (fd == -1) {
        perror("clcontrol: socket");
        return -1;
    }

    struct sockaddr_un endereco = {0};
    endereco.sun_family = AF_UNIX;

    if (strlen(CAMINHO_SOCKET) >= sizeof(endereco.sun_path)) {
        fprintf(stderr,
                "clcontrol: caminho do socket muito longo\n");
        close(fd);
        return -1;
    }

    strcpy(endereco.sun_path, CAMINHO_SOCKET);

    if (connect(
            fd,
            (struct sockaddr *)&endereco,
            sizeof(endereco)) == -1) {
        perror("clcontrol: connect");
        close(fd);
        return -1;
    }

    return fd;
}

int main(int argc, char **argv)
{
    if (argc != 2 || !operacao_valida(argv[1])) {
        fprintf(stderr,
                "Uso: clcontrol {poweroff|reboot|halt}\n");
        return 2;
    }

    int fd = conectar();

    if (fd == -1)
        return 1;

    size_t tamanho = strlen(argv[1]);

    if (send(
            fd,
            argv[1],
            tamanho,
            MSG_NOSIGNAL) != (ssize_t)tamanho) {
        perror("clcontrol: send");
        close(fd);
        return 1;
    }

    char resposta[TAMANHO_RESPOSTA] = {0};

    ssize_t recebido = recv(
        fd,
        resposta,
        sizeof(resposta) - 1,
        MSG_TRUNC);

    close(fd);

    if (recebido <= 0) {
        if (recebido < 0)
            perror("clcontrol: recv");
        else
            fprintf(stderr,
                    "clcontrol: conexão encerrada sem resposta\n");

        return 1;
    }

    if ((size_t)recebido >= sizeof(resposta)) {
        fprintf(stderr,
                "clcontrol: resposta inválida do daemon\n");
        return 1;
    }

    resposta[recebido] = '\0';

    if (strcmp(resposta, "OK") == 0)
        return 0;

    if (strcmp(resposta, "EPERM") == 0) {
        fprintf(stderr,
                "clcontrol: operação não autorizada\n");
        return 3;
    }

    if (strcmp(resposta, "EBUSY") == 0) {
        fprintf(stderr,
                "clcontrol: encerramento já está em andamento\n");
        return 1;
    }

    if (strcmp(resposta, "EINVAL") == 0) {
        fprintf(stderr,
                "clcontrol: operação rejeitada pelo daemon\n");
        return 2;
    }

    if (strcmp(resposta, "EMSGSIZE") == 0) {
        fprintf(stderr,
                "clcontrol: pedido rejeitado pelo daemon\n");
        return 2;
    }

    if (strcmp(resposta, "EIO") == 0) {
        fprintf(stderr,
                "clcontrol: falha interna no controle administrativo\n");
        return 1;
    }

    fprintf(stderr,
            "clcontrol: resposta desconhecida do daemon: %s\n",
            resposta);

    return 1;
}
