# Draws the app icon: python3 tools/make_icon.py Shared/Fonts App/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png (needs Pillow)
import sys, math, random
from PIL import Image, ImageDraw, ImageFont, ImageFilter
fontdir, out = sys.argv[1], sys.argv[2]
S=1024; SS=2; W=S*SS
def c(h): return ((h>>16)&255,(h>>8)&255,h&255,255)
paper=c(0xF8F0DF); card=c(0xFFFAF0); ink=c(0x2B2118); red=c(0xB8322A); rule=c(0xE3D3B4); gold=c(0xF2B33D); sunk=c(0xEFE3CB)
img=Image.new("RGBA",(W,W),c(0xF2B33D))
d=ImageDraw.Draw(img)
# warm gold background with soft vignette via gradient
for y in range(W):
    t=y/W
    col=tuple(int(a*(1-t)+b*t) for a,b in zip(c(0xF6C25A)[:3],c(0xE89A2E)[:3]))+(255,)
    d.line([(0,y),(W,y)],fill=col)
# page geometry
px0,py0,px1,py1=int(W*.19),int(W*.20),int(W*.81),int(W*.84)
r=int(W*.06)
# shadow
sh=Image.new("RGBA",(W,W),(0,0,0,0)); sd=ImageDraw.Draw(sh)
sd.rounded_rectangle([px0+int(W*.012),py0+int(W*.03),px1+int(W*.012),py1+int(W*.03)],r,fill=(90,45,10,110))
sh=sh.filter(ImageFilter.GaussianBlur(W*.02)); img.alpha_composite(sh)
d=ImageDraw.Draw(img)
# stacked pages behind
d.rounded_rectangle([px0+int(W*.02),py0+int(W*.02),px1+int(W*.02),py1+int(W*.02)],r,fill=sunk)
d.rounded_rectangle([px0,py0,px1,py1],r,fill=card)
# red header band
hb=py0+int(W*.17)
d.rounded_rectangle([px0,py0,px1,hb+r],r,fill=red)
d.rectangle([px0,hb,px1,hb+r],fill=card)
# perforation line
for x in range(px0+int(W*.03),px1-int(W*.02),int(W*.028)):
    d.ellipse([x,hb-int(W*.006),x+int(W*.012),hb+int(W*.006)],fill=card)
# binding rings
for cx in (px0+int(W*.17),px1-int(W*.17)):
    d.ellipse([cx-int(W*.03),py0+int(W*.05),cx+int(W*.03),py0+int(W*.11)],fill=c(0x7A1F19))
    d.rounded_rectangle([cx-int(W*.014),py0-int(W*.06),cx+int(W*.014),py0+int(W*.085)],int(W*.014),fill=ink)
# month label
f1=ImageFont.truetype(f"{fontdir}/AlmanacDisplay-SemiBoldItalic.ttf",int(W*.075))
txt="Almanac"
bb=d.textbbox((0,0),txt,font=f1)
# big number
f2=ImageFont.truetype(f"{fontdir}/AlmanacDisplay-Black.ttf",int(W*.36))
num="1"
bb=d.textbbox((0,0),num,font=f2,anchor="mm")
d.text(((px0+px1)//2,(hb+py1)//2+int(W*.03)),num,font=f2,fill=ink,anchor="mm")
# confetti
random.seed(7)
conf=[c(0xE0533D),c(0x3D8FC9),c(0xE36FA0),c(0x4FA36B),c(0xFFFAF0)]
spots=[(.17,.16),(.83,.14),(.10,.55),(.91,.48),(.18,.86),(.84,.88),(.50,.93),(.33,.09),(.68,.07)]
for i,(x,y) in enumerate(spots):
    x*=W;y*=W; s=W*.022; col=conf[i%len(conf)]
    if i%2==0: d.ellipse([x-s,y-s,x+s,y+s],fill=col)
    else:
        a=random.uniform(0,math.pi)
        pts=[(x+math.cos(a+k*math.pi/2)*s*(1.6 if k%2==0 else .6),y+math.sin(a+k*math.pi/2)*s*(1.6 if k%2==0 else .6)) for k in range(4)]
        d.polygon(pts,fill=col)
img=img.resize((S,S),Image.LANCZOS).convert("RGB")
img.save(out)
