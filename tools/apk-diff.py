import sys,os,hashlib,base64
root=sys.argv[1]
owned={};pkg=d=None;cur=None
for line in open(os.path.join(root,'lib/apk/db/installed'),encoding='utf-8',errors='replace'):
    line=line.rstrip('\n')
    if line.startswith('P:'): pkg=line[2:]
    elif line.startswith('F:'): d=line[2:]; owned.setdefault(d,None)
    elif line.startswith('R:'):
        cur=os.path.relpath(os.path.realpath(os.path.join(root,d,line[2:])),root) if os.path.islink(os.path.join(root,d)) or os.path.islink(os.path.join(root,d.split('/')[0])) else d+'/'+line[2:]; owned[cur]=None
    elif line.startswith('Z:') and cur: owned[cur]=line[2:]; cur=None
unowned=[];modified=[]
skip=('proc','sys','dev','run','tmp','var/cache','var/log','lib/apk','etc/apk','usr/lib/modules','lib/modules','lib/firmware')
for dp,dns,fns in os.walk(root):
    rel=os.path.relpath(dp,root)
    if rel!='.' and rel.startswith(skip): dns[:]=[];continue
    for f in fns:
        r=os.path.normpath(os.path.join(rel,f))
        if os.path.islink(os.path.join(root,r)): continue
        if r not in owned: unowned.append(r); continue
        z=owned[r]
        if z and z.startswith('Q1') and not os.path.islink(os.path.join(root,r)):
            h=base64.b64encode(hashlib.sha1(open(os.path.join(root,r),'rb').read()).digest()).decode()
            if h!=z[2:]: modified.append(r)
print('UNOWNED',len(unowned)); [print(' ',u) for u in sorted(unowned)]
print('MODIFIED',len(modified)); [print(' ',m) for m in sorted(modified)]
