/* setjmp.h - C89-compatible for GCC 1.42 (shadows musl version) */

#ifndef _GCC142_SETJMP_H
#define _GCC142_SETJMP_H

/* RV32: 13 registers (ra, sp, s0-s11) = 13 words */
typedef int jmp_buf[13];

extern int setjmp(jmp_buf);
extern void longjmp(jmp_buf, int);

#endif
