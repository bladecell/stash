#!/usr/bin/env python3
# Prints "show" once Super + left Alt have been held alone for DELAY seconds, and "hide" when either is
# released or another key is pressed. Reads /dev/input keyboards (needs the input group); only
# modifier state is tracked, nothing is stored or sent anywhere.
import glob, os, re, select, struct, sys, time

DELAY = float(sys.argv[1]) if len(sys.argv) > 1 else 0.5
EVENT = struct.Struct("llHHi")
EV_KEY = 1
SUPER = {125, 126}  # KEY_LEFTMETA, KEY_RIGHTMETA
ALT = {56}          # KEY_LEFTALT (right Alt is AltGr on many layouts)


def keyboards():
  """Device nodes whose capabilities look like a keyboard (EV_KEY with letter keys)."""
  out = []
  for block in open("/proc/bus/input/devices").read().split("\n\n"):
    ev = re.search(r"^B: EV=(\w+)", block, re.M)
    key = re.search(r"^B: KEY=([\w ]+)", block, re.M)
    hnd = re.search(r"^H: Handlers=.*\b(event\d+)", block, re.M)
    if not (ev and key and hnd) or not int(ev.group(1), 16) & (1 << EV_KEY):
      continue
    words = key.group(1).split()
    low = int(words[-1], 16) if words else 0
    if low & (1 << 30) and low & (1 << 16):  # KEY_A and KEY_Q present
      out.append("/dev/input/" + hnd.group(1))
  return out


def emit(s):
  sys.stdout.write(s + "\n")
  sys.stdout.flush()


fds, rescan = {}, 0.0
down = set()
since = None     # when Super+Alt became held alone
dirty = False    # another key was pressed while they were held
shown = False

while True:
  now = time.monotonic()
  if now >= rescan:
    for path in keyboards():
      if path not in fds.values():
        try:
          fds[os.open(path, os.O_RDONLY | os.O_NONBLOCK)] = path
        except OSError:
          pass
    rescan = now + 10
  timeout = 10.0
  if since is not None and not dirty and not shown:
    timeout = max(0.0, since + DELAY - now)
  ready, _, _ = select.select(list(fds), [], [], timeout)
  for fd in ready:
    try:
      data = os.read(fd, EVENT.size * 64)
    except OSError:
      os.close(fd)
      fds.pop(fd, None)
      continue
    for i in range(0, len(data) - EVENT.size + 1, EVENT.size):
      _, _, typ, code, value = EVENT.unpack_from(data, i)
      if typ != EV_KEY or value == 2:  # ignore autorepeat
        continue
      if value == 1:
        down.add(code)
        if code not in SUPER | ALT:
          dirty = True
      else:
        down.discard(code)
  held = bool(down & SUPER) and bool(down & ALT)
  if not held:
    since, dirty = None, False
  elif since is None:
    since = time.monotonic()
  if shown and (not held or dirty):
    shown = False
    emit("hide")
  elif held and not dirty and not shown and time.monotonic() - since >= DELAY:
    shown = True
    emit("show")
