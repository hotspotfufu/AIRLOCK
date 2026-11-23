"""Split the static astronaut into rigid parts with joint pivots so code can animate it."""
import json,struct,io,numpy as np
from PIL import Image
from glbinfo import load
from glbmesh import acc as racc
SRC='/mnt/user-data/uploads/7e575c3f-an_astronaut_infused__0320143842_texture.glb'
OUT='/home/claude/airlock/assets/models/astronaut/astronaut.glb'
j,b=load(SRC); p=j['meshes'][0]['primitives'][0]
pos=racc(j,b,p['attributes']['POSITION']).astype(np.float64); nrm=racc(j,b,p['attributes']['NORMAL']).astype(np.float64)
uv=racc(j,b,p['attributes']['TEXCOORD_0']).astype(np.float64); idx=racc(j,b,p['indices']).reshape(-1,3).astype(np.int64)
# node transform (FAB wrapper) – apply world matrix
from glbinfo import trs
W=np.eye(4)
def find(ni,M):
    n=j['nodes'][ni]; Wn=M@trs(n)
    if 'mesh' in n: return Wn
    for c in n.get('children',[]):
        r=find(c,Wn)
        if r is not None: return r
for r in j['scenes'][0]['nodes']:
    m=find(r,np.eye(4))
    if m is not None: W=m
pos=(W[:3,:3]@pos.T).T+W[:3,3]; nrm=(W[:3,:3]@nrm.T).T
# decimate (uv-aware clustering)
CELL=0.015
key=np.concatenate([np.round(pos/CELL),np.round(uv*24)],axis=1).astype(np.int64)
_,inv,cnt=np.unique(key,axis=0,return_inverse=True,return_counts=True); inv=inv.ravel(); n=len(cnt)
def avg(a):
    o=np.zeros((n,a.shape[1])); np.add.at(o,inv,a); return o/cnt[:,None]
pos,nrm,uv=avg(pos),avg(nrm),avg(uv); nrm/=np.maximum(np.linalg.norm(nrm,axis=1,keepdims=True),1e-9)
t=inv[idx]; t=t[(t[:,0]!=t[:,1])&(t[:,1]!=t[:,2])&(t[:,0]!=t[:,2])]
print('tris',len(idx),'->',len(t))
# classify triangles by centroid (original model space: 2 m tall, centred, faces +Z)
c=pos[t].mean(1); x,y=c[:,0],c[:,1]
part=np.full(len(t),'torso',dtype=object)
armb=np.where(y>0.2,0.235,0.30)
arm=(np.abs(x)>armb)&(y>-0.25)&(y<0.74)
part[arm&(x>0)]='arm_px'; part[arm&(x<0)]='arm_nx'
leg=(y<-0.12)&~arm
part[leg&(y>=-0.52)&(x>0)]='thigh_px'; part[leg&(y>=-0.52)&(x<0)]='thigh_nx'
part[leg&(y<-0.52)&(x>0)]='shin_px'; part[leg&(y<-0.52)&(x<0)]='shin_nx'
# final space: scale .9, feet at y=0, rotated 180 deg so it faces -Z (Godot forward). x -> -x so model +x becomes the LEFT side.
S=0.9
def fin(v): return np.stack([-v[:,0]*S,(v[:,1]+1.0)*S,-v[:,2]*S],1)
fpos=fin(pos); fnrm=np.stack([-nrm[:,0],nrm[:,1],-nrm[:,2]],1)
def piv(x,y,z): return np.array([-x*S,(y+1.0)*S,-z*S])
PARTS={ # name: (source tag, pivot (model space), parent)
 'Torso':('torso',piv(0,-0.1,0),None),
 'ArmL':('arm_px',piv(0.27,0.6,-0.02),'Torso'),'ArmR':('arm_nx',piv(-0.27,0.6,-0.02),'Torso'),
 'ThighL':('thigh_px',piv(0.12,-0.1,0),'Torso'),'ThighR':('thigh_nx',piv(-0.12,-0.1,0),'Torso'),
 'ShinL':('shin_px',piv(0.13,-0.52,0.0),'ThighL'),'ShinR':('shin_nx',piv(-0.13,-0.52,0.0),'ThighR')}
binb=bytearray(); views=[]; accs=[]
def view(data,target=None):
    while len(binb)%4: binb.append(0)
    v={'buffer':0,'byteOffset':len(binb),'byteLength':len(data)}
    if target: v['target']=target
    binb.extend(data); views.append(v); return len(views)-1
def accr(arr,typ,ct,target,mm=False):
    arr=np.ascontiguousarray(arr); d={'bufferView':view(arr.tobytes(),target),'componentType':ct,'count':len(arr),'type':typ}
    if mm: d['min']=arr.min(0).tolist(); d['max']=arr.max(0).tolist()
    accs.append(d); return len(accs)-1
nodes=[{'name':'Astronaut','children':[]}]; meshes=[]; index={}
for name,(tag,pv,parent) in PARTS.items():
    tt=t[part==tag]; used=np.unique(tt); rm=np.full(len(pos),-1); rm[used]=np.arange(len(used))
    P=(fpos[used]-pv).astype(np.float32)
    prim={'attributes':{'POSITION':accr(P,'VEC3',5126,34962,True),'NORMAL':accr(fnrm[used].astype(np.float32),'VEC3',5126,34962),
          'TEXCOORD_0':accr(uv[used].astype(np.float32),'VEC2',5126,34962)},
          'indices':accr(rm[tt].ravel().astype(np.uint16 if len(used)<65535 else np.uint32),'SCALAR',5123 if len(used)<65535 else 5125,34963),'material':0,'mode':4}
    meshes.append({'name':name,'primitives':[prim]})
    ppv=PARTS[parent][1] if parent else np.zeros(3)
    nodes.append({'name':name,'mesh':len(meshes)-1,'translation':(pv-ppv).tolist()}); index[name]=len(nodes)-1
    print(name,len(tt),'tris')
for name,(tag,pv,parent) in PARTS.items():
    nodes[index[parent] if parent else 0].setdefault('children',[]).append(index[name])
im=j['images'][0]; bv=j['bufferViews'][im['bufferView']]; d=b[bv.get('byteOffset',0):bv.get('byteOffset',0)+bv['byteLength']]
img=Image.open(io.BytesIO(d)).convert('RGB').resize((1024,1024),Image.LANCZOS); o=io.BytesIO(); img.save(o,'JPEG',quality=85)
img.resize((256,256)).save('/tmp/astro_tex.png')
mat=j['materials'][0]; mat['doubleSided']=True
g={'asset':{'version':'2.0'},'scene':0,'scenes':[{'nodes':[0]}],'nodes':nodes,'meshes':meshes,'materials':[mat],
   'textures':j['textures'],'samplers':j.get('samplers',[]),'images':[{'bufferView':view(o.getvalue()),'mimeType':'image/jpeg'}],
   'accessors':accs,'bufferViews':views}
if not g['samplers']: del g['samplers']
while len(binb)%4: binb.append(0)
g['buffers']=[{'byteLength':len(binb)}]
js=json.dumps(g,separators=(',',':')).encode(); js+=b' '*((4-len(js)%4)%4)
with open(OUT,'wb') as f:
    f.write(struct.pack('<4sII',b'glTF',2,28+len(js)+len(binb))); f.write(struct.pack('<I4s',len(js),b'JSON')); f.write(js); f.write(struct.pack('<I4s',len(binb),b'BIN\0')); f.write(bytes(binb))
print('wrote',(28+len(js)+len(binb))//1024,'KB')
