/* Build-time glibc ABI probe. This program is not linked into asmwc. */
#define _GNU_SOURCE
#include <errno.h>
#include <features.h>
#include <fts.h>
#include <stddef.h>
#include <stdio.h>
#include <sys/stat.h>
#include <unistd.h>

#ifndef __GLIBC__
#error "The Linux assembly ports currently require glibc."
#endif

#define EMIT(name, value) printf("#define ABI_" #name " %zu\n", (size_t)(value))

int main(void) {
    puts("/* Generated from the target's libc headers; do not edit. */");
    EMIT(STAT_SIZE, sizeof(struct stat));
    EMIT(STAT_ST_SIZE, offsetof(struct stat, st_size));
    EMIT(STAT_ST_MODE, offsetof(struct stat, st_mode));
    EMIT(FTS_PATH, offsetof(FTSENT, fts_path));
    EMIT(FTS_PATHLEN, offsetof(FTSENT, fts_pathlen));
    EMIT(FTS_INFO, offsetof(FTSENT, fts_info));
    EMIT(FTS_NAME, offsetof(FTSENT, fts_name));
    EMIT(FTS_LEVEL, offsetof(FTSENT, fts_level));
    EMIT(FTS_LEVEL_SIZE, sizeof(((FTSENT *)0)->fts_level));
    EMIT(FTS_STATP, offsetof(FTSENT, fts_statp));
    EMIT(FTS_PHYSICAL, FTS_PHYSICAL);
    EMIT(FTS_NOCHDIR, FTS_NOCHDIR);
    EMIT(FTS_COMFOLLOW, FTS_COMFOLLOW);
    EMIT(FTS_D, FTS_D);
    EMIT(FTS_DP, FTS_DP);
    EMIT(FTS_ERR, FTS_ERR);
    EMIT(FTS_NS, FTS_NS);
    EMIT(FTS_DNR, FTS_DNR);
    EMIT(FTS_DC, FTS_DC);
    EMIT(FTS_SL, FTS_SL);
    EMIT(FTS_SLNONE, FTS_SLNONE);
    EMIT(SC_NPROCESSORS_ONLN, _SC_NPROCESSORS_ONLN);
    EMIT(EPIPE, EPIPE);
    EMIT(ENOSPC, ENOSPC);
    EMIT(EINVAL, EINVAL);
    EMIT(EACCES, EACCES);
    EMIT(EISDIR, EISDIR);
    EMIT(EFBIG, EFBIG);
    EMIT(EAGAIN, EAGAIN);
    EMIT(EINTR, EINTR);
    EMIT(ENOMEM, ENOMEM);
    return 0;
}
