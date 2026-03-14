/* stdlib.h - C89-compatible for GCC 1.42 (shadows musl's __restrict version) */

#ifndef _GCC142_STDLIB_H
#define _GCC142_STDLIB_H

#include <stddef.h>

#define EXIT_SUCCESS 0
#define EXIT_FAILURE 1
#define RAND_MAX 2147483647
#define MB_CUR_MAX 4

extern void exit(int);
extern void abort(void);
extern int atexit(void (*)(void));
extern void _exit(int);

extern void *malloc(size_t);
extern void *calloc(size_t, size_t);
extern void *realloc(void *, size_t);
extern void free(void *);

extern int atoi(const char *);
extern long atol(const char *);
extern double atof(const char *);
extern long strtol(const char *, char **, int);
extern unsigned long strtoul(const char *, char **, int);
extern double strtod(const char *, char **);

extern int abs(int);
extern long labs(long);
extern int rand(void);
extern void srand(unsigned int);

extern void qsort(void *, size_t, size_t, int (*)(const void *, const void *));
extern void *bsearch(const void *, const void *, size_t, size_t,
                      int (*)(const void *, const void *));

extern char *getenv(const char *);
extern int system(const char *);
extern int mkstemp(char *);

#endif
