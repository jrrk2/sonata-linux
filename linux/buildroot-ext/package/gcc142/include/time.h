/* time.h - C89-compatible for GCC 1.42 (shadows musl version) */

#ifndef _GCC142_TIME_H
#define _GCC142_TIME_H

#include <stddef.h>

typedef long time_t;
typedef long clock_t;

#define CLOCKS_PER_SEC 1000000L

struct tm {
	int tm_sec;
	int tm_min;
	int tm_hour;
	int tm_mday;
	int tm_mon;
	int tm_year;
	int tm_wday;
	int tm_yday;
	int tm_isdst;
};

extern time_t time(time_t *);
extern double difftime(time_t, time_t);
extern time_t mktime(struct tm *);

extern struct tm *localtime(const time_t *);
extern struct tm *gmtime(const time_t *);
extern char *asctime(const struct tm *);
extern char *ctime(const time_t *);
extern size_t strftime(char *, size_t, const char *, const struct tm *);

extern clock_t clock(void);

#endif
