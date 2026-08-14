; extends

; pyright escapes markdown punctuation when it converts a Python docstring to
; markdown, so `read_only` arrives as `read\_only`. The runtime query only
; highlights the escape as @string.escape -- it never hides the backslash, so
; hover floats (conceallevel=2) show it verbatim. Conceal just the backslash by
; shrinking the capture to its first character; the escaped character stays.
((backslash_escape) @conceal
  (#offset! @conceal 0 0 0 -1)
  (#set! conceal ""))
