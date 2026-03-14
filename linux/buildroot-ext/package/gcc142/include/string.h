/* string.h - C89-compatible for GCC 1.42 (shadows musl's __restrict version) */

#ifndef _GCC142_STRING_H
#define _GCC142_STRING_H

#include <stddef.h>

extern size_t strlen(const char *);
extern char *strcpy(char *, const char *);
extern char *strncpy(char *, const char *, size_t);
extern char *strcat(char *, const char *);
extern char *strncat(char *, const char *, size_t);

extern int strcmp(const char *, const char *);
extern int strncmp(const char *, const char *, size_t);
extern int strcoll(const char *, const char *);

extern char *strchr(const char *, int);
extern char *strrchr(const char *, int);
extern char *strstr(const char *, const char *);
extern char *strpbrk(const char *, const char *);
extern size_t strspn(const char *, const char *);
extern size_t strcspn(const char *, const char *);
extern char *strtok(char *, const char *);

extern char *strdup(const char *);
extern char *strerror(int);

extern void *memcpy(void *, const void *, size_t);
extern void *memmove(void *, const void *, size_t);
extern void *memset(void *, int, size_t);
extern int memcmp(const void *, const void *, size_t);
extern void *memchr(const void *, int, size_t);

/* BSD compat */
extern void bcopy(const void *, void *, size_t);
extern void bzero(void *, size_t);
extern char *index(const char *, int);
extern char *rindex(const char *, int);

#endif
