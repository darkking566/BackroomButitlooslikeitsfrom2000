import struct,os,re,sys
ROOT=r'D:\SteamLibrary\steamapps\common\GarrysMod\sourceengine'
class VPK:
    def __init__(s,base):
        s.base=base; s.dir=os.path.join(ROOT,base+'_dir.vpk'); s.files={}
        f=open(s.dir,'rb'); sig,ver=struct.unpack('<II',f.read(8))
        assert sig==0x55aa1234
        if ver==2:
            tree,fds,a,b,c=struct.unpack('<5I',f.read(20)); hdr=28
        else:
            tree,=struct.unpack('<I',f.read(4)); hdr=12
        data=f.read(tree); s.dataoff=hdr+tree
        p=0
        def cs():
            nonlocal p
            e=data.index(b'\0',p); r=data[p:e].decode('utf8','replace'); p=e+1; return r
        while True:
            ext=cs()
            if not ext: break
            while True:
                path=cs()
                if not path: break
                while True:
                    name=cs()
                    if not name: break
                    crc,pre,ai,off,ln=struct.unpack('<IHHII',data[p:p+16]); p+=18
                    pd=data[p:p+pre]; p+=pre
                    full=(path+'/'+name+'.'+ext).lower() if path!=' ' else (name+'.'+ext).lower()
                    s.files[full]=(pre,pd,ai,off,ln)
    def read(s,full):
        pre,pd,ai,off,ln=s.files[full]
        if ai==0x7fff:
            with open(s.dir,'rb') as f: f.seek(s.dataoff+off); return pd+f.read(ln)
        with open(os.path.join(ROOT,'%s_%03d.vpk'%(s.base,ai)),'rb') as f: f.seek(off); return pd+f.read(ln)
