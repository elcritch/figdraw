import std/unicode

func isAsciiText*(text: string): bool =
  for ch in text:
    if ord(ch) >= 128:
      return false
  result = true

func isSpaceRune*(rune: Rune): bool {.inline.} =
  ## Avoids a Unicode table lookup for ASCII whitespace.
  if rune.uint32 < 0x80:
    rune.int in {0x09 .. 0x0d, 0x20}
  else:
    rune.isWhiteSpace
