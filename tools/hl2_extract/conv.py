import sys,json,os; sys.path.insert(0,'.')
from vpk import *; from vtf import decode
from PIL import Image
BS=chr(92)
res=json.load(open('vmts.json'))
vs={b:VPK(b) for b in ('hl2_textures','content_hl2','content_cstrike','hl2_misc')}
out=BS.join(['C:','Users','dark','Documents','貝克潤ps-2','assets','models','hl2_local']); os.makedirs(out,exist_ok=True)
ok=[];bad=[]
for n,(vm,bt) in res.items():
    if not bt: bad.append((n,'nobase')); continue
    key='materials/'+bt.replace(BS,'/').lower()+'.vtf'
    done=False
    for b,v in vs.items():
        if key in v.files:
            try:
                im=decode(v.read(key)); w,h=im.size; s=min(1.0,128/max(w,h))
                if s<1: im=im.resize((max(1,int(w*s)),max(1,int(h*s))),Image.LANCZOS)
                im.convert('RGB').save(os.path.join(out,n.upper()+'.png')); ok.append(n); done=True
            except Exception as e: bad.append((n,repr(e)))
            break
    if not done and not any(x[0]==n for x in bad): bad.append((n,'novtf '+key))
print(len(ok),'ok'); print(bad)
