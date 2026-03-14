/* ctype.h - C89-compatible for GCC 1.42 (shadows musl's locale version) */

#ifndef _GCC142_CTYPE_H
#define _GCC142_CTYPE_H

extern int isalnum(int);
extern int isalpha(int);
extern int iscntrl(int);
extern int isdigit(int);
extern int isgraph(int);
extern int islower(int);
extern int isprint(int);
extern int ispunct(int);
extern int isspace(int);
extern int isupper(int);
extern int isxdigit(int);

extern int toupper(int);
extern int tolower(int);

#endif
