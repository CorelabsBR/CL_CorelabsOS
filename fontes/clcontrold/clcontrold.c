#define _GNU_SOURCE

#include <errno.h>
#include <signal.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/un.h>
#include <unistd.h>

#define CAMINHO_SOCKET "/run/Lithos/control.sock"
#define CAMINHO_PEDIDO "/run/Lithos/operacao"
#define CAMINHO_LOCK   "/run/Lithos/encerrando"

#define GID_ADMIN_PADRAO ((gid_t)10)
#define TAMANHO_PEDIDO 32

static volatile sig_atomic_t encerrando = 0;
static int socket_servidor = -1;

static void receber_sinal(int sinal)
{
    (void)sinal;
    encerrando = 1;

    if (socket_servidor >= 0)
        close(socket_servidor);
}

static bool operacao_valida(const char *operacao)
{
    return strcmp(operacao, "poweroff") == 0 ||
           strcmp(operacao, "reboot") == 0 ||
           strcmp(operacao, "halt") == 0;
}

static bool grupo_presente(
    const gid_t *grupos,
    size_t quantidade,
    gid_t procurado)
{
    for (size_t i = 0; i < quantidade; i++) {
        if (grupos[i] == procurado)
            return true;
    }

    return false;
}

static bool autorizado(int fd, struct ucred *credencial)
{
    socklen_t tamanho = sizeof(*credencial);

    if (getsockopt(
            fd,
            SOL_SOCKET,
            SO_PEERCRED,
            credencial,
            &tamanho) == -1) {
        perror("getsockopt SO_PEERCRED");
        return false;
    }

    if (tamanho != sizeof(*credencial)) {
        fprintf(stderr,
                "[CONTROLE] Credencial de peer inválida.\n");
        return false;
    }

    if (credencial->uid == 0)
        return true;

    gid_t grupos[64];
    socklen_t bytes = sizeof(grupos);

    if (getsockopt(
            fd,
            SOL_SOCKET,
            SO_PEERGROUPS,
            grupos,
            &bytes) == -1) {
        perror("getsockopt SO_PEERGROUPS");
        return false;
    }

    if (bytes % sizeof(gid_t) != 0) {
        fprintf(stderr,
                "[CONTROLE] Lista de grupos inválida.\n");
        return false;
    }

    size_t quantidade = bytes / sizeof(gid_t);

    return grupo_presente(
        grupos,
        quantidade,
        GID_ADMIN_PADRAO);
}

static int solicitar_encerramento(const char *operacao)
{
    /*
     * O diretório /run/Lithos pertence ao root.
     * O daemon também executa como root.
     *
     * mkdir fornece exclusão atômica: apenas uma
     * solicitação de encerramento pode ficar ativa.
     */
    if (mkdir(CAMINHO_LOCK, 0700) == -1) {
        if (errno == EEXIST)
            return EBUSY;

        perror("mkdir lock");
        return EIO;
    }

    FILE *arquivo = fopen(CAMINHO_PEDIDO, "w");

    if (!arquivo) {
        perror("fopen pedido");
        rmdir(CAMINHO_LOCK);
        return EIO;
    }

    bool falhou = false;

    if (fprintf(arquivo, "%s\n", operacao) < 0)
        falhou = true;

    if (fclose(arquivo) == EOF)
        falhou = true;

    if (falhou) {
        fprintf(stderr,
                "[CONTROLE] Falha ao gravar pedido.\n");
        unlink(CAMINHO_PEDIDO);
        rmdir(CAMINHO_LOCK);
        return EIO;
    }

    /*
     * PID 1 é a autoridade final. Ele relê o pedido,
     * valida novamente a operação e executa encerrar().
     */
    if (kill(1, SIGUSR1) == -1) {
        perror("kill PID 1");
        unlink(CAMINHO_PEDIDO);
        rmdir(CAMINHO_LOCK);
        return EIO;
    }

    return 0;
}

static int criar_socket(void)
{
    int fd = socket(
        AF_UNIX,
        SOCK_SEQPACKET | SOCK_CLOEXEC,
        0);

    if (fd == -1) {
        perror("socket");
        return -1;
    }

    struct sockaddr_un endereco = {0};
    endereco.sun_family = AF_UNIX;

    if (strlen(CAMINHO_SOCKET) >=
        sizeof(endereco.sun_path)) {
        fprintf(stderr,
                "[CONTROLE] Caminho do socket muito longo.\n");
        close(fd);
        return -1;
    }

    strcpy(endereco.sun_path, CAMINHO_SOCKET);

    /*
     * O daemon só deve iniciar depois que /run/Lithos
     * tiver sido criado pelo PID 1.
     */
    struct stat estado;

    if (lstat(CAMINHO_SOCKET, &estado) == 0) {
        if (!S_ISSOCK(estado.st_mode)) {
            fprintf(stderr,
                    "[CONTROLE] O caminho existente não é socket.\n");
            close(fd);
            return -1;
        }

        if (unlink(CAMINHO_SOCKET) == -1) {
            perror("unlink socket antigo");
            close(fd);
            return -1;
        }
    } else if (errno != ENOENT) {
        perror("lstat socket");
        close(fd);
        return -1;
    }

    mode_t mascara_anterior = umask(0111);

    if (bind(
            fd,
            (struct sockaddr *)&endereco,
            sizeof(endereco)) == -1) {
        perror("bind");
        umask(mascara_anterior);
        close(fd);
        return -1;
    }

    umask(mascara_anterior);

    if (chmod(CAMINHO_SOCKET, 0666) == -1) {
        perror("chmod socket");
        unlink(CAMINHO_SOCKET);
        close(fd);
        return -1;
    }

    if (listen(fd, 16) == -1) {
        perror("listen");
        unlink(CAMINHO_SOCKET);
        close(fd);
        return -1;
    }

    return fd;
}

int main(void)
{
    struct sigaction acao = {0};
    acao.sa_handler = receber_sinal;
    sigemptyset(&acao.sa_mask);

    if (sigaction(SIGTERM, &acao, NULL) == -1 ||
        sigaction(SIGINT, &acao, NULL) == -1) {
        perror("sigaction");
        return 1;
    }

    socket_servidor = criar_socket();

    if (socket_servidor == -1)
        return 1;

    fprintf(stderr,
            "[CONTROLE] clcontrold inicializado.\n");

    /*
     * O daemon autentica o peer e encaminha apenas
     * operações administrativas válidas ao PID 1.
     */
    while (!encerrando) {
        int cliente = accept4(
            socket_servidor,
            NULL,
            NULL,
            SOCK_CLOEXEC);

        if (cliente == -1) {
            if (errno == EINTR && encerrando)
                break;

            if (errno == EINTR)
                continue;

            perror("accept4");
            break;
        }

        char pedido[TAMANHO_PEDIDO] = {0};

        /*
         * SOCK_SEQPACKET preserva os limites da mensagem.
         * MSG_TRUNC permite detectar um pedido maior que
         * nosso protocolo sem aceitá-lo parcialmente.
         */
        ssize_t recebido = recv(
            cliente,
            pedido,
            sizeof(pedido) - 1,
            MSG_TRUNC);

        if (recebido <= 0) {
            close(cliente);
            continue;
        }

        if ((size_t)recebido >= sizeof(pedido)) {
            static const char resposta[] = "EMSGSIZE";

            (void)send(
                cliente,
                resposta,
                sizeof(resposta) - 1,
                MSG_NOSIGNAL);

            close(cliente);
            continue;
        }

        pedido[recebido] = '\0';

        struct ucred credencial = {0};

        if (!autorizado(cliente, &credencial)) {
            static const char resposta[] = "EPERM";

            (void)send(
                cliente,
                resposta,
                sizeof(resposta) - 1,
                MSG_NOSIGNAL);

            close(cliente);
            continue;
        }

        if (!operacao_valida(pedido)) {
            static const char resposta[] = "EINVAL";

            (void)send(
                cliente,
                resposta,
                sizeof(resposta) - 1,
                MSG_NOSIGNAL);

            close(cliente);
            continue;
        }

        fprintf(stderr,
                "[CONTROLE] uid=%ld pid=%ld solicitou %s.\n",
                (long)credencial.uid,
                (long)credencial.pid,
                pedido);

        int resultado = solicitar_encerramento(pedido);

        const char *resposta;

        switch (resultado) {
            case 0:
                resposta = "OK";
                break;
            case EBUSY:
                resposta = "EBUSY";
                break;
            default:
                resposta = "EIO";
                break;
        }

        (void)send(
            cliente,
            resposta,
            strlen(resposta),
            MSG_NOSIGNAL);

        close(cliente);
    }

    if (socket_servidor >= 0)
        close(socket_servidor);

    unlink(CAMINHO_SOCKET);

    fprintf(stderr,
            "[CONTROLE] clcontrold encerrado.\n");

    return 0;
}
