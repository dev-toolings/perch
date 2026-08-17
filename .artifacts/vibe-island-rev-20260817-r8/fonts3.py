import re, collections, json
lines=open('vi.asm',errors='replace').read().split('\n')
SYS='FontV6system4size6weight6design'; CUSTOM='FontV6custom_4size'
W={'6mediumAEvgZ':'medium','8semiboldAEvgZ':'semibold','4boldAEvgZ':'bold','7regularAEvgZ':'regular','5lightAEvgZ':'light','5heavyAEvgZ':'heavy'}
fmov=re.compile(r'fmov\s+d0, #([0-9.]+)')
movz=re.compile(r'\tmov\tx(\d+), #0x([0-9a-f]+)$'); movk=re.compile(r'\tmovk\tx(\d+), #0x([0-9a-f]+), lsl #(\d+)$')
def decode_inline(seg):
    regs={}
    outs=[]
    for s in seg:
        m=movz.search(s)
        if m: regs[m.group(1)]=int(m.group(2),16); continue
        m=movk.search(s)
        if m and m.group(1) in regs:
            regs[m.group(1)] |= int(m.group(2),16)<<int(m.group(3))
    for r,v in regs.items():
        b=v.to_bytes(8,'little').rstrip(b'\x00')
        try:
            t=b.decode('ascii')
            if len(t)>=3 and all(32<=ord(c)<127 for c in t): outs.append(t)
        except: pass
    return outs
out=[]
for i,l in enumerate(lines):
    if 'symbol stub for' not in l or (SYS not in l and CUSTOM not in l): continue
    custom=CUSTOM in l
    size=None; weight=None; design=None; arith=[]
    for j in range(i-1,max(0,i-80),-1):
        m=lines[j]
        if size is None:
            mm=fmov.search(m)
            if mm: size=float(mm.group(1))
            elif re.search(r'\t(ldr|ldur|fadd|fsub|fmul|fdiv|fcvt|scvtf|ucvtf|fmax|fmin|fmov)\td0', m):
                size='var'
                arith=[x.split('\t',1)[1] for x in lines[max(0,j-6):j+1] if re.search(r'\tf(add|sub|mul|div|mov|max|min)\t|\tfmov\td\d, #',x)]
        if weight is None:
            for k,v in W.items():
                if k in m: weight=v
        if design is None:
            mm=re.search(r'FontV6DesignO\d+([a-z]+)yA2EmFWC', m)
            if mm: design=mm.group(1)
            elif 'FontV6DesignOMa' in m:
                seg='\n'.join(lines[j:i])
                if re.search(r'mov\tw1, #0x1\n[0-9a-f]+\tmov\tw2, #0x1', seg): design='nil'
                else: design='some?'
        if 'FontV6system4size' in m and j!=i: break   # previous font call: stop
    seg2='\n'.join(lines[max(0,i-6):i])
    if weight is None and re.search(r'mov\tx0, #0x0\n[^\n]*mov\tw1, #0x1', seg2): weight='nil'
    strs=[]; inl=[]
    for j in range(i-1,max(0,i-500),-1):
        if 'literal pool for:' in lines[j]:
            strs.append(lines[j].split('literal pool for:')[1].strip()[:60])
        if len(strs)>=4: break
    inl=decode_inline(lines[max(0,i-500):i])
    out.append(dict(addr=l.split('\t')[0], kind='custom' if custom else 'system', size=size, weight=weight or '?', design=design or 'nil', arith=arith, ctx=strs[::-1], inline=inl[-8:]))
json.dump(out,open('fonts.json','w'),indent=0)
hist=collections.Counter((o['kind'],str(o['size']),o['weight'],o['design']) for o in out)
for k,v in sorted(hist.items(), key=lambda kv:-kv[1])[:40]: print(v,k)
