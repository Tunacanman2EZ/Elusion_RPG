#!/usr/bin/env python3
"""
shrink_emoji_font.py - scale the colour emoji font's pictures down to chat size.

    pip install fonttools pillow pyoxipng
    python tools/shrink_emoji_font.py NotoColorEmoji.ttf assets/fonts/NotoColorEmoji.ttf

The first argument is the font as Google releases it (noto-emoji, 109 ppem),
the second is where the chat-size copy goes. Every emoji is kept; only the
pictures get smaller.

WHY
---
Noto Color Emoji stores every emoji as a 136x128 PNG (one strike at 109 ppem),
10.8 MB in all, and it was three quarters of the browser build's game file. The
chat draws emoji at 10 to 16 px on a 1280x720 canvas, so at most 32 px on a
1440p screen. A 32 ppem strike is drawn at that size or smaller everywhere the
game uses it, and the font comes out at about a third of the size.

HOW
---
For each glyph: scale the picture by 32/109 with premultiplied alpha (so the
edges do not go dark), reduce it to a 256-colour palette the way the original
pictures already are, and compress it with oxipng. The glyph's metrics and the
strike's line metrics are scaled by the same factor, which is what tells the
renderer the picture is now drawn at 32 ppem.

It refuses a font whose strike is already this small, because doing it twice
would only blur the pictures a second time.

LICENCE
-------
The font is under the SIL Open Font License 1.1 (assets/fonts/OFL.txt), which
allows modifying it. The modified font is still under the OFL, keeps Google's
copyright notice and declares no Reserved Font Name, so it may keep its name.
The version string says which build it is.
"""
import io
import sys

from fontTools.ttLib import TTFont
from PIL import Image
import oxipng

TARGET_PPEM = 32
MARK = "; Elusion chat size %d ppem" % TARGET_PPEM

LINE_METRICS = ("ascender", "descender", "widthMax", "minOriginSB",
                "minAdvanceSB", "maxBeforeBL", "minAfterBL")


def _scaled(value: int, scale: float, lo: int, hi: int) -> int:
    return max(lo, min(hi, round(value * scale)))


def shrink(src: str, dst: str) -> None:
    font = TTFont(src)
    if "CBDT" not in font or len(font["CBLC"].strikes) != 1:
        sys.exit("expected one CBDT strike, as Noto Color Emoji has")
    strike = font["CBLC"].strikes[0]
    old_ppem = strike.bitmapSizeTable.ppemX
    if old_ppem <= TARGET_PPEM:
        sys.exit("the strike is already %d ppem; start from Google's release" % old_ppem)
    scale = TARGET_PPEM / old_ppem

    glyphs = font["CBDT"].strikeData[0]
    for glyph in glyphs.values():
        glyph.ensureDecompiled()
        picture = Image.open(io.BytesIO(glyph.imageData)).convert("RGBA")
        size = (max(1, round(picture.width * scale)), max(1, round(picture.height * scale)))
        picture = picture.convert("RGBa").resize(size, Image.LANCZOS).convert("RGBA")
        picture = picture.quantize(colors=256, method=Image.Quantize.FASTOCTREE)
        out = io.BytesIO()
        picture.save(out, "PNG")
        glyph.imageData = oxipng.optimize_from_memory(out.getvalue(), level=4)
        m = glyph.metrics
        m.width, m.height = size
        m.BearingX = _scaled(m.BearingX, scale, -128, 127)
        m.BearingY = _scaled(m.BearingY, scale, -128, 127)
        m.Advance = _scaled(m.Advance, scale, 0, 255)

    table = strike.bitmapSizeTable
    table.ppemX = table.ppemY = TARGET_PPEM
    for line in (table.hori, table.vert):
        for name in LINE_METRICS:
            value = getattr(line, name)
            setattr(line, name, _scaled(value, scale, 0 if name == "widthMax" else -128,
                                        255 if name == "widthMax" else 127))

    for record in font["name"].names:
        if record.nameID == 5 and MARK not in record.toUnicode():
            record.string = record.toUnicode() + MARK

    font.save(dst)
    print("%d emoji, %d ppem -> %d ppem, written to %s" % (len(glyphs), old_ppem, TARGET_PPEM, dst))


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    shrink(sys.argv[1], sys.argv[2])
