import sys, re
sys.argv=[sys.argv[0]]+sys.argv[1:]
import importlib.util
spec=importlib.util.spec_from_file_location('fn','/tmp/parity/fn.py'); fn=importlib.util.module_from_spec(spec)
import builtins
_argv=sys.argv; sys.argv=[_argv[0]]
spec.loader.exec_module(fn)
sys.argv=_argv
lo=int(sys.argv[1],16); hi=int(sys.argv[2],16)
import bisect
i=bisect.bisect_left(fn.starts, lo)
fn.MAXD=0
while i<len(fn.starts) and fn.starts[i]<hi:
    for l in fn.listing(fn.starts[i], 0, set()): print(l)
    i+=1
