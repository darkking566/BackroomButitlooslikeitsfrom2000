import struct,io
from PIL import Image
BPP={0:4,1:4,2:3,3:3,12:4,16:4,5:1,8:2}
def size(fmt,w,h):
    if fmt in (13,): return max(1,(w+3)//4)*max(1,(h+3)//4)*8
    if fmt in (14,15): return max(1,(w+3)//4)*max(1,(h+3)//4)*16
    return w*h*BPP[fmt]
def decode(b):
    assert b[:4]==b'VTF\0'
    ver=struct.unpack('<II',b[4:12]); hs=struct.unpack('<I',b[12:16])[0]
    w,h,flags,frames,first=struct.unpack('<HHIHH',b[16:28])
    fmt,=struct.unpack('<i',b[52:56]); mips=b[56]; lfmt,=struct.unpack('<i',b[57:61]); lw,lh=b[61],b[62]
    off=hs+(size(lfmt,lw,lh) if lfmt>=0 and lw and lh else 0)
    for i in range(mips-1,0,-1):
        off+=frames*size(fmt,max(1,w>>i),max(1,h>>i))
    n=size(fmt,w,h); d=b[off:off+n]
    if fmt in (13,14,15):
        fcc={13:b'DXT1',14:b'DXT3',15:b'DXT5'}[fmt]
        hdr=b'DDS '+struct.pack('<7I',124,0x81007,h,w,n,0,0)+b'\0'*44+struct.pack('<2I4s5I',32,4,fcc,0,0,0,0,0)+struct.pack('<5I',0x1000,0,0,0,0)
        return Image.open(io.BytesIO(hdr+d)).convert('RGBA')
    mode={0:('RGBA','RGBA'),2:('RGB','RGB'),3:('RGB','BGR'),12:('RGBA','BGRA'),16:('RGBA','BGRX'),1:('RGBA','ABGR')}[fmt]
    return Image.frombytes(mode[0],(w,h),d,'raw',mode[1])
