/* signal.h - C89-compatible for GCC 1.42 (shadows musl version) */

#ifndef _GCC142_SIGNAL_H
#define _GCC142_SIGNAL_H

typedef void (*__sighandler_t)(int);
typedef __sighandler_t sig_t;

#define SIG_DFL ((__sighandler_t)0)
#define SIG_IGN ((__sighandler_t)1)
#define SIG_ERR ((__sighandler_t)-1)

#define SIGHUP    1
#define SIGINT    2
#define SIGQUIT   3
#define SIGILL    4
#define SIGTRAP   5
#define SIGABRT   6
#define SIGBUS    7
#define SIGFPE    8
#define SIGKILL   9
#define SIGUSR1  10
#define SIGSEGV  11
#define SIGUSR2  12
#define SIGPIPE  13
#define SIGALRM  14
#define SIGTERM  15
#define SIGCHLD  17
#define SIGCONT  18
#define SIGSTOP  19

extern __sighandler_t signal(int, __sighandler_t);
extern int raise(int);

#endif
