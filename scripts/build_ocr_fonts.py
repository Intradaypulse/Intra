"""Build original, OCR-only identity fonts. Requires fonttools==4.61.1.

These are not display fonts. Unique glyph IDs preserve Unicode through PDFBox's
ToUnicode map; uniform metrics are fitted to each recognized word. Rendering
mode 3 (NEITHER) is mandatory. No third-party glyph outlines are used.
"""
from pathlib import Path
import sys
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen


def build(destination: Path):
    destination.mkdir(parents=True, exist_ok=True)
    for plane in range(4):
        points = [cp for cp in range(plane << 16, (plane + 1) << 16)
                  if cp & 0xffff < 0xfffe and not 0xd800 <= cp <= 0xdfff
                  and not cp < 32 and not 0x7f <= cp <= 0x9f]
        names = ['.notdef'] + [f'u{cp:06X}' for cp in points]
        builder = FontBuilder(1000, isTTF=True)
        builder.setupGlyphOrder(names)
        builder.setupCharacterMap(dict(zip(points, names[1:])))
        pen = TTGlyphPen(None)
        pen.moveTo((0, -200))
        pen.lineTo((500, -200))
        pen.lineTo((500, 800))
        pen.lineTo((0, 800))
        pen.closePath()
        glyph = pen.glyph()
        builder.setupGlyf({name: glyph for name in names})
        builder.setupHorizontalMetrics({name: (500, 0) for name in names})
        builder.setupHorizontalHeader(ascent=800, descent=-200)
        builder.setupNameTable({'familyName': f'PDFMate OCR {plane}',
            'styleName': 'Regular', 'uniqueFontIdentifier': f'PDFMateOCR{plane}-1',
            'fullName': f'PDFMate OCR {plane}', 'psName': f'PDFMateOCR{plane}',
            'version': 'Version 1.0'})
        builder.setupOS2(sTypoAscender=800, sTypoDescender=-200,
                        usWinAscent=800, usWinDescent=200)
        builder.setupPost(keepGlyphNames=False)
        builder.setupMaxp()
        builder.font['head'].created = builder.font['head'].modified = 2082844800
        builder.font.recalcTimestamp = False
        builder.save(destination / f'PDFMateOCR{plane}.ttf')


if __name__ == '__main__':
    build(Path(sys.argv[1]))
