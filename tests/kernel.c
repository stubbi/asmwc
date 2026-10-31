/* Behavioral kernel contract tests: catch transition, flag, carry, tail and overread bugs. */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

typedef struct { uint64_t bytes, chars, words, lines, max, in_word, current, reserved; } State;
extern void asmwc_count_buffer(const unsigned char *, size_t, unsigned, State *);
extern int kernel_abi_probe(const unsigned char *, size_t, unsigned, State *);
static uint64_t seed = 0xb4ff21371c883d21ULL;
static uint64_t rng(void) { seed ^= seed << 13; seed ^= seed >> 7; return seed ^= seed << 17; }
static void reference(const unsigned char *p, size_t n, unsigned f, State *s) {
    for (size_t i=0; i<n; ++i) {
        unsigned c=p[i];
        s->bytes += !!(f&1);
        s->chars += !!(f&2) && c!=0;
        s->lines += !!(f&4) && c==10;
        if(f&8) { unsigned w=(c==32 || c==9 || c==10 || c==13); s->words += s->in_word && w; s->in_word = !w; }
        if(f&16) { if(c==10) { if(s->current>s->max) s->max=s->current; s->current=0; } else ++s->current; }
    }
}
static void equal(State got, State want, const char *name, size_t n, unsigned f, size_t chunk) {
    if(memcmp(&got,&want,sizeof got)) {
        fprintf(stderr,"FAIL %s length=%zu flags=%u chunk=%zu\n",name,n,f,chunk);
        uint64_t *g=(void *)&got,*w=(void *)&want;
        for(unsigned i=0;i<8;++i) fprintf(stderr," field %u got=%llu want=%llu\n",i,(unsigned long long)g[i],(unsigned long long)w[i]);
        exit(1);
    }
}
static void check(const unsigned char *p,size_t n,unsigned f,size_t chunk,State start) {
    State want=start,got=start;
    reference(p,n,f,&want);
    if(!chunk) asmwc_count_buffer(p,n,f,&got);
    else for(size_t at=0;at<n;) { size_t m=n-at; if(m>chunk)m=chunk; asmwc_count_buffer(p+at,m,f,&got); at+=m; }
    equal(got,want,"differential",n,f,chunk);
}
static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC_RAW,&t); return t.tv_sec+t.tv_nsec*1e-9; }
int main(int argc,char **argv) {
    const unsigned char fixture[]={'a','b',' ','\0','\n','\t','c','d','\r','e'};
    State literal={10,9,3,1,4,1,5,0xdeadbeef};
    State actual={.reserved=0xdeadbeef};
    asmwc_count_buffer(fixture,sizeof fixture,31,&actual);
    equal(actual,literal,"literal NUL and pending word",10,31,0);
    State initial={71,83,97,101,23,1,37,0xa55aa55a};
    unsigned char data[8192+64];
    /* Each possible byte, ASCII whitespace, vector positions and cross-call state. */
    for(size_t i=0;i<sizeof data;++i) data[i]=(unsigned char)i;
    for(unsigned f=0;f<32;++f) for(size_t n=0;n<260;++n) for(size_t off=0;off<17;++off) check(data+off,n,f,0,initial);
    const size_t chunks[]={1,2,7,15,16,17,31,32,63,64,65,127,128,129,4096};
    for(unsigned trial=0;trial<300;++trial) {
        size_t n=rng()%8193;
        for(size_t i=0;i<n;++i) { uint64_t r=rng(); data[i]=(trial%3==0)?(unsigned char)r:(r%7==0?" \t\n\r"[(r>>8)%4]:(trial%3==1?'a':0)); }
        for(unsigned f=0;f<32;++f) check(data,n,f,chunks[trial%15],initial);
    }
    /* Dense runs catch counter-lane overflow and LF masks at every vector lane.
       Both starting word states matter when byte zero itself is whitespace. */
    for(unsigned byte=0;byte<256;++byte) {
        memset(data,byte,8192);
        for(unsigned f=0;f<32;++f) {
            check(data,8192,f,0,initial);
            State from_empty=initial; from_empty.in_word=0; from_empty.current=0;
            check(data,8192,f,127,from_empty);
        }
    }
    long page=sysconf(_SC_PAGESIZE);
    unsigned char *mem=mmap(0,page*3,PROT_NONE,MAP_PRIVATE|MAP_ANON,-1,0);
    if(mem==MAP_FAILED || mprotect(mem+page,page,PROT_READ|PROT_WRITE)) {perror("guard pages");return 2;}
    for(size_t i=0;i<(size_t)page;++i) mem[page+i]=(unsigned char)rng();
    for(unsigned f=0;f<32;++f) for(size_t n=0;n<260;++n) {check(mem+2*page-n,n,f,0,initial);check(mem+page,n,f,0,initial);}
    munmap(mem,page*3);
    const size_t abi_lengths[]={0,1,15,16,63,64,2048,4097};
    for(unsigned f=0;f<32;++f) for(unsigned j=0;j<sizeof abi_lengths/sizeof *abi_lengths;++j) {
        State state={0};
        if(kernel_abi_probe(data,abi_lengths[j],f,&state)) { fprintf(stderr,"FAIL ABI flags=%u length=%zu\n",f,abi_lengths[j]); return 1; }
    }
    puts("PASS literal, all 32 flag masks, unaligned vectors, randomized chunk carry, guard pages, and callee-saved ABI");
    if(argc>1 && !strcmp(argv[1],"bench")) {
        const size_t n=64*1024*1024; unsigned char *p=malloc(n); if(!p)return 2;
        for(size_t i=0;i<n;++i) p[i]=(i%79==78?'\n':(i%7==6?' ':'a'));
        const unsigned flags[]={13,4,8,2,31,16};
        for(size_t j=0;j<sizeof flags/sizeof *flags;++j) { State s={0}; double t=now(); for(unsigned k=0;k<32;++k)asmwc_count_buffer(p,n,flags[j],&s); t=now()-t; printf("flags=%u %.2f GB/s (%.3f s) checksum=%llu\n",flags[j],n*32.0/t/1e9,t,(unsigned long long)(s.bytes+s.chars+s.words+s.lines+s.max+s.current+s.in_word)); }
        free(p);
    }
    return 0;
}
