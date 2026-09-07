from pathlib import Path
import sys
from PIL import Image, ImageDraw, ImageFont
ROOT=Path(__file__).parent
VERSION=sys.argv[1] if len(sys.argv)>1 else 'v003'
PREFIX='' if VERSION=='v002' else VERSION+'_'
W,H=1800,1050
im=Image.new('RGB',(W,H),(235,233,227));d=ImageDraw.Draw(im)
font_path='C:/Windows/Fonts/arial.ttf'
font=ImageFont.truetype(font_path,24)
small=ImageFont.truetype(font_path,19)
title=ImageFont.truetype(font_path,32)
d.text((40,24),'HAKUREI REIMU  /  CHARACTER REFINEMENT',fill=(42,38,37),font=title)
d.text((42,66),VERSION+'   |   1.650 m sole-to-crown   |   8 heads (hair / bow excluded)   |   ART_REVIEW',fill=(104,86,81),font=small)
for idx,name in enumerate(('front','side','back')):
    x=idx*600
    d.rounded_rectangle((x+18,109,x+582,979),radius=14,fill=(249,247,243))
    pic=Image.open(ROOT/(PREFIX+name+'.png')).convert('RGBA')
    pic.thumbnail((600,800),Image.Resampling.LANCZOS)
    im.paste(pic,(x+(600-pic.width)//2,151),pic)
    d.text((x+42,123),name.upper()+'  /  ORTHOGRAPHIC',fill=(77,63,61),font=font)
d.text((40,1005),'Detailed blockout. Facial topology / hands / rigging / game optimization remain pending. User visual review required.',fill=(103,81,75),font=small)
im.save(ROOT/('reimu_turnaround_'+VERSION+'.jpg'),quality=94)
print(ROOT/('reimu_turnaround_'+VERSION+'.jpg'))
if VERSION!='v002':
    comp=Image.new('RGB',(1400,820),(235,233,227));cd=ImageDraw.Draw(comp)
    cd.text((28,20),'FACE / HAIR   -   BEFORE & AFTER',fill=(42,38,37),font=title)
    for idx,(label,filename) in enumerate((('v002  /  INITIAL BLOCKOUT','v002_face_baseline.png'),(VERSION+'  /  REFINEMENT',VERSION+'_face.png'))):
        x=idx*700
        cd.rounded_rectangle((x+15,76,x+685,749),radius=12,fill=(249,247,243))
        cd.text((x+30,87),label,fill=(77,63,61),font=font)
        pic=Image.open(ROOT/filename).convert('RGBA')
        pic.thumbnail((640,640),Image.Resampling.LANCZOS)
        comp.paste(pic,(x+30,115),pic)
    cd.text((28,778),'Same frontal camera. Geometry, materials and lighting all changed; this is not a shading-matched comparison.',fill=(103,81,75),font=small)
    comp.save(ROOT/('reimu_face_comparison_'+VERSION+'.jpg'),quality=94)
    print(ROOT/('reimu_face_comparison_'+VERSION+'.jpg'))
