/* math.h - C89-compatible for GCC 1.42 (shadows musl's __restrict version) */

#ifndef _GCC142_MATH_H
#define _GCC142_MATH_H

#define HUGE_VAL 1e500

extern double sin(double);
extern double cos(double);
extern double tan(double);
extern double asin(double);
extern double acos(double);
extern double atan(double);
extern double atan2(double, double);

extern double sinh(double);
extern double cosh(double);
extern double tanh(double);

extern double exp(double);
extern double log(double);
extern double log10(double);
extern double pow(double, double);
extern double sqrt(double);

extern double ceil(double);
extern double floor(double);
extern double fabs(double);
extern double fmod(double, double);

extern double frexp(double, int *);
extern double ldexp(double, int);
extern double modf(double, double *);

#endif
