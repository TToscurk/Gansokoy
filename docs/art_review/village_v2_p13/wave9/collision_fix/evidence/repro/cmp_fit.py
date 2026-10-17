import json,sys
a=json.load(open(sys.argv[1],encoding='utf-8'))['buildings']; b=json.load(open(sys.argv[2],encoding='utf-8'))['buildings']
k=lambda x:(x['tier'],x['x0'],x['x1'],x['z0'],x['z1'],x['y0'],x['y1'])
print('buildings',len(a),'->',len(b),'boxes',sum(len(v['boxes']) for v in a.values()),'->',sum(len(v['boxes']) for v in b.values()))
for id in sorted(set(a)|set(b)):
    A=set(map(k,a.get(id,{}).get('boxes',[]))); B=set(map(k,b.get(id,{}).get('boxes',[])))
    if A!=B:
        print('==',id, len(A),'->',len(B))
        for x in sorted(A-B): print('   -',x)
        for x in sorted(B-A): print('   +',x)
