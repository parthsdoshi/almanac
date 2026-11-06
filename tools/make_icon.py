# Draws the app icon: python3 tools/make_icon.py Shared/Fonts App/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png (needs Pillow)
# A "#!" on warm ink, in the app's display face, with the bang in gold.
import sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter
fontdir, out = sys.argv[1], sys.argv[2]
S=1024; SS=2; W=S*SS
def c(h,a=255): return ((h>>16)&255,(h>>8)&255,h&255,a)
img=Image.new("RGBA",(W,W))
d=ImageDraw.Draw(img)
top,bot=c(0x3A2C20),c(0x1E1610)
for y in range(W):
    t=y/W; d.line([(0,y),(W,y)],fill=tuple(int(a*(1-t)+b*t) for a,b in zip(top,bot)))
f=ImageFont.truetype(f"{fontdir}/AlmanacDisplay-Black.ttf",int(W*.56))
hash_, bang = "#", "!"
wh=d.textlength(hash_,font=f); wb=d.textlength(bang,font=f); gap=int(W*.01)
# center the ink, not the advance boxes
bh=d.textbbox((0,0),hash_,font=f,anchor="ls"); bb=d.textbbox((wh+gap,0),bang,font=f,anchor="ls")
left,right=bh[0],bb[2]; topy,boty=min(bh[1],bb[1]),max(bh[3],bb[3])
x0=(W-(right-left))/2-left; y=(W-(boty-topy))/2-topy
glow=Image.new("RGBA",(W,W),(0,0,0,0)); gd=ImageDraw.Draw(glow)
gd.text((x0+wh+gap,y),bang,font=f,fill=c(0xF2B33D,150),anchor="ls")
img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(W*.03)))
d=ImageDraw.Draw(img)
d.text((x0,y),hash_,font=f,fill=c(0xF8F0DF),anchor="ls")
d.text((x0+wh+gap,y),bang,font=f,fill=c(0xF2B33D),anchor="ls")
img.resize((S,S),Image.LANCZOS).convert("RGB").save(out)
