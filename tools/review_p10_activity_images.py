from pathlib import Path
from PIL import Image,ImageDraw
import json,hashlib,struct,zlib,sys
r=Path(__file__).resolve().parents[1]
out=r/'docs/art_review/village_v2_p10_population/activity_r1'
folder=out/(sys.argv[1] if len(sys.argv)>1 else 'selected')
rows=json.loads((folder/'capture.json').read_text())
keys=sorted(set(a['candidate'] for a in rows))
proof=[]
for row in rows:
 p=folder/row['file']; data=p.read_bytes(); assert data[:8]==b'\x89PNG\r\n\x1a\n'
 assert struct.unpack('>II',data[16:24])==(1920,1080)
 offset=8
 while offset<len(data):
  n=struct.unpack('>I',data[offset:offset+4])[0]; end=offset+12+n
  assert zlib.crc32(data[offset+4:offset+8+n])&0xffffffff==struct.unpack('>I',data[offset+8+n:end])[0],p
  offset=end
 proof.append({'file':str(p.relative_to(r)),'sha256':hashlib.sha256(data).hexdigest(),'size':[1920,1080],'crc':'PASS'})
for key in keys:
 sheet=Image.new('RGB',(3200,1840),'#252525'); draw=ImageDraw.Draw(sheet)
 for row in [a for a in rows if a['candidate']==key]:
  im=Image.open(folder/row['file']).crop((480,40,1440,1080)); im.thumbnail((400,430)); x=row['phase']*400; y=row['view']*460
  sheet.paste(im,(x,y+25)); draw.text((x+3,y+3),'v%d p%d t%.2f'%(row['view'],row['phase'],row['time']),fill='white')
 sheet.save(folder/(key+'_sheet.jpg'))
(folder/'png_proof.json').write_text(json.dumps(proof,indent=2))
print('verified',len(proof),'1920x1080 PNG and CRC;',len(keys),'sheets')
