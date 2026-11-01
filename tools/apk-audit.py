import sys,os,collections
root=sys.argv[1]
pkg=None;d=None;missing=collections.defaultdict(list);total=0
for line in open(os.path.join(root,'lib/apk/db/installed'),encoding='utf-8',errors='replace'):
    line=line.rstrip('\n')
    if line.startswith('P:'): pkg=line[2:]
    elif line.startswith('F:'): d=line[2:]
    elif line.startswith('R:'):
        total+=1
        p=os.path.join(root,d,line[2:])
        if not os.path.lexists(p): missing[pkg].append(d+'/'+line[2:])
print('files',total,'missing',sum(len(v) for v in missing.values()))
for k,v in sorted(missing.items(),key=lambda x:-len(x[1])): print(len(v),k,v[0])
