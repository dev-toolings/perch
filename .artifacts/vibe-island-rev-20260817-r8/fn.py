import re, sys, json, subprocess, bisect, functools, struct
DATA=open('vi-arm64','rb').read()
def _segs():
    magic,cputype,cpusub,filetype,ncmds,sizeofcmds,flags,res=struct.unpack_from('<IiiIIIII',DATA,0)
    off=32; segs=[]
    for _ in range(ncmds):
        cmd,cmdsize=struct.unpack_from('<II',DATA,off)
        if cmd==0x19:
            vmaddr,vmsize,fileoff,filesize=struct.unpack_from('<QQQQ',DATA,off+24); segs.append((vmaddr,vmsize,fileoff))
        off+=cmdsize
    return segs
SEGS=_segs()
def rdd(va):
    for vmaddr,vmsize,fileoff in SEGS:
        if vmaddr<=va<vmaddr+vmsize:
            fo=fileoff+(va-vmaddr)
            try: return struct.unpack_from('<d',DATA,fo)[0]
            except: return None
    return None
def rdf(va):
    for vmaddr,vmsize,fileoff in SEGS:
        if vmaddr<=va<vmaddr+vmsize:
            fo=fileoff+(va-vmaddr)
            try: return struct.unpack_from('<f',DATA,fo)[0]
            except: return None

lines=open('vi.asm',errors='replace').read().split('\n')
addr_re=re.compile(r'^([0-9a-f]{16})\t')
addrs=[]; addr_line={}
for i,l in enumerate(lines):
    m=addr_re.match(l)
    if m:
        a=int(m.group(1),16); addrs.append(a); addr_line[a]=i
starts=[]
for l in open('/Users/kevin/Documents/lab/sandbox/perch/.artifacts/vibe-island-rev-20260817-r8/vibe_island_extract/2026_08_17/symbols/function_starts.txt'):
    m=re.match(r'^([0-9a-f]{16})', l)
    if m: starts.append(int(m.group(1),16))
starts=sorted(set(starts)); startset=set(starts); MAXD=int(__import__('os').environ.get('MAXD','3')); RANGE=__import__('os').environ.get('RANGE'); LO,HI=(int(x,16) for x in RANGE.split('-')) if RANGE else (0,0xffffffffff)
@functools.lru_cache(maxsize=None)
def demangle(s):
    try:
        out=subprocess.run(['xcrun','swift-demangle','-compact'],input=s,capture_output=True,text=True).stdout.strip()
        return out or s
    except: return s
def fn_bounds(a):
    i=bisect.bisect_right(starts,a)-1
    s=starts[i]; e=starts[i+1] if i+1<len(starts) else s+0x2000
    return s,e
def listing(a, depth=0, seen=None, maxlines=4000):
    seen=seen or set()
    s,e=fn_bounds(a)
    if s in seen: return []
    seen.add(s)
    out=[f"--- func {hex(s)}..{hex(e)} (depth {depth})"]
    pend=[]; sub=[]; adrp={}; xreg={}
    i=addr_line[s]
    while i<len(lines):
        l=lines[i]; m=addr_re.match(l)
        if not m: i+=1; continue
        a=int(m.group(1),16)
        if a>=e: break
        body=l.split('\t',1)[1]
        mz=re.match(r'mov\tx(\d+), #(-?0x[0-9a-f]+)$', body)
        if mz:
            xreg[mz.group(1)]=int(mz.group(2),16)&0xffffffffffffffff
            if re.match(r'mov\tx[0-7], #0x[34][0-9a-f]{15}$', body):
                pend.append(f"x{mz.group(1)}=dbl {struct.unpack('<d',struct.pack('<Q',xreg[mz.group(1)]))[0]!r}")
        mk=re.match(r'movk\tx(\d+), #0x([0-9a-f]+), lsl #(\d+)$', body)
        if mk and mk.group(1) in xreg:
            sh=int(mk.group(3)); xreg[mk.group(1)]=(xreg[mk.group(1)]&~(0xffff<<sh))|(int(mk.group(2),16)<<sh)
        mw=re.match(r'(?!mov\t|movk\t)\w+\tx(\d+),', body)
        if mw and mw.group(1) in xreg: del xreg[mw.group(1)]
        mo=re.match(r'orr\tx(\d+), xzr, #(0x[0-9a-f]+)$', body)
        if mo: xreg[mo.group(1)]=int(mo.group(2),16)
        mf=re.match(r'fmov\td(\d+), x(\d+)$', body)
        if mf and mf.group(2) in xreg:
            pend.append(f"d{mf.group(1)}={struct.unpack('<d',struct.pack('<Q',xreg[mf.group(2)]))[0]!r}")
        ma=re.match(r'adrp\tx(\d+), \d+ ; (0x[0-9a-f]+)', body)
        if ma: adrp[ma.group(1)]=int(ma.group(2),16)
        ml=re.match(r'ldr\t([ds])(\d+), \[x(\d+), #(0x[0-9a-f]+)\]', body)
        if ml and ml.group(3) in adrp:
            va=adrp[ml.group(3)]+int(ml.group(4),16)
            v=rdd(va) if ml.group(1)=='d' else rdf(va)
            pend.append(f"{ml.group(1)}{ml.group(2)}=const {v!r}")
        if re.match(r'fmov(\.2d)?\t[dv]\d+, #', body) or re.match(r'mov\tw\d+, #0x[0-9a-f]{1,3}$', body) or 'literal pool for:' in body:
            pend.append(body.replace('\t',' '))
        mm=re.search(r'stub for: (\S+)', body)
        if mm:
            name=demangle(mm.group(1))
            if any(k in name for k in ['SwiftUI','CoreGraphics','Foundation.NSLocalizedString','VibeIsland']) and 'swift_' not in name:
                out.append(f"  {m.group(1)[-6:]}  [{' | '.join(pend[-8:])}]  -> {name[:110]}")
            pend=[]
        mm2=re.match(r'(b|bl)\t(0x1[0-9a-f]{8})$', body)
        if mm2:
            t=int(mm2.group(2),16)
            if t in startset and t!=s and 'stub' not in body: sub.append((t, mm2.group(1)))
        madd=re.match(r'add\tx(\d+), x(\d+), #(0x[0-9a-f]+)$', body)
        if madd and madd.group(2) in adrp:
            t=adrp[madd.group(2)]+int(madd.group(3),16)
            if t in startset and t!=s: sub.append((t,'adrp+add'))
        mm3=re.search(r'\b(0x1[0-9a-f]{8})\b', body)
        if mm3 and body.startswith('adr'):
            t=int(mm3.group(1),16)
            if t in startset and t!=s: sub.append((t,'adr'))
        i+=1
    if depth<MAXD:
        for t,k in sub[:40]:
            out+=listing(t, depth+1, seen)
    return out
if __name__=='__main__':
    for a in sys.argv[1:]:
        for l in listing(int(a,16)): print(l)
