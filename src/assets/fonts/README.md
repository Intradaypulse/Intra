# Invisible OCR font

NotoSansDevanagariOCR.ttf is an OFL-licensed Noto Sans Devanagari derivative used only for invisible searchable text, not for rendering visible Hindi glyphs. See OFL.txt.

Source: google/fonts, ofl/notosansdevanagari/NotoSansDevanagari[wdth,wght].ttf, downloaded 2026-09-29. Instantiate weight 400 / width 100 with fontTools; remove GSUB because the invisible PDF layer must preserve logical Unicode order. Subset U+0020–024F, U+0900–097F, U+1CD0–1CFF, U+2000–206F, U+20A0–20CF, U+A8E0–A8FF. This includes rupee signs, smart punctuation, Latin accents and Devanagari. Unsupported scripts fail output verification instead of silently returning corrupted text.

Upstream source SHA-256: `14ec4af41f27482216d1c2229f417ff9b1425e1babb014e57d1d40d03229853e`.
