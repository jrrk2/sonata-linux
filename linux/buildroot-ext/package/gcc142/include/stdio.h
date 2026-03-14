/* stdio.h - C89-compatible for GCC 1.42 (shadows musl's __restrict version) */

#ifndef _GCC142_STDIO_H
#define _GCC142_STDIO_H

#include <stddef.h>
#include <stdarg.h>

typedef struct _IO_FILE FILE;
typedef long fpos_t;

extern FILE *stdin;
extern FILE *stdout;
extern FILE *stderr;

#define EOF (-1)
#define BUFSIZ 1024
#define FILENAME_MAX 4096
#define FOPEN_MAX 1000
#define L_tmpnam 20
#define TMP_MAX 10000

#define SEEK_SET 0
#define SEEK_CUR 1
#define SEEK_END 2

#define _IOFBF 0
#define _IOLBF 1
#define _IONBF 2

extern int printf(const char *, ...);
extern int fprintf(FILE *, const char *, ...);
extern int sprintf(char *, const char *, ...);
extern int snprintf(char *, size_t, const char *, ...);
extern int scanf(const char *, ...);
extern int fscanf(FILE *, const char *, ...);
extern int sscanf(const char *, const char *, ...);

extern int vprintf(const char *, va_list);
extern int vfprintf(FILE *, const char *, va_list);
extern int vsprintf(char *, const char *, va_list);

extern int fgetc(FILE *);
extern int fputc(int, FILE *);
extern int getc(FILE *);
extern int putc(int, FILE *);
extern int getchar(void);
extern int putchar(int);
extern int ungetc(int, FILE *);

extern char *fgets(char *, int, FILE *);
extern int fputs(const char *, FILE *);
extern int puts(const char *);

extern size_t fread(void *, size_t, size_t, FILE *);
extern size_t fwrite(const void *, size_t, size_t, FILE *);

extern FILE *fopen(const char *, const char *);
extern FILE *freopen(const char *, const char *, FILE *);
extern FILE *fdopen(int, const char *);
extern int fclose(FILE *);
extern int fflush(FILE *);

extern int fseek(FILE *, long, int);
extern long ftell(FILE *);
extern void rewind(FILE *);
extern int fgetpos(FILE *, fpos_t *);
extern int fsetpos(FILE *, const fpos_t *);

extern int feof(FILE *);
extern int ferror(FILE *);
extern void clearerr(FILE *);

extern void perror(const char *);
extern int remove(const char *);
extern int rename(const char *, const char *);
extern FILE *tmpfile(void);
extern char *tmpnam(char *);

extern void setbuf(FILE *, char *);
extern int setvbuf(FILE *, char *, int, size_t);

extern int fileno(FILE *);
extern FILE *popen(const char *, const char *);
extern int pclose(FILE *);

#endif
