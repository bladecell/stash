#!/usr/bin/env python3
# Removes tracking parameters from every URL in stdin; used by the "Remove tracking" command.
import re,sys
from urllib.parse import urlsplit,parse_qs
T=re.compile(r"(utm_\w+|fbclid|gclid|gclsrc|dclid|gbraid|wbraid|msclkid|yclid|twclid|ttclid|li_fat_id|igshid|igsh|si|mc_cid|mc_eid|_hsenc|_hsmi|mkt_tok|vero_id|oly_\w+|_ga|_gl|srsltid|spm|ref_src|ref_url|s_cid|trk|trkCampaign|epik|wickedid|rb_clickid|cvid|sxsrf|ved|ei|gs_lcrp|sca_esv)$",re.I)
W={"www.google.com":"/url","l.facebook.com":"/l.php","lm.facebook.com":"/l.php","l.instagram.com":"/"}
def unwrap(u):
  for _ in range(3):
    s=urlsplit(u)
    q=parse_qs(s.query)
    if W.get(s.netloc)==s.path:
      t=(q.get("url") or q.get("q") or q.get("u") or [""])[0]
    elif s.netloc=="href.li":
      t=s.query
    else:
      return u
    if not t.startswith("http"):
      return u
    u=t
  return u
def keep(p):
  return p and not T.match(p.split("=")[0])
def clean(m):
  u,_,frag=unwrap(m.group(0)).partition("#")
  base,_,q=u.partition("?")
  if re.match(r"https?://([a-z]+\.)?aliexpress\.[a-z.]+/item/",base):
    return base
  a=re.match(r"(https?://(?:www\.)?amazon\.[a-z.]+)/(?:[^/]+/)?(?:dp|gp/product)/([A-Z0-9]{10})",base)
  if a:
    return a.group(1)+"/dp/"+a.group(2)
  q="&".join(filter(keep,q.split("&")))
  return base+("?"+q if q else "")+("#"+frag if frag else "")
sys.stdout.write(re.sub(r"https?://[^\s<>\"]+",clean,sys.stdin.read()))
