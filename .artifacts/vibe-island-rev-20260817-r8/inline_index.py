import re, json
lines=open('vi.asm',errors='replace').read().split('\n')
movz=re.compile(r'^([0-9a-f]+)\tmov\tx(\d+), #0x([0-9a-f]+)$'); movk=re.compile(r'^([0-9a-f]+)\tmovk\tx(\d+), #0x([0-9a-f]+), lsl #(\d+)$')
regs={}; found=[]
for i,l in enumerate(lines):
    m=movz.match(l)
    if m:
        regs[m.group(2)]=(int(m.group(3),16), i); continue
    m=movk.match(l)
    if m and m.group(2) in regs:
        v,start=regs[m.group(2)]
        v|=int(m.group(3),16)<<int(m.group(4))
        regs[m.group(2)]=(v,start)
        b=v.to_bytes(8,'little').rstrip(b'\x00')
        try:
            t=b.decode('ascii')
            if len(t)>=4 and all(32<=ord(c)<127 for c in t): found.append((i,t))
        except: pass
json.dump(found, open('inline.json','w'))
print(len(found))
