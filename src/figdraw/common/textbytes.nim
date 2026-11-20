func isAsciiText*(text: string): bool =
  for ch in text:
    if ord(ch) >= 128:
      return false
  result = true
