/* test_v08.c - v0.8 checks against real Orovela 1.4 data (Linux). */
#include "hfe.h"
#include "slots.h"
#include "wavio.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
extern const unsigned char BASE_DISK[]; extern const unsigned int BASE_DISK_LEN;
static int fails=0;
#define CHECK(c,n) do{ if(c) printf("PASS  %s\n",n); else {printf("FAIL  %s\n",n); fails++;} }while(0)
static uint8_t *slurp(const char *p,size_t *n){FILE*f=fopen(p,"rb");if(!f){*n=0;return 0;}fseek(f,0,2);long l=ftell(f);fseek(f,0,0);uint8_t*b=malloc(l);if(fread(b,1,l,f)!=(size_t)l){}fclose(f);*n=l;return b;}
static double bpc(const uint8_t *s,int n){ /* zero-crossing period estimate, rising crossings */
    double first=-1,last=-1; int cnt=0;
    for(int i=1;i<n;i++){ double a=s[i-1]-128.0,b=s[i]-128.0;
        if(a<0&&b>=0){ double t=i-1+(-a)/(b-a); if(first<0)first=t; else cnt++; last=t; } }
    return cnt? (last-first)/cnt : 0; }
int main(void){
    HFE h; SlotInfo si; char nm[128];
    /* 1. OS-saved v5 slots (Orovela 1.4-era builds) */
    CHECK(hfe_load(&h,"ret182.hfe")==0,"load ret182");
    slot_info(&h,0,&si);
    CHECK(si.kind==SLOT_V3 && si.version==5 && si.meta==220,"OS v5 slot parses (version 5, meta 220)");
    CHECK(si.rate==4 && si.rate_hz==15504,"OS rate-4 slot -> rate 4 / 15504 Hz");
    slot_info(&h,4,&si);
    CHECK(si.rate==3 && si.rate_hz==10256 && si.loop_on,"OS rate-3 slot -> 10256 Hz, loop on (as saved)");
    uint8_t os_hdr[512];
    CHECK(slot_export_wav(&h,4,"out_r3.wav")==0,"export WAV rate 3");
    CHECK(slot_export_oro(&h,0,"out.oro")==0,"export .oro of a v5 slot");
    hfe_free(&h);
    /* reference header from a build-180 save (PARMTAB identical to Orovela 1.4) */
    CHECK(hfe_load(&h,"ret180.hfe")==0,"load ret180"); slot_info(&h,0,&si); memcpy(os_hdr,si.header,512);
    CHECK(si.rate==4 && si.version==5,"build-180 rate-4 slot parses"); hfe_free(&h);
    /* 2. WAV import auto rate picks */
    const char *f[5]={"s15.wav","s30.wav","s50.wav","s90.wav","s120.wav"}; int want[5]={4,3,2,1,1};
    WavImport *wi=malloc(sizeof *wi); size_t n; uint8_t *w;
    for(int i=0;i<5;i++){ w=slurp(f[i],&n); int rc=wav_import_build(w,n,wi); free(w);
        snprintf(nm,sizeof nm,"auto rate %s -> %d (got %d%s)",f[i],want[i],wi->rate,wi->truncated?", truncated":"");
        CHECK(rc==0&&wi->rate==want[i],nm); }
    /* 3. rate-4 import: header layout identical to what the OS saves */
    w=slurp("s15.wav",&n); wav_import_build(w,n,wi); free(w);
    int same=1; for(int i=0;i<54;i++){ const uint8_t*a=wi->hdr+4+i*4,*b=os_hdr+4+i*4; if(a[0]!=b[0]||a[2]!=b[2]||a[3]!=b[3]) same=0; }
    CHECK(same,"import PARMTAB spec/min/max sequence == OS-saved v5 header (54 entries)");
    CHECK(wi->hdr[2]==5 && wi->hdr[221]==1 && wi->hdr[220]==3,"import header v5, SMPSHFT 3, SMPPRE 1 at [221]");
    CHECK(hdr_param_by_spec(wi->hdr,1)==4 && hdr_param_by_spec(wi->hdr,76)==0 && hdr_param_by_spec(wi->hdr,77)==0,"param 1 = 4, 76 = 0, 77 = 0");
    double b=bpc(wi->sample,wi->out_n-200), exp=rate_hz_exact(4)/261.63;
    snprintf(nm,sizeof nm,"rate-4 resample: %.3f bytes/cycle (expect %.3f)",b,exp);
    CHECK(fabs(b/exp-1)<0.0005,nm);
    CHECK(wi->sendpos>0 && !wi->loop_on,"rate-4 one-shot gets end marker");
    /* 4. write into the embedded base disk (Orovela 1.5 since v1.0), re-read, parse */
    CHECK(hfe_from_mem(&h,BASE_DISK,BASE_DISK_LEN)==0,"embedded base loads");
    CHECK(disk_validate_orovela(&h)==0,"embedded base validates as Orovela");
    slot_info(&h,0,&si); CHECK(si.kind==SLOT_EMPTY,"embedded base slots empty");
    CHECK(slot_write_sample(&h,3,wi->sample)==0 && slot_write_header(&h,3,wi->hdr)==0,"write import to slot 3");
    w=slurp("loop.wav",&n); wav_import_build_rate(w,n,3,wi); free(w);
    CHECK(wi->rate==3 && wi->loop_on,"forced rate 3 loop import");
    CHECK(slot_write_sample(&h,5,wi->sample)==0 && slot_write_header(&h,5,wi->hdr)==0,"write loop import to slot 5");
    CHECK(slot_import_oro(&h,7,"out.oro")==0,"import v5 .oro to slot 7");
    hfe_save(&h,"out_disk.hfe"); hfe_free(&h);
    CHECK(hfe_load(&h,"out_disk.hfe")==0,"reload written disk");
    slot_info(&h,3,&si); CHECK(si.rate==4&&si.version==5&&!si.loop_on,"slot 3 reads back rate 4 v5");
    slot_info(&h,5,&si); CHECK(si.rate==3&&si.loop_on,"slot 5 reads back rate 3 looped");
    CHECK(slot_export_wav(&h,5,"out_loop.wav")==0,"export looped WAV (smpl)");
    hfe_free(&h);
    printf("%s (%d failures)\n",fails?"FAILED":"ALL PASS",fails);
    return fails!=0;
}
