#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <signal.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#define LIMITE_REINICIOS 5
#define INTERVALO_REINICIO 2
#define TEMPO_ESTABILIDADE 30

enum politica {
    POLITICA_SEMPRE,
    POLITICA_FALHA,
    POLITICA_NUNCA
};

static volatile sig_atomic_t encerrando = 0;
static volatile sig_atomic_t pid_filho = -1;

static void receber_sinal(int sinal)
{
    (void)sinal;
    encerrando = 1;

    if (pid_filho > 0) {
        kill(-(pid_t)pid_filho, SIGTERM);
    }
}

static void registrar(const char *mensagem)
{
    time_t agora = time(NULL);
    struct tm horario;
    char data[32];

    if (localtime_r(&agora, &horario) &&
        strftime(data, sizeof(data),
                 "%Y-%m-%d %H:%M:%S", &horario)) {
        fprintf(stderr,
                "[%s] [SUPERVISOR] %s\n",
                data, mensagem);
    } else {
        fprintf(stderr,
                "[SUPERVISOR] %s\n",
                mensagem);
    }

    fflush(stderr);
}

static void aguardar_intervalo(unsigned int segundos)
{
    struct timespec intervalo = {
        .tv_sec = segundos,
        .tv_nsec = 0
    };

    while (!encerrando) {
        if (nanosleep(&intervalo, &intervalo) == 0)
            break;

        if (errno != EINTR)
            break;
    }
}


static void limpar_grupo(pid_t grupo)
{
    if (grupo <= 0)
        return;

    /*
     * O processo principal já foi recolhido.
     * Os descendentes convencionais permanecem
     * no grupo criado pelo supervisor.
     */
    if (kill(-grupo, SIGTERM) == -1) {
        if (errno == ESRCH)
            return;

        perror("kill SIGTERM");
    }

    struct timespec intervalo = {
        .tv_sec = 0,
        .tv_nsec = 100000000
    };

    for (int tentativa = 0; tentativa < 20; tentativa++) {
        if (kill(-grupo, 0) == -1) {
            if (errno == ESRCH)
                return;

            perror("kill verificação");
            break;
        }

        struct timespec restante = intervalo;

        while (nanosleep(&restante, &restante) == -1 &&
               errno == EINTR) {
        }
    }

    if (kill(-grupo, SIGKILL) == -1 &&
        errno != ESRCH) {
        perror("kill SIGKILL");
    }
}

static enum politica obter_politica(const char *valor)
{
    if (strcmp(valor, "sempre") == 0)
        return POLITICA_SEMPRE;

    if (strcmp(valor, "falha") == 0)
        return POLITICA_FALHA;

    if (strcmp(valor, "nunca") == 0)
        return POLITICA_NUNCA;

    fprintf(stderr, "Política inválida: %s\n", valor);
    exit(2);
}

int main(int argc, char **argv)
{
    if (argc < 4 || strcmp(argv[2], "--") != 0) {
        fprintf(stderr,
                "Uso: clsupervisor "
                "{sempre|falha|nunca} -- "
                "<programa> [argumentos...]\n");
        return 2;
    }

    enum politica politica = obter_politica(argv[1]);

    sigset_t bloqueados;
    sigset_t anteriores;

    sigemptyset(&bloqueados);
    sigaddset(&bloqueados, SIGTERM);
    sigaddset(&bloqueados, SIGINT);

    struct sigaction acao = {0};
    acao.sa_handler = receber_sinal;
    sigemptyset(&acao.sa_mask);

    if (sigaction(SIGTERM, &acao, NULL) == -1 ||
        sigaction(SIGINT, &acao, NULL) == -1) {
        perror("sigaction");
        return 1;
    }

    int reinicios = 0;
    int codigo_final = 0;

    registrar("Supervisor inicializado.");

    while (!encerrando) {
        if (sigprocmask(SIG_BLOCK,
                        &bloqueados,
                        &anteriores) == -1) {
            perror("sigprocmask");
            return 1;
        }

        if (encerrando) {
            sigprocmask(SIG_SETMASK, &anteriores, NULL);
            break;
        }

        time_t inicio = time(NULL);
        pid_t filho = fork();

        if (filho < 0) {
            perror("fork");
            sigprocmask(SIG_SETMASK, &anteriores, NULL);
            return 1;
        }

        if (filho == 0) {
            struct sigaction padrao = {0};
            padrao.sa_handler = SIG_DFL;
            sigemptyset(&padrao.sa_mask);

            sigaction(SIGTERM, &padrao, NULL);
            sigaction(SIGINT, &padrao, NULL);

            setpgid(0, 0);

            sigprocmask(SIG_SETMASK,
                        &anteriores,
                        NULL);

            execvp(argv[3], &argv[3]);

            perror("execvp");
            _exit(127);
        }

        pid_filho = filho;

        /*
         * O pai também tenta estabelecer o grupo,
         * evitando depender exclusivamente do filho.
         */
        if (setpgid(filho, filho) == -1 &&
            errno != EACCES &&
            errno != ESRCH) {
            perror("setpgid");
        }

        sigprocmask(SIG_SETMASK, &anteriores, NULL);

        char mensagem[160];

        snprintf(mensagem, sizeof(mensagem),
                 "Processo iniciado. PID: %ld",
                 (long)filho);
        registrar(mensagem);

        int estado = 0;
        pid_t resultado;

        do {
            resultado = waitpid(filho, &estado, 0);
        } while (resultado == -1 && errno == EINTR);

        pid_filho = -1;

        /*
         * Antes de reiniciar ou encerrar, eliminar
         * os descendentes do serviço anterior.
         */
        limpar_grupo(filho);

        if (resultado == -1) {
            perror("waitpid");
            return 1;
        }

        bool falhou = false;

        if (WIFEXITED(estado)) {
            codigo_final = WEXITSTATUS(estado);
            falhou = codigo_final != 0;

            snprintf(mensagem, sizeof(mensagem),
                     "Processo encerrado. Código: %d",
                     codigo_final);
        } else if (WIFSIGNALED(estado)) {
            codigo_final = 128 + WTERMSIG(estado);
            falhou = true;

            snprintf(mensagem, sizeof(mensagem),
                     "Processo encerrado por sinal: %d",
                     WTERMSIG(estado));
        } else {
            codigo_final = 1;
            falhou = true;

            snprintf(mensagem, sizeof(mensagem),
                     "Estado inesperado do processo.");
        }

        registrar(mensagem);

        if (encerrando)
            break;

        bool reiniciar =
            politica == POLITICA_SEMPRE ||
            (politica == POLITICA_FALHA && falhou);

        if (!reiniciar)
            break;

        time_t fim = time(NULL);

        if (inicio != (time_t)-1 &&
            fim != (time_t)-1 &&
            fim - inicio >= TEMPO_ESTABILIDADE) {
            reinicios = 0;
        }

        reinicios++;

        if (reinicios > LIMITE_REINICIOS) {
            registrar(
                "Limite de reinicializações atingido."
            );
            return 1;
        }

        snprintf(mensagem, sizeof(mensagem),
                 "Reinicialização %d/%d.",
                 reinicios, LIMITE_REINICIOS);
        registrar(mensagem);

        aguardar_intervalo(INTERVALO_REINICIO);
    }

    registrar("Supervisor encerrado.");

    return encerrando ? 0 : codigo_final;
}
