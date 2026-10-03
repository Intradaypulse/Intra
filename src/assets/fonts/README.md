# Invisible OCR fonts

All searchable OCR uses PDFBox text rendering mode 3 (NEITHER). These fonts must never be used for visible text.

`scripts/build_ocr_fonts.py` builds four original PDFMate OCR identity fonts with fonttools 4.61.1 during Android project setup. Each Unicode scalar in planes 0–3 (except controls, surrogates and terminal noncharacters) has a unique glyph ID. Simple original outlines and fixed metrics are fitted to the recognized word bounds; embedded ToUnicode mappings retain logical text. No third-party glyph outlines are used. Fonts load lazily per document/plane and are shared across pages. Source and timestamps are deterministic. Coverage includes Latin, Devanagari, CJK and supplementary ideographs.

The older NotoSansDevanagariOCR.ttf is retained as a licensed fixture; the new writer does not use it. See OFL.txt. Source: google/fonts, ofl/notosansdevanagari/NotoSansDevanagari[wdth,wght].ttf, downloaded 2026-09-29, instantiated at weight 400 / width 100 with GSUB removed. Upstream SHA-256: 14ec4af41f27482216d1c2229f417ff9b1425e1babb014e57d1d40d03229853e.
