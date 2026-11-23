"""GLB optimizer: downscale textures, optional vertex-cluster decimation, mesh dedupe.
usage: glbopt.py in.glb out.glb --tex 1024 [--cell 0.02] [--dropuv] [--matjson file]"""
import json,struct,sys,io,hashlib,argparse
import numpy as np
from PIL import Image
from glbinfo import load
from glbmesh import acc as read_acc
from glbinfo import trs
UVQ=16
def pad4(b,ch=b'\0'):
    return b+ch*((4-len(b)%4)%4)
def opt_image(d,maxdim,q=82):
    im=Image.open(io.BytesIO(d)); im.load()
    has_alpha = im.mode in ('RGBA','LA','PA') and np.asarray(im.convert('RGBA'))[...,3].min()<250
    if max(im.size)>maxdim:
        s=maxdim/max(im.size); im=im.resize((max(1,round(im.size[0]*s)),max(1,round(im.size[1]*s))),Image.LANCZOS)
    o=io.BytesIO()
    if has_alpha:
        im.convert('RGBA').save(o,'PNG',optimize=True); return o.getvalue(),'image/png'
    im.convert('RGB').save(o,'JPEG',quality=q,optimize=True); return o.getvalue(),'image/jpeg'
def cluster(pos,nrm,uv,idx,cell):
    key=np.round(pos/cell).astype(np.int64)
    if uv is not None: key=np.concatenate([key,np.round(uv*UVQ).astype(np.int64)],axis=1)
    _,inv,cnt=np.unique(key,axis=0,return_inverse=True,return_counts=True)
    inv=inv.ravel(); n=len(cnt)
    def avg(a):
        o=np.zeros((n,a.shape[1])); np.add.at(o,inv,a); return o/cnt[:,None]
    p=avg(pos); nn=avg(nrm); l=np.linalg.norm(nn,axis=1,keepdims=True); l[l<1e-9]=1; nn=nn/l
    u=avg(uv) if uv is not None else None
    t=inv[idx]
    ok=(t[:,0]!=t[:,1])&(t[:,1]!=t[:,2])&(t[:,0]!=t[:,2]); t=t[ok]
    if len(t):
        s=np.sort(t,axis=1); _,first=np.unique(s,axis=0,return_index=True); t=t[np.sort(first)]
    used=np.unique(t); remap=np.full(n,-1); remap[used]=np.arange(len(used))
    return p[used],nn[used],(u[used] if u is not None else None),remap[t]
def main():
    ap=argparse.ArgumentParser(); ap.add_argument('inp'); ap.add_argument('out')
    ap.add_argument('--tex',type=int,default=1024); ap.add_argument('--cell',type=float,default=0)
    ap.add_argument('--dropuv',action='store_true'); ap.add_argument('--matjson'); ap.add_argument('--q',type=int,default=82); ap.add_argument('--keeprects'); ap.add_argument('--dropnodes',default=''); ap.add_argument('--cellmat',default=''); ap.add_argument('--cutboxes',default='')
    a=ap.parse_args()
    j,bin_=load(a.inp)
    views=[]  # new bufferViews data
    def bv_bytes(i):
        bv=j['bufferViews'][i]; o=bv.get('byteOffset',0); return bin_[o:o+bv['byteLength']]
    new_views=[]; new_bin=bytearray()
    def add_view(data,target=None,stride=None):
        while len(new_bin)%4: new_bin.append(0)
        v={'buffer':0,'byteOffset':len(new_bin),'byteLength':len(data)}
        if target: v['target']=target
        new_bin.extend(data); new_views.append(v); return len(new_views)-1
    new_acc=[]
    def add_acc(arr,typ,ct,target,minmax=False):
        arr=np.ascontiguousarray(arr)
        v=add_view(arr.tobytes(),target)
        d={'bufferView':v,'componentType':ct,'count':len(arr),'type':typ}
        if minmax: d['min']=arr.min(0).tolist(); d['max']=arr.max(0).tolist()
        new_acc.append(d); return len(new_acc)-1
    # meshes
    cache={}; tris_in=tris_out=0
    mats=j.get('materials',[])
    def mat_has_tex(mi):
        if mi is None: return False
        return 'Texture' in json.dumps(mats[mi])
    mesh_hash={}; mesh_remap={}; new_meshes=[]
    mscale={}; mworld={}
    drop=[d for d in a.dropnodes.split(',') if d]
    for n in j['nodes']:
        if 'mesh' in n and any(d in n.get('name','') for d in drop): del n['mesh']
    rects=[[float(v) for v in r.split(',')] for r in a.keeprects.split(';')] if a.keeprects else None
    cuts=[(c.split(':')[0],[float(v) for v in c.split(':')[1].split(',')]) for c in a.cutboxes.split(';') if c]
    mnode={}
    for n in j['nodes']:
        if 'mesh' in n: mnode.setdefault(n['mesh'],n.get('name',''))
    cellmat=dict((kv.split('=')[0],float(kv.split('=')[1])) for kv in a.cellmat.split(',') if kv)
    def walk(ni,M):
        n=j['nodes'][ni]; W=M@trs(n)
        if 'mesh' in n: mscale.setdefault(n['mesh'],float(np.cbrt(abs(np.linalg.det(W[:3,:3]))))); mworld.setdefault(n['mesh'],W)
        for c in n.get('children',[]): walk(c,W)
    for r in j['scenes'][j.get('scene',0)]['nodes']: walk(r,np.eye(4))
    for mi,m in enumerate(j.get('meshes',[])):
        prims=[]; h=hashlib.md5()
        for p in m['primitives']:
            at=p['attributes']
            pos=read_acc(j,bin_,at['POSITION']).astype(np.float64)
            nrm=read_acc(j,bin_,at['NORMAL']).astype(np.float64) if 'NORMAL' in at else np.zeros_like(pos)
            keepuv=('TEXCOORD_0' in at) and not (a.dropuv and not mat_has_tex(p.get('material')))
            uv=read_acc(j,bin_,at['TEXCOORD_0']).astype(np.float64) if keepuv else None
            if uv is not None and uv.dtype!=np.float64: uv=uv.astype(np.float64)
            idx=read_acc(j,bin_,p['indices']).reshape(-1,3).astype(np.int64) if 'indices' in p else np.arange(len(pos)).reshape(-1,3)
            tris_in+=len(idx)
            if rects is not None and mi in mworld:
                W=mworld[mi]; wp=(W[:3,:3]@pos.T).T+W[:3,3]; c=wp[idx].mean(1)
                keep=np.zeros(len(idx),bool)
                for x0,z0,x1,z1 in rects: keep|=(c[:,0]>=x0)&(c[:,0]<=x1)&(c[:,2]>=z0)&(c[:,2]<=z1)
                idx=idx[keep]
            if cuts and mi in mworld:
                W=mworld[mi]; wp=(W[:3,:3]@pos.T).T+W[:3,3]; c=wp[idx].mean(1)
                for pat,(bx0,by0,bz0,bx1,by1,bz1) in cuts:
                    if pat in mnode.get(mi,''):
                        ins=(c[:,0]>=bx0)&(c[:,0]<=bx1)&(c[:,1]>=by0)&(c[:,1]<=by1)&(c[:,2]>=bz0)&(c[:,2]<=bz1)
                        idx=idx[~ins]; c=c[~ins]
            mname=mats[p['material']].get('name') if 'material' in p else None
            cell=cellmat.get(mname,a.cell)
            if cell>0 and len(idx): pos,nrm,uv,idx=cluster(pos,nrm,uv,idx,cell/mscale.get(mi,1.0))
            tris_out+=len(idx)
            if len(idx)==0: continue
            h.update(np.round(pos,4).astype(np.float32).tobytes()); h.update(idx.astype(np.uint32).tobytes()); h.update(str(p.get('material')).encode())
            prims.append((pos,nrm,uv,idx,p))
        key=h.hexdigest()
        if key in mesh_hash: mesh_remap[mi]=mesh_hash[key]; continue
        np_=[]
        for pos,nrm,uv,idx,p in prims:
            at={'POSITION':add_acc(pos.astype(np.float32),'VEC3',5126,34962,True)}
            if 'NORMAL' in p['attributes']: at['NORMAL']=add_acc(nrm.astype(np.float32),'VEC3',5126,34962)
            if uv is not None: at['TEXCOORD_0']=add_acc(uv.astype(np.float32),'VEC2',5126,34962)
            flat=idx.ravel()
            if len(pos)<65535: ia=add_acc(flat.astype(np.uint16),'SCALAR',5123,34963)
            else: ia=add_acc(flat.astype(np.uint32),'SCALAR',5125,34963)
            q={'attributes':at,'indices':ia,'mode':4}
            if 'material' in p: q['material']=p['material']
            np_.append(q)
        if not np_: mesh_remap[mi]=None; continue
        nm={'primitives':np_}
        if 'name' in m: nm['name']=m['name']
        new_meshes.append(nm); mesh_hash[key]=len(new_meshes)-1; mesh_remap[mi]=len(new_meshes)-1
    for n in j['nodes']:
        if 'mesh' in n:
            r=mesh_remap[n['mesh']]
            if r is None: del n['mesh']
            else: n['mesh']=r
        n.pop('skin',None)
    # images
    isz=0
    for im in j.get('images',[]):
        if 'bufferView' in im:
            d,mt=opt_image(bv_bytes(im['bufferView']),a.tex,a.q); isz+=len(d)
            im['bufferView']=add_view(d); im['mimeType']=mt
    if a.matjson:
        over=json.load(open(a.matjson))
        for m in mats:
            if m.get('name') in over: m.update(over[m['name']])
    j['meshes']=new_meshes; j['accessors']=new_acc; j['bufferViews']=new_views
    j.pop('animations',None); j.pop('skins',None)
    while len(new_bin)%4: new_bin.append(0)
    j['buffers']=[{'byteLength':len(new_bin)}]
    js=pad4(json.dumps(j,separators=(',',':')).encode(),b' ')
    total=12+8+len(js)+8+len(new_bin)
    with open(a.out,'wb') as f:
        f.write(struct.pack('<4sII',b'glTF',2,total)); f.write(struct.pack('<I4s',len(js),b'JSON')); f.write(js)
        f.write(struct.pack('<I4s',len(new_bin),b'BIN\0')); f.write(bytes(new_bin))
    print(a.out,'size',total//1024,'KB images',isz//1024,'KB meshes',len(j['meshes']),'tris',tris_in,'->',tris_out)
main()
