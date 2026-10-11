"""Copy catalog PNGs (art/catalog/catalog-data.json) into godot/art/items/<id>.png.

Each image is cropped to its visible alpha area, centred on a square canvas with a small margin
and downscaled to SIZE px, so every icon fills the inventory slot the same way.
Run from the project root:  python tools/icon_import/import_icons.py
"""
import json, os
from PIL import Image

SIZE = 256
MARGIN = 0.04
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CATALOG = os.path.join(ROOT, "art", "catalog", "catalog-data.json")
OUT = os.path.join(ROOT, "godot", "art", "items")

def main():
    data = json.load(open(CATALOG, encoding="utf-8"))
    os.makedirs(OUT, exist_ok=True)
    n = 0
    for item in data["items"]:
        rel = item.get("image")
        if not rel:
            continue
        src = os.path.normpath(os.path.join(ROOT, "art", "catalog", rel))
        im = Image.open(src).convert("RGBA")
        box = im.getchannel("A").point(lambda a: 255 if a > 8 else 0).getbbox() or (0, 0, *im.size)
        im = im.crop(box)
        side = int(max(im.size) * (1 + MARGIN * 2))
        canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
        canvas.paste(im, ((side - im.width) // 2, (side - im.height) // 2))
        canvas.resize((SIZE, SIZE), Image.LANCZOS).save(os.path.join(OUT, item["id"] + ".png"), optimize=True)
        n += 1
    print(f"{n} icons -> {OUT}")

if __name__ == "__main__":
    main()
