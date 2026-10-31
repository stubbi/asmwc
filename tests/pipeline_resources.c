// Setup failure must leave the fd unread so main can use its normal reader.
#include <assert.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <sys/types.h>
extern int ripwc_pipeline_scan(int, unsigned, uint64_t *);
static int fail_queue, reads, releases;
void *dispatch_group_create(void) { return fail_queue ? (void *)1 : NULL; }
void *dispatch_queue_create(const char *name, void *attr) { (void)name;(void)attr;return NULL; }
long dispatch_group_wait(void *group, uint64_t deadline) { (void)group;(void)deadline;return 0; }
void dispatch_group_async_f(void *g, void *q, void *c, void (*f)(void *)) {(void)g;(void)q;(void)c;(void)f;assert(0);}
void dispatch_release(void *object) {(void)object;++releases;}
ssize_t read(int fd, void *data, size_t count) {(void)fd;(void)data;(void)count;++reads;return 0;}
int main(void) {
    for (fail_queue=0;fail_queue<2;++fail_queue) {
        uint64_t state[8]={1,2,3,4,5,6,7,8};
        reads=0;releases=0;
        int result=ripwc_pipeline_scan(-1,13,state);
        if(result!=1 || reads || releases!=fail_queue) {
            fprintf(stderr,"FAIL setup=%s result=%d reads=%d releases=%d\n",fail_queue?"queue":"group",result,reads,releases);return 1;
        }
        for(unsigned i=0;i<8;++i) assert(state[i]==i+1);
    }
    puts("PASS pipeline group/queue setup failures preserve state and allow buffered fallback");
}
