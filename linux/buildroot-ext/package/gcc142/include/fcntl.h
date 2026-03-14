/* fcntl.h - POSIX file control for GCC 1.42 (shadows musl version) */

#ifndef _GCC142_FCNTL_H
#define _GCC142_FCNTL_H

#define O_RDONLY   0
#define O_WRONLY   1
#define O_RDWR     2
#define O_CREAT  0100
#define O_EXCL   0200
#define O_NOCTTY 0400
#define O_TRUNC  01000
#define O_APPEND 02000

extern int open(const char *, int, ...);
extern int creat(const char *, int);
extern int fcntl(int, int, ...);

#endif
