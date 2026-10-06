#define _GNU_SOURCE
#include <ctype.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

/* Intentionally bounded, strict ustar subset: no PAX/GNU extensions/hooks. */
#define LIMIT 10000
#define PATHMAX 1024
#define BYTES_MAX (512UL * 1024 * 1024)
typedef struct {
  char path[PATHMAX], target[PATHMAX], type;
  mode_t mode;
  unsigned long size, offset;
  unsigned long long dev, ino;
} Entry;
static Entry entries[LIMIT];
static size_t count;
static void fail(const char *s) {
  fprintf(stderr, "[CPM archive] %s (%s)\n", s, strerror(errno));
  exit(1);
}
static int safe(const char *s) {
  if (!*s || *s == '/' || strlen(s) >= PATHMAX)
    return 0;
  const char *p = s;
  while (*p) {
    const char *a = p;
    while (*p && *p != '/') {
      unsigned char c = (unsigned char)*p++;
      if (!(isalnum(c) && c < 128) && !strchr("_+.@-", c))
        return 0;
    }
    size_t n = (size_t)(p - a);
    if (!n || (n == 1 && *a == '.') || (n == 2 && a[0] == '.' && a[1] == '.'))
      return 0;
    if (*p++ == '\0')
      break;
    if (!*p)
      return 0;
  }
  return 1;
}
static int protected(const char *p) {
  const char *dirs[] = {"/",     "/bin",     "/sbin",     "/lib",     "/lib64",
                        "/usr",  "/usr/bin", "/usr/sbin", "/usr/lib", "/etc",
                        "/var",  "/home",    "/root",     "/boot",    "/dev",
                        "/proc", "/sys",     "/run",      NULL};
  for (int i = 0; dirs[i]; i++)
    if (!strcmp(p, dirs[i]))
      return 1;
  return 0;
}
static int reserved(const char *p) {
  const char *trees[] = {"/boot",    "/dev",         "/proc",          "/sys",
                         "/run",     "/tmp",         "/home",          "/root",
                         "/etc/cpm", "/var/lib/cpm", "/var/cache/cpm", NULL};
  const char *files[] = {"/init",
                         "/bin/busybox",
                         "/bin/ash",
                         "/bin/sh",
                         "/bin/bash",
                         "/bin/su",
                         "/usr/bin/sudo",
                         "/usr/bin/curl",
                         "/usr/bin/cpm",
                         "/usr/libexec/cpm/arquivo",
                         "/etc/passwd",
                         "/etc/group",
                         "/etc/shadow",
                         "/etc/sudoers",
                         "/etc/fstab",
                         "/usr/share/Lithos/base-abi-v1.sha256",
                         NULL};
  for (int i = 0; trees[i]; i++) {
    size_t n = strlen(trees[i]);
    if (!strncmp(p, trees[i], n) && (!p[n] || p[n] == '/'))
      return 1;
  }
  for (int i = 0; files[i]; i++)
    if (!strcmp(p, files[i]))
      return 1;
  return 0;
}
static unsigned long octal(const unsigned char *p, size_t n) {
  unsigned long v = 0;
  size_t i = 0;
  while (i < n && (p[i] == ' ' || !p[i]))
    i++;
  for (; i < n && p[i] >= '0' && p[i] <= '7'; i++) {
    if (v > BYTES_MAX)
      fail("número tar fora do limite");
    v = v * 8 + (p[i] - '0');
  }
  for (; i < n; i++)
    if (p[i] && p[i] != ' ')
      fail("campo octal tar inválido");
  return v;
}
static void field(char *out, const unsigned char *p, size_t n) {
  size_t len = strnlen((const char *)p, n);
  if (len >= PATHMAX)
    fail("campo longo");
  memcpy(out, p, len);
  out[len] = 0;
  for (size_t i = len; i < n; i++)
    if (p[i])
      fail("lixo após campo tar");
}
static int find_entry(const char *path) {
  for (size_t i = 0; i < count; i++)
    if (!strcmp(entries[i].path, path))
      return (int)i;
  return -1;
}
static void add_dir(const char *path) {
  int i = find_entry(path);
  if (i >= 0) {
    if (entries[i].type != 'd')
      fail("ancestral não é diretório");
    return;
  }
  if (count == LIMIT)
    fail("muitos membros");
  Entry *e = &entries[count++];
  strcpy(e->path, path);
  e->type = 'd';
  e->mode = 0755;
}
static int compare(const void *a, const void *b) {
  return strcmp(((const Entry *)a)->path, ((const Entry *)b)->path);
}
static int rootfd(const char *root) {
  int fd = open(root, O_DIRECTORY | O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
  struct stat st;
  if (fd < 0 || fstat(fd, &st) || st.st_uid != geteuid() || (st.st_mode & 0022))
    fail("raiz não confiável");
  return fd;
}
/* Walk every ancestor without following symlinks. Writable foreign ancestors
 * are forbidden, so payload cannot exploit a user's concurrent rename. */
static int parent(int root, const char *path, char *name, int create) {
  if (*path != '/')
    fail("destino não absoluto");
  if (!safe(path + 1))
    fail("destino inseguro");
  char buf[PATHMAX];
  strcpy(buf, path + 1);
  char *last = strrchr(buf, '/');
  if (!last) {
    strcpy(name, buf);
    return dup(root);
  }
  strcpy(name, last + 1);
  *last = 0;
  int fd = dup(root);
  char *save = NULL;
  for (char *p = strtok_r(buf, "/", &save); p; p = strtok_r(NULL, "/", &save)) {
    int next = openat(fd, p, O_DIRECTORY | O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
    if (next < 0 && errno == ENOENT && create) {
      if (mkdirat(fd, p, 0755))
        fail("mkdir staging");
      next = openat(fd, p, O_DIRECTORY | O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
    }
    if (next < 0) {
      close(fd);
      if (errno == ENOENT && !create)
        return -1;
      fail("ancestral inseguro/ausente");
    }
    struct stat st;
    if (fstat(next, &st) || st.st_uid != geteuid() || (st.st_mode & 0022))
      fail("ancestral gravável/não confiável");
    close(fd);
    fd = next;
  }
  return fd;
}
static void copy_data(int in, int out, unsigned long bytes) {
  char buf[65536];
  while (bytes) {
    size_t n = bytes > sizeof(buf) ? sizeof(buf) : (size_t)bytes;
    ssize_t r = read(in, buf, n);
    if (r <= 0)
      fail("payload truncado");
    for (ssize_t pos = 0; pos < r;) {
      ssize_t w = write(out, buf + pos, (size_t)(r - pos));
      if (w <= 0)
        fail("write payload");
      pos += w;
    }
    bytes -= (unsigned long)r;
  }
}
static void unpack(const char *tar, const char *stage) {
  int in = open(tar, O_RDONLY | O_NOFOLLOW);
  struct stat st;
  if (in < 0 || fstat(in, &st) || !S_ISREG(st.st_mode) || st.st_size < 0 ||
      (unsigned long)st.st_size > BYTES_MAX)
    fail("archive inválido/grande");
  unsigned char h[512];
  unsigned long pos = 0;
  int ended = 0, manifest = 0;
  while (read(in, h, 512) == 512) {
    pos += 512;
    int zero = 1;
    for (int i = 0; i < 512; i++)
      if (h[i])
        zero = 0;
    if (zero) {
      unsigned char tail[512];
      if (read(in, tail, 512) != 512)
        fail("fim tar incompleto");
      for (int i = 0; i < 512; i++)
        if (tail[i])
          fail("fim tar inválido");
      ssize_t n;
      while ((n = read(in, tail, 512)) > 0)
        for (ssize_t i = 0; i < n; i++)
          if (tail[i])
            fail("dados após fim tar");
      if (n < 0)
        fail("read archive");
      ended = 1;
      break;
    }
    unsigned long sum = 0;
    for (int i = 0; i < 512; i++)
      sum += (i >= 148 && i < 156) ? 32 : h[i];
    if (sum != octal(h + 148, 8))
      fail("checksum tar incorreto");
    if (memcmp(h + 257, "ustar", 5))
      fail("somente formato ustar é aceito");
    char name[PATHMAX], prefix[PATHMAX], target[PATHMAX], path[PATHMAX];
    field(name, h, 100);
    field(prefix, h + 345, 155);
    field(target, h + 157, 100);
    if (*prefix) {
      if (snprintf(path, sizeof(path), "%s/%s", prefix, name) >=
          (int)sizeof(path))
        fail("path longo");
    } else
      strcpy(path, name);
    size_t len = strlen(path);
    char type = (char)h[156];
    if (type == '5' && len && path[len - 1] == '/')
      path[--len] = 0;
    if (!safe(path))
      fail("path tar inseguro");
    unsigned long size = octal(h + 124, 12), mode = octal(h + 100, 8);
    if (mode & 07000 || (type != '2' && (mode & 0022)))
      fail("modo privilegiado/gravável não aceito");
    if (!strcmp(path, "CPM") || !strcmp(path, "payload")) {
      if (type != '5' || size)
        fail("container inválido");
    } else if (!strcmp(path, "CPM/MANIFEST")) {
      if ((type != '0' && type) || !size || size > 65536 || manifest++)
        fail("MANIFEST inválido/duplicado");
    } else if (strncmp(path, "payload/", 8))
      fail("membro fora do payload/MANIFEST");
    if (type != '0' && type && type != '5' && type != '2')
      fail("tipo tar não permitido (inclui hardlinks)");
    if ((type == '5' || type == '2') && size)
      fail("size de link/diretório inválido");
    if (size > BYTES_MAX ||
        pos + ((size + 511) / 512) * 512 > (unsigned long)st.st_size)
      fail("archive truncado");
    if (type == '2') {
      if (!*target || *target == '/' || strlen(target) >= PATHMAX)
        fail("symlink absoluto/vazio");
      /* Lexical expansion relative to payload parent, never above payload. */
      int depth = 0;
      for (const char *p = path + 8; *p; p++)
        if (*p == '/')
          depth++;
      char copy[PATHMAX];
      strcpy(copy, target);
      char *save = NULL;
      for (char *p = strtok_r(copy, "/", &save); p;
           p = strtok_r(NULL, "/", &save)) {
        if (!strcmp(p, "..")) {
          if (!depth--)
            fail("symlink escapa da raiz");
        } else if (strcmp(p, ".")) {
          if (!safe(p))
            fail("symlink inseguro");
          depth++;
        }
      }
    }
    if (find_entry(path) >= 0)
      fail("membro duplicado");
    if (count == LIMIT)
      fail("muitos membros");
    Entry *e = &entries[count++];
    strcpy(e->path, path);
    strcpy(e->target, target);
    e->mode = (mode_t)mode;
    e->type = type == '5' ? 'd' : type == '2' ? 'l' : 'f';
    e->size = size;
    e->offset = pos;
    pos += ((size + 511) / 512) * 512;
    if (lseek(in, (off_t)pos, SEEK_SET) < 0)
      fail("seek archive");
  }
  if (!ended || !manifest)
    fail("archive truncado ou MANIFEST ausente");
  size_t original = count;
  for (size_t i = 0; i < original; i++) {
    char p[PATHMAX];
    strcpy(p, entries[i].path);
    for (char *s = strrchr(p, '/'); s; s = strrchr(p, '/')) {
      *s = 0;
      add_dir(p);
    }
  }
  qsort(entries, count, sizeof(Entry), compare);
  int root = rootfd(stage);
  FILE *list = NULL;
  int lfd = openat(root, "files", O_WRONLY | O_CREAT | O_EXCL, 0600);
  if (lfd < 0 || !(list = fdopen(lfd, "w")))
    fail("lista staging");
  for (size_t i = 0; i < count; i++) {
    Entry *e = &entries[i];
    char path[PATHMAX], name[PATHMAX];
    if (snprintf(path, sizeof(path), "/%s", e->path) >= (int)sizeof(path))
      fail("path longo");
    int dir = parent(root, path, name, 1);
    if (e->type == 'd') {
      if (mkdirat(dir, name, 0755) && errno != EEXIST)
        fail("mkdir archive");
    } else if (e->type == 'l') {
      if (symlinkat(e->target, dir, name))
        fail("symlink archive");
    } else {
      int out =
          openat(dir, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0600);
      if (out < 0 || lseek(in, (off_t)e->offset, SEEK_SET) < 0)
        fail("extract file");
      copy_data(in, out, e->size);
      if (fchmod(out, e->mode) || fsync(out))
        fail("chmod/fsync file");
      close(out);
    }
    close(dir);
    if (!strncmp(e->path, "payload/", 8)) {
      const char *dest = e->path + 7;
      if (reserved(dest))
        fail("namespace reservado");
      fprintf(list, "%c|%s\n", e->type, dest);
    }
  }
  if (fclose(list))
    fail("write lista");
  close(root);
  close(in);
}
static void load(const char *file, int recorded) {
  FILE *f = fopen(file, "r");
  if (!f)
    fail("files ausente");
  char line[PATHMAX * 2];
  count = 0;
  while (fgets(line, sizeof(line), f)) {
    if (!strchr(line, '\n') || count == LIMIT)
      fail("registro inválido/longo");
    line[strcspn(line, "\n")] = 0;
    Entry *e = &entries[count++];
    memset(e, 0, sizeof(*e));
    char *save = NULL, *t = strtok_r(line, "|", &save),
         *p = strtok_r(NULL, "|", &save);
    if (!t || strlen(t) != 1 || !strchr("fdl", *t) || !p || *p != '/' ||
        !safe(p + 1))
      fail("registro inseguro");
    e->type = *t;
    strcpy(e->path, p);
    if (recorded) {
      char *d = strtok_r(NULL, "|", &save), *ino = strtok_r(NULL, "|", &save),
           *end = NULL;
      if (!d || !ino)
        fail("registro sem inode");
      errno = 0;
      e->dev = strtoull(d, &end, 10);
      if (errno || *end || !isdigit((unsigned char)*d))
        fail("dev inválido");
      e->ino = strtoull(ino, &end, 10);
      if (errno || *end || !e->ino || !isdigit((unsigned char)*ino))
        fail("inode inválido");
    }
    if (strtok_r(NULL, "|", &save))
      fail("campos extras em files");
    for (size_t j = 0; j + 1 < count; j++)
      if (!strcmp(entries[j].path, p))
        fail("files duplicado");
  }
  if (ferror(f))
    fail("read files");
  fclose(f);
}
static int owned(const char *file, const char *path, const char *pkg) {
  FILE *f = fopen(file, "r");
  if (!f)
    fail("ownership ausente");
  char line[PATHMAX + 256];
  int result = 0;
  while (fgets(line, sizeof(line), f)) {
    if (!strchr(line, '\n'))
      fail("ownership corrompido");
    line[strcspn(line, "\n")] = 0;
    char *sep = strchr(line, '|');
    if (!sep || strchr(sep + 1, '|') || !sep[1])
      fail("ownership corrompido");
    *sep = 0;
    if (*line != '/' || !safe(line + 1) || protected(line) || reserved(line))
      fail("ownership inseguro");
    if (!strcmp(line, path)) {
      if (result)
        fail("ownership duplicado");
      result = !strcmp(sep + 1, pkg) ? 1 : 2;
    }
  }
  if (ferror(f))
    fail("read ownership");
  fclose(f);
  return result;
}
static int abi_file(int root, const char *path) {
  int fd = openat(root, "usr/share/Lithos/base-abi-v1.sha256",
                  O_RDONLY | O_NOFOLLOW);
  if (fd < 0) {
    if (errno == ENOENT)
      return 0;
    fail("manifest ABI");
  }
  FILE *f = fdopen(fd, "r");
  if (!f)
    fail("manifest ABI stream");
  char line[PATHMAX + 80];
  int found = 0;
  while (fgets(line, sizeof(line), f))
    if (strlen(line) > 66 && line[64] == ' ' && line[65] == ' ') {
      line[strcspn(line, "\n")] = 0;
      if (!strcmp(path + 1, line + 66))
        found = 1;
    }
  fclose(f);
  return found;
}
static void check(int root, const char *ownership, const char *pkg,
                  int removing) {
  for (size_t i = 0; i < count; i++) {
    Entry *e = &entries[i];
    char name[PATHMAX];
    if ((protected(e->path) && (removing || e->type != 'd')) ||
        reserved(e->path) || abi_file(root, e->path))
      fail("destino protegido/base ABI");
    int o = owned(ownership, e->path, pkg);
    int dir = parent(root, e->path, name, 0);
    struct stat st;
    int exists = dir >= 0 && !fstatat(dir, name, &st, AT_SYMLINK_NOFOLLOW);
    if (dir >= 0 && !exists && errno != ENOENT)
      fail("stat destino");
    if (removing) {
      if (o != 1 || !exists || (unsigned long long)st.st_dev != e->dev ||
          (unsigned long long)st.st_ino != e->ino ||
          (e->type == 'f' && !S_ISREG(st.st_mode)) ||
          (e->type == 'l' && !S_ISLNK(st.st_mode)) ||
          (e->type == 'd' && !S_ISDIR(st.st_mode)))
        fail("ownership/inode de remoção divergente");
    } else if (e->type == 'd') {
      if (exists && (!S_ISDIR(st.st_mode) || st.st_uid != geteuid() ||
                     (st.st_mode & 0022)))
        fail("colisão/ancestral inseguro");
    } else if (exists || o)
      fail(o ? "colisão ownership" : "colisão unmanaged");
    if (dir >= 0)
      close(dir);
  }
}
static void journal(FILE *f, Entry *e, const struct stat *st,
                    const char *backup) {
  fprintf(f, "%c|%s|%llu|%llu|%s\n", e->type, e->path,
          (unsigned long long)st->st_dev, (unsigned long long)st->st_ino,
          backup);
  if (fflush(f) || fsync(fileno(f)))
    fail("journal fsync");
}
static void apply(const char *rootpath, const char *stage, const char *files,
                  const char *ownership, const char *pkg, const char *log,
                  int removing) {
  load(files, removing);
  int root = rootfd(rootpath);
  check(root, ownership, pkg, removing);
  FILE *j = fopen(log, "wx");
  if (!j)
    fail("journal exclusivo");
  fprintf(j, "%c\n", removing ? 'R' : 'I');
  if (fflush(j) || fsync(fileno(j)))
    fail("journal header");
  char logdir[PATHMAX];
  if (strlen(log) >= sizeof(logdir))
    fail("journal path longo");
  strcpy(logdir, log);
  char *slash = strrchr(logdir, '/');
  if (!slash || slash == logdir)
    fail("journal parent inválido");
  *slash = 0;
  int journal_dir = open(logdir, O_RDONLY | O_DIRECTORY | O_NOFOLLOW);
  if (journal_dir < 0 || fsync(journal_dir))
    fail("journal parent fsync");
  close(journal_dir);
  sigset_t blocked;
  sigemptyset(&blocked);
  sigaddset(&blocked, SIGINT);
  sigaddset(&blocked, SIGTERM);
  sigaddset(&blocked, SIGHUP);
  if (sigprocmask(SIG_BLOCK, &blocked, NULL))
    fail("signals");
  int source = removing ? -1 : rootfd(stage);
  for (size_t i = 0; i < count; i++) {
    Entry *e = &entries[i];
    char name[PATHMAX];
    int dir = parent(root, e->path, name, 0);
    if (dir < 0)
      fail("parent ausente no commit");
    struct stat st;
    if (e->type == 'd') {
      if (removing) {
        if (fstatat(dir, name, &st, AT_SYMLINK_NOFOLLOW))
          fail("stat diretório remove");
        journal(j, e, &st, "-");
      }
      if (!removing && fstatat(dir, name, &st, AT_SYMLINK_NOFOLLOW)) {
        if (errno != ENOENT || mkdirat(dir, name, 0755) ||
            fstatat(dir, name, &st, AT_SYMLINK_NOFOLLOW))
          fail("mkdir commit");
        if (!protected(e->path) && !reserved(e->path))
          journal(j, e, &st, "-");
      }
      if (fsync(dir))
        fail("fsync diretório commit");
      close(dir);
      continue;
    }
    char temp[80], backup[PATHMAX];
    snprintf(temp, sizeof(temp), ".cpm-%ld-%zu", (long)getpid(), i);
    const char *last = strrchr(e->path, '/');
    size_t prefix = (size_t)(last - e->path);
    if (snprintf(backup, sizeof(backup), "%.*s/%s", (int)prefix, e->path,
                 temp) >= (int)sizeof(backup))
      fail("temp path");
    if (removing) {
      if (fstatat(dir, name, &st, AT_SYMLINK_NOFOLLOW))
        fail("stat remoção");
      journal(j, e, &st, backup);
      if (renameat2(dir, name, dir, temp, RENAME_NOREPLACE))
        fail("staging remoção");
    } else {
      char srcpath[PATHMAX], srcname[PATHMAX];
      if (snprintf(srcpath, sizeof(srcpath), "/payload%s", e->path) >=
          (int)sizeof(srcpath))
        fail("src path");
      int srcdir = parent(source, srcpath, srcname, 0);
      if (srcdir < 0 || fstatat(srcdir, srcname, &st, AT_SYMLINK_NOFOLLOW))
        fail("staging file ausente");
      if (e->type == 'l') {
        char target[PATHMAX];
        ssize_t n = readlinkat(srcdir, srcname, target, sizeof(target) - 1);
        if (n <= 0 || n >= (ssize_t)sizeof(target) - 1)
          fail("readlink staging");
        target[n] = 0;
        if (symlinkat(target, dir, temp))
          fail("create symlink commit");
      } else {
        int in = openat(srcdir, srcname, O_RDONLY | O_NOFOLLOW),
            out = openat(dir, temp, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW,
                         0600);
        if (in < 0 || out < 0 || !S_ISREG(st.st_mode))
          fail("create staging commit");
        copy_data(in, out, (unsigned long)st.st_size);
        if (fchmod(out, st.st_mode & 0777) || fsync(out))
          fail("commit chmod/fsync");
        close(in);
        close(out);
      }
      close(srcdir);
      if (fstatat(dir, temp, &st, AT_SYMLINK_NOFOLLOW))
        fail("stat temp commit");
      journal(j, e, &st, backup);
      if (renameat2(dir, temp, dir, name, RENAME_NOREPLACE))
        fail("commit sem overwrite");
    }
    if (fsync(dir))
      fail("fsync parent");
    close(dir);
  }
  if (source >= 0)
    close(source);
  fclose(j);
  close(root);
}
static void finish(const char *rootpath, const char *log, int finalize) {
  FILE *f = fopen(log, "r");
  if (!f) {
    if (errno == ENOENT)
      return;
    fail("journal read");
  }
  char line[PATHMAX * 2 + 100];
  if (!fgets(line, sizeof(line), f) ||
      (strcmp(line, "I\n") && strcmp(line, "R\n")))
    fail("journal inválido");
  int removal = *line == 'R';
  count = 0;
  while (fgets(line, sizeof(line), f)) {
    if (!strchr(line, '\n') || count == LIMIT)
      fail("journal longo");
    line[strcspn(line, "\n")] = 0;
    Entry *e = &entries[count++];
    memset(e, 0, sizeof(*e));
    char *save = NULL, *t = strtok_r(line, "|", &save),
         *p = strtok_r(NULL, "|", &save), *dev = strtok_r(NULL, "|", &save),
         *ino = strtok_r(NULL, "|", &save),
         *backup = strtok_r(NULL, "|", &save), *end = NULL;
    if (!t || strlen(t) != 1 || !strchr("fdl", *t) || !p || *p != '/' ||
        !safe(p + 1) || protected(p) || reserved(p) || !dev || !ino ||
        !backup || strtok_r(NULL, "|", &save))
      fail("journal inseguro");
    e->type = *t;
    strcpy(e->path, p);
    strcpy(e->target, backup);
    errno = 0;
    e->dev = strtoull(dev, &end, 10);
    if (errno || *end)
      fail("journal dev");
    e->ino = strtoull(ino, &end, 10);
    if (errno || *end || !e->ino)
      fail("journal inode");
    if (e->type != 'd') {
      const char *a = strrchr(p, '/'), *b = strrchr(backup, '/');
      if (*backup != '/' || !safe(backup + 1) || !b ||
          (a - p) != (b - backup) || strncmp(p, backup, (size_t)(a - p)) ||
          strncmp(b + 1, ".cpm-", 5))
        fail("journal backup inseguro");
    } else if (strcmp(backup, "-"))
      fail("journal diretório inválido");
  }
  if (ferror(f))
    fail("journal read");
  fclose(f);
  int root = rootfd(rootpath);
  for (size_t k = count; k > 0; k--) {
    Entry *e = &entries[k - 1];
    char name[PATHMAX], backname[PATHMAX];
    int dir = parent(root, e->path, name, 0);
    if (dir < 0)
      continue;
    struct stat st;
    if (e->type == 'd') {
      if ((!removal && !finalize) || (removal && finalize)) {
        if (!fstatat(dir, name, &st, AT_SYMLINK_NOFOLLOW)) {
          if ((unsigned long long)st.st_dev != e->dev ||
              (unsigned long long)st.st_ino != e->ino || !S_ISDIR(st.st_mode))
            fail("diretório alterado");
          if (unlinkat(dir, name, AT_REMOVEDIR) && errno != ENOTEMPTY &&
              errno != EEXIST)
            fail("rmdir seguro");
        } else if (errno != ENOENT)
          fail("stat diretório undo");
      }
    } else {
      strcpy(backname, strrchr(e->target, '/') + 1);
      const char *item = (removal || finalize) ? backname : name;
      if (!fstatat(dir, item, &st, AT_SYMLINK_NOFOLLOW)) {
        if ((unsigned long long)st.st_dev != e->dev ||
            (unsigned long long)st.st_ino != e->ino)
          fail("inode de undo divergente");
        if (removal && !finalize) {
          if (renameat2(dir, backname, dir, name, RENAME_NOREPLACE))
            fail("restaurar payload");
        } else if (unlinkat(dir, item, 0))
          fail("unlink transação");
      } else if (errno != ENOENT)
        fail("stat undo");
      if (!removal && !finalize &&
          !fstatat(dir, backname, &st, AT_SYMLINK_NOFOLLOW)) {
        if ((unsigned long long)st.st_dev != e->dev ||
            (unsigned long long)st.st_ino != e->ino ||
            unlinkat(dir, backname, 0))
          fail("limpar temp commit");
      }
    }
    if (fsync(dir))
      fail("undo fsync");
    close(dir);
  }
  close(root);
}
int main(int argc, char **argv) {
  if (argc == 3 && !strcmp(argv[1], "root")) {
    int root = rootfd(argv[2]);
    close(root);
  } else if (argc == 4 && !strcmp(argv[1], "unpack"))
    unpack(argv[2], argv[3]);
  else if (argc == 7 && !strcmp(argv[1], "check")) {
    load(argv[3], !strcmp(argv[6], "remove"));
    int root = rootfd(argv[2]);
    check(root, argv[4], argv[5], !strcmp(argv[6], "remove"));
    close(root);
  } else if (argc == 8 &&
             (!strcmp(argv[1], "install") || !strcmp(argv[1], "remove")))
    apply(argv[2], argv[3], argv[4], argv[5], argv[6], argv[7],
          !strcmp(argv[1], "remove"));
  else if (argc == 4 &&
           (!strcmp(argv[1], "undo") || !strcmp(argv[1], "finalize")))
    finish(argv[2], argv[3], !strcmp(argv[1], "finalize"));
  else {
    fprintf(stderr,
            "CPM archive v0.2: unpack/check/install/remove/undo/finalize\n");
    return 2;
  }
  return 0;
}
