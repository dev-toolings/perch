import struct, sys, json
data=open('vi-arm64','rb').read()
# parse mach-o 64 load commands
magic,cputype,cpusub,filetype,ncmds,sizeofcmds,flags,res=struct.unpack_from('<IiiIIIII',data,0)
assert magic==0xfeedfacf
off=32; secs={}; segs=[]
for _ in range(ncmds):
    cmd,cmdsize=struct.unpack_from('<II',data,off)
    if cmd==0x19: # LC_SEGMENT_64
        segname=data[off+8:off+24].rstrip(b'\0').decode()
        vmaddr,vmsize,fileoff,filesize=struct.unpack_from('<QQQQ',data,off+24)
        nsects=struct.unpack_from('<I',data,off+64)[0]
        segs.append((segname,vmaddr,vmsize,fileoff,filesize))
        so=off+72
        for i in range(nsects):
            sn=data[so:so+16].rstrip(b'\0').decode(); sg=data[so+16:so+32].rstrip(b'\0').decode()
            addr,size,soff=struct.unpack_from('<QQI',data,so+32)
            secs[(sg,sn)]=(addr,size,soff)
            so+=80
    off+=cmdsize
def va2fo(va):
    for name,vmaddr,vmsize,fileoff,filesize in segs:
        if vmaddr<=va<vmaddr+vmsize: return fileoff+(va-vmaddr)
    return None
def rd32(va): return struct.unpack_from('<i',data,va2fo(va))[0]
def rdu32(va): return struct.unpack_from('<I',data,va2fo(va))[0]
def rd64(va): return struct.unpack_from('<Q',data,va2fo(va))[0]
def cstr(va):
    fo=va2fo(va); e=data.index(b'\0',fo); return data[fo:e].decode('utf-8','replace')
def rel(va): return va+rd32(va)
def relind(va):
    v=rd32(va)
    if v&1: return ('ind', va+(v&~1))
    return ('dir', va+v)
def fixup(v):
    # DYLD_CHAINED_PTR_64 rebase decode
    bind=(v>>63)&1
    if bind: return ('bind', v&0xffffff)
    target=v&0xfffffffff; high8=(v>>36)&0xff
    return ('rebase', target|(high8<<56))
paddr,psize,_=secs[('__TEXT','__swift5_proto')]
print('proto section', hex(paddr), psize, 'entries', psize//4)
res=[]
for i in range(psize//4):
    e=paddr+4*i
    cd=rel(e)
    prot=relind(cd)
    flags=rdu32(cd+12)
    kind=(flags>>3)&3
    tref=None
    if kind==0: tref=rel(cd+4)
    elif kind==1:
        k,tva=('ind',rel(cd+4)); 
        try: tref=fixup(rd64(tva))[1]
        except: tref=None
    name=None
    if tref:
        try:
            # nominal type descriptor: flags(4) parent(4) name(4)...
            name=cstr(rel(tref+8))
        except Exception as ex: name=None
    wt=rel(cd+8) if rd32(cd+8) else None
    res.append(dict(cd=hex(cd), kind=kind, name=name, tref=hex(tref) if tref else None, wt=hex(wt) if wt else None, prot=prot[0]+':'+hex(prot[1])))
json.dump(res,open('conformances.json','w'),indent=0)
names_all=[r for r in res if r['name']]
names=[r for r in res if r['name'] in ('SessionCardView','TaskListView','TaskRowView','TagPill','NotchContentView','PixelStatusIconCompact','PixelStatusIcon','PixelSessionIcon','CompletionCardView','SessionsListView','StateIndicator','JumpToTerminalPill','NotchShape','CompactingProgressLabel','ChildAgentsSection','ChildAgentRow','ShowAllSessionsButton','FreeModeCallToActionRow','LockedSessionsSummaryRow','StatusWarningCardView','BypassActivePill','SessionCardTitleParts','CodexHookTrustBannerView','ArchiveButton','CompletionUnreadDot')]
for r in names:
    line=r.copy()
    if r['wt']:
        wt=int(r['wt'],16)
        words=[fixup(rd64(wt+8*k)) for k in range(4)]
        line['wt_words']=[ (w[0],hex(w[1])) for w in words]
    print(line)

print("=== resilient witnesses")
out={}
for r in names_all:
    cd=int(r['cd'],16); flags=rdu32(cd+12)
    off=cd+16
    if flags&(1<<6): off+=4
    ncond=(flags>>8)&0xff; off+=12*ncond
    npack=(flags>>24)&0xf
    if npack: off+=4+4*npack  # header + descriptors (approx)
    wits=[]
    if flags&(1<<16):
        n=rdu32(off); off+=4
        for k in range(n):
            req=relind(off); imp=rd32(off+4); wva=off+4+imp if imp else None
            wits.append((req, hex(wva) if wva else None)); off+=8
    if len(wits)==6 and wits[2][1]=='0x100721dc0': out.setdefault(r['name'],[]).append(wits[5][1])
json.dump(out,open('bodygetters.json','w'),indent=1); print(len(out),'View bodies')
