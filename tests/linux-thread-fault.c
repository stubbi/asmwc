/* Test-only preload: all worker creation fails, so the caller must do the work.
   A failed pthread_create does not produce a thread that may be joined. */
#include <errno.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

static unsigned create_attempts;

int pthread_create(pthread_t *thread, const pthread_attr_t *attributes,
                   void *(*start)(void *), void *argument) {
    (void)thread;
    (void)attributes;
    (void)start;
    (void)argument;
    ++create_attempts;
    return EAGAIN;
}

int pthread_join(pthread_t thread, void **result) {
    (void)thread;
    (void)result;
    _exit(97); /* No successful creation means every attempted join is invalid. */
}

__attribute__((destructor)) static void report_attempts(void) {
    const char *path = getenv("ASMWC_TEST_THREAD_TRACE");
    if (!path) return;
    FILE *output = fopen(path, "w");
    if (!output) return;
    fprintf(output, "%u\n", create_attempts);
    fclose(output);
}
