/* unistd.h - POSIX basics for GCC 1.42 (shadows musl version) */

#ifndef _GCC142_UNISTD_H
#define _GCC142_UNISTD_H

#include <stddef.h>

typedef int ssize_t;
typedef int off_t;
typedef int pid_t;
typedef unsigned int uid_t;
typedef unsigned int gid_t;

#define STDIN_FILENO  0
#define STDOUT_FILENO 1
#define STDERR_FILENO 2

#define R_OK 4
#define W_OK 2
#define X_OK 1
#define F_OK 0

extern ssize_t read(int, void *, size_t);
extern ssize_t write(int, const void *, size_t);
extern int close(int);
extern off_t lseek(int, off_t, int);
extern int dup(int);
extern int dup2(int, int);
extern int pipe(int *);

extern int unlink(const char *);
extern int rmdir(const char *);
extern int link(const char *, const char *);
extern int symlink(const char *, const char *);
extern int access(const char *, int);
extern int chdir(const char *);
extern char *getcwd(char *, size_t);
extern int chown(const char *, uid_t, gid_t);

extern pid_t fork(void);
extern int execl(const char *, const char *, ...);
extern int execv(const char *, char *const *);
extern int execle(const char *, const char *, ...);
extern int execve(const char *, char *const *, char *const *);
extern int execlp(const char *, const char *, ...);
extern int execvp(const char *, char *const *);
extern pid_t getpid(void);
extern pid_t getppid(void);
extern uid_t getuid(void);
extern gid_t getgid(void);

extern unsigned int sleep(unsigned int);
extern int usleep(unsigned int);
extern int isatty(int);

extern int brk(void *);
extern void *sbrk(int);

#endif
