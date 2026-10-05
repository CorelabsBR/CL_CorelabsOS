#include <gnu/libc-version.h>
#include <math.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>
#include <dlfcn.h>
#include <grp.h>
#include <netdb.h>
#include <pwd.h>
#include <signal.h>

static volatile sig_atomic_t signal_seen;
static void handler(int signal_number) {
    signal_seen = signal_number;
}

static void *worker(void *unused) {
    (void)unused;
    return (void *)42;
}

int main(int argc, char **argv) {
    struct sigaction action = {0};
    action.sa_handler = handler;
    sigemptyset(&action.sa_mask);
    if (sigaction(SIGUSR1, &action, NULL) || raise(SIGUSR1) || signal_seen != SIGUSR1)
        return 5;
    pthread_t thread;
    void *result = NULL;
    void *handle = dlopen("libm.so.6", RTLD_NOW);
    if (!handle || pthread_create(&thread, NULL, worker, NULL) ||
        pthread_join(thread, &result) || result != (void *)42)
        return 1;
    double (*cosine)(double) = (double (*)(double))dlsym(handle, "cos");
    if (!cosine || fabs(cosine(0.0) - 1.0) > 0.000001)
        return 2;
    dlclose(handle);
    struct passwd *user = getpwnam("girelli");
    struct group *wheel = getgrnam("wheel");
    if (!user || user->pw_uid != 1000 || user->pw_gid != 100 ||
        !wheel || wheel->gr_gid != 10)
        return 3;
    if (argc > 1 && strcmp(argv[1], "--dns") == 0) {
        struct addrinfo *addresses = NULL;
        if (getaddrinfo("example.com", "443", NULL, &addresses) != 0)
            return 4;
        freeaddrinfo(addresses);
        puts("hello-corelabs C: NSS files/DNS OK");
    }
    printf("hello-corelabs C: glibc %s; signal/pthread/dlopen/libm OK\n", gnu_get_libc_version());
    return strcmp(gnu_get_libc_version(), "2.44") != 0;
}
