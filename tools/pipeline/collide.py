"""Occupancy grid -> merged collision boxes + map image. Input: world tris in body band."""
import numpy as np, json, sys
from PIL import Image
CELL=0.2; YLO,YHI=0.35,1.7
t=np.fromfile('/tmp/station_tris.bin',np.float32).reshape(-1,3,3).astype(np.float64)
print('tris',len(t))
x0,z0=t[:,:,0].min()-1,t[:,:,2].min()-1; x1,z1=t[:,:,0].max()+1,t[:,:,2].max()+1
W=int(np.ceil((x1-x0)/CELL)); H=int(np.ceil((z1-z0)/CELL))
occ=np.zeros((H,W),bool)
e=np.linalg.norm(t-np.roll(t,1,axis=1),axis=2).max(1)
n=np.clip(np.ceil(e/(CELL*0.45)).astype(int),1,400)
for k in np.unique(n):
    sel=t[n==k]
    i,j=np.meshgrid(np.arange(k+1),np.arange(k+1),indexing='ij'); m=(i+j)<=k
    u=i[m]/k; v=j[m]/k; w=1-u-v
    for s in range(0,len(sel),20000):
        T=sel[s:s+20000]
        P=T[:,0,None,:]*u[None,:,None]+T[:,1,None,:]*v[None,:,None]+T[:,2,None,:]*w[None,:,None]
        P=P.reshape(-1,3); P=P[(P[:,1]>=YLO)&(P[:,1]<=YHI)]
        occ[((P[:,2]-z0)/CELL).astype(int),((P[:,0]-x0)/CELL).astype(int)]=True
print('grid',W,H,'occupied',occ.sum())
np.save('/tmp/occ.npy',occ); json.dump({'x0':x0,'z0':z0,'cell':CELL},open('/tmp/occ_meta.json','w'))
Image.fromarray((~occ*255).astype(np.uint8)).resize((W*3,H*3),Image.NEAREST).save('/tmp/occ.png')
# --- close 1-cell gaps, then greedy-merge into rectangles ---
from scipy import ndimage
occ=ndimage.binary_closing(np.pad(occ,2),structure=np.ones((3,3)))[2:-2,2:-2]
g=occ.copy(); boxes=[]
for r in range(H):
    c=0
    while c<W:
        if not g[r,c]: c+=1; continue
        c2=c
        while c2<W and g[r,c2]: c2+=1
        r2=r+1
        while r2<H and g[r2,c:c2].all(): r2+=1
        g[r:r2,c:c2]=False
        boxes.append([round(x0+c*CELL,3),round(z0+r*CELL,3),round(x0+c2*CELL,3),round(z0+r2*CELL,3)])
        c=c2
print('boxes',len(boxes))
json.dump(boxes,open('/home/claude/airlock/levels/station/collision_boxes.json','w'))
Image.fromarray((~occ*255).astype(np.uint8)).resize((W*3,H*3),Image.NEAREST).save('/tmp/occ.png')
np.save('/tmp/occ.npy',occ)
