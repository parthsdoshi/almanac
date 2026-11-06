# Renders the app icon from tools/icon.svg (designed on the Claude Design canvas):
#   python3 tools/make_icon.py   (needs cairosvg and Pillow)
import cairosvg, io
from PIL import Image
png = cairosvg.svg2png(url="tools/icon.svg", output_width=1024, output_height=1024)
Image.open(io.BytesIO(png)).convert("RGB").save("App/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png")
