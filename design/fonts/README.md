# Fonts

`Newtown.ttf` is Newtown Regular, a TrueType font by Roger White (1994), which OpenReliant carries
built in ([deps/newtown](https://github.com/OpenReliant/openreliant/tree/main/deps/newtown)). Newtown
is in the public domain: Roger White's site, Roger's Fonts, says that every font on it is now public
domain, for personal and commercial use alike, and asks only that the source be acknowledged where a
font is used commercially.

Browsers refuse the original file, so this copy has two fixes: the last range of its character map
maps U+FFFF to the missing glyph, as the format asks, and its `maxp` table gives 2 zones rather than
3.

The pages load IBM Plex Sans and JetBrains Mono from Google Fonts. Both are under the SIL Open Font
License, so the editor can carry them too.
