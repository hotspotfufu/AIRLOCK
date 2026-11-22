import json,struct,sys,io
import numpy as np
from PIL import Image
def load(f):
    b=open(f,'rb').read()
    n=struct.unpack('<I',b[12:16])[0]; j=json.loads(b[20:20+n])
    off=20+n; bin_=b''
    if off<len(b):
        m=struct.unpack('<I',b[off:off+4])[0]; bin_=b[off+8:off+8+m]
    return j,bin_
def trs(n):
    if 'matrix' in n: return np.array(n['matrix'],float).reshape(4,4).T
    M=np.eye(4)
    t=n.get('translation',[0,0,0]); r=n.get('rotation',[0,0,0,1]); s=n.get('scale',[1,1,1])
    x,y,z,w=r
    R=np.array([[1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w)],[2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w)],[2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y)]])
    M[:3,:3]=R@np.diag(s); M[:3,3]=t
    return M
def main(f,depth=2):
    j,bin_=load(f)
    print('==',f,'bin',len(bin_)//1024,'KB','ext',j.get('extensionsUsed'))
    img_bytes=0
    for i,im in enumerate(j.get('images',[])):
        if 'bufferView' in im:
            bv=j['bufferViews'][im['bufferView']]; d=bin_[bv.get('byteOffset',0):bv.get('byteOffset',0)+bv['byteLength']]
            img_bytes+=len(d)
            try: sz=Image.open(io.BytesIO(d)).size
            except Exception as e: sz=str(e)[:30]
            print('  img',i,im.get('name'),im.get('mimeType'),len(d)//1024,'KB',sz)
        else: print('  img',i,im.get('uri','')[:60])
    print('  images total',img_bytes//1024,'KB, geometry',(len(bin_)-img_bytes)//1024,'KB')
    for i,m in enumerate(j.get('materials',[])):
        p=m.get('pbrMetallicRoughness',{})
        print('  mat',i,m.get('name'),'base',p.get('baseColorFactor'),'tex',p.get('baseColorTexture',{}).get('index'),'mr',p.get('metallicRoughnessTexture',{}).get('index'),'n',m.get('normalTexture',{}).get('index'),'em',m.get('emissiveTexture',{}).get('index'),m.get('emissiveFactor'),m.get('alphaMode'),list(m.get('extensions',{}).keys()))
    acc=j.get('accessors',[])
    tris=0
    def meshbox(mi):
        nonlocal tris
        lo=np.full(3,1e18);hi=-lo
        for p in j['meshes'][mi]['primitives']:
            a=acc[p['attributes']['POSITION']]
            lo=np.minimum(lo,a['min']);hi=np.maximum(hi,a['max'])
            if 'indices' in p: tris+=acc[p['indices']]['count']//3
            else: tris+=a['count']//3
        return lo,hi
    glo=np.full(3,1e18);ghi=-glo
    def walk(ni,M,d):
        nonlocal glo,ghi
        n=j['nodes'][ni]; W=M@trs(n)
        lo=np.full(3,1e18);hi=-lo
        if 'mesh' in n:
            a,b=meshbox(n['mesh'])
            c=np.array([[x,y,z,1] for x in (a[0],b[0]) for y in (a[1],b[1]) for z in (a[2],b[2])])
            w=(W@c.T).T[:,:3]; lo=w.min(0);hi=w.max(0)
        for c in n.get('children',[]):
            a,b=walk(c,W,d+1); lo=np.minimum(lo,a);hi=np.maximum(hi,b)
        if d<=depth and hi[0]>-1e17:
            print('  '+'  '*d+f"{n.get('name')} mesh={n.get('mesh')} min={np.round(lo,2).tolist()} max={np.round(hi,2).tolist()} size={np.round(hi-lo,2).tolist()}")
        glo=np.minimum(glo,lo);ghi=np.maximum(ghi,hi)
        return lo,hi
    for r in j['scenes'][j.get('scene',0)]['nodes']: walk(r,np.eye(4),0)
    print('  TOTAL min',np.round(glo,2).tolist(),'max',np.round(ghi,2).tolist(),'size',np.round(ghi-glo,2).tolist(),'tris',tris)
if __name__=='__main__': main(sys.argv[1],int(sys.argv[2]) if len(sys.argv)>2 else 2)
