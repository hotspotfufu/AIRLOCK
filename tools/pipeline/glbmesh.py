import numpy as np, json, struct
from glbinfo import load, trs
CT={5120:np.int8,5121:np.uint8,5122:np.int16,5123:np.uint16,5125:np.uint32,5126:np.float32}
NC={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}
def acc(j,bin_,i):
    a=j['accessors'][i]; bv=j['bufferViews'][a['bufferView']]
    dt=np.dtype(CT[a['componentType']]); nc=NC[a['type']]
    off=bv.get('byteOffset',0)+a.get('byteOffset',0); st=bv.get('byteStride',0)
    if st and st!=dt.itemsize*nc:
        raw=np.frombuffer(bin_,np.uint8,count=st*(a['count']-1)+dt.itemsize*nc,offset=off)
        idx=(np.arange(a['count'])[:,None]*st+np.arange(dt.itemsize*nc)[None,:])
        arr=raw[idx].copy().view(dt).reshape(a['count'],nc)
    else:
        arr=np.frombuffer(bin_,dt,count=a['count']*nc,offset=off).reshape(a['count'],nc)
    return arr
def instances(f):
    """yield (nodename, matname, world verts Nx3, tris Mx3)"""
    j,bin_=load(f); out=[]
    def walk(ni,M):
        n=j['nodes'][ni]; W=M@trs(n)
        if 'mesh' in n:
            for p in j['meshes'][n['mesh']]['primitives']:
                v=acc(j,bin_,p['attributes']['POSITION']).astype(float)
                w=(W[:3,:3]@v.T).T+W[:3,3]
                t=acc(j,bin_,p['indices']).reshape(-1,3) if 'indices' in p else np.arange(len(v)).reshape(-1,3)
                mn=j['materials'][p['material']].get('name') if 'material' in p else None
                out.append((n.get('name'),mn,w,t))
        for c in n.get('children',[]): walk(c,W)
    for r in j['scenes'][j.get('scene',0)]['nodes']: walk(r,np.eye(4))
    return out
