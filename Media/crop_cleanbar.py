from PIL import Image

# Slices the user-supplied CleanFullBar.tga (a plain, textureless
# chevron-pointed bar shape, 261x12) and BarTexture.tga (a separate
# black-with-sparse-alpha grain overlay meant to layer on top of it, same
# canvas size) into matching fixed-cap-plus-tileable-fill pieces, same
# technique as crop_statusbar.py. Both files share the same crop bounds so
# the grain overlay lines up exactly with the clean bar underneath it.
#
# Bounds below were established by profiling CleanFullBar.tga's alpha
# channel per-column (to find where the pointed taper ends and the flat
# middle begins) -- rerun this only if CleanFullBar.tga/BarTexture.tga
# themselves change; these numbers are specific to their current layout.
src_dir = r"E:\Development\modern-calendar\CalendarPlus\Media"

LEFT_CAP_END = 8
RIGHT_CAP_START = 253  # CleanFullBar.tga is 261px wide

clean = Image.open(f"{src_dir}\\CleanFullBar.tga").convert("RGBA")
texture = Image.open(f"{src_dir}\\BarTexture.tga").convert("RGBA")

pieces = [
    ("CleanFullBarCapLeft", clean.crop((0, 0, LEFT_CAP_END, clean.height))),
    ("CleanFullBarCapRight", clean.crop((RIGHT_CAP_START, 0, clean.width, clean.height))),
    ("CleanFullBarFill", clean.crop((LEFT_CAP_END, 0, RIGHT_CAP_START, clean.height))),
    ("BarTextureFill", texture.crop((LEFT_CAP_END, 0, RIGHT_CAP_START, texture.height))),
]

for name, im in pieces:
    path = f"{src_dir}\\{name}.tga"
    im.save(path)
    print(name, im.size, "->", path)
