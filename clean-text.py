#!/usr/bin/env python3
# Strips copy junk from text for the "Clean text" command: odd spaces, invisible characters,
# Windows line endings, trailing spaces, extra blank lines.
import re, sys

t = sys.stdin.read()
t = t.replace("\r\n", "\n").replace("\r", "\n")
t = re.sub(r"[\u00a0\u2000-\u200a\u202f\u205f\u3000]", " ", t)    # non-breaking and other unusual spaces
t = re.sub(r"[\u200b-\u200d\u2060\ufeff\u00ad]", "", t)           # zero-width characters, soft hyphens
t = re.sub(r"[ \t]+$", "", t, flags=re.M)                          # trailing spaces on each line
t = re.sub(r"\n{3,}", "\n\n", t)                                   # at most one blank line in a row
sys.stdout.write(t.strip("\n").strip(" "))
