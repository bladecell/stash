.pragma library

// Default custom commands. The item text arrives on stdin and in $STASH_TEXT ($STASH_KIND = item kind).
// output: copy | paste | replace (rewrite the item) | none. kinds: comma list (url,code,…), empty = all.
var defaults = [
  { name: "Open", command: "xdg-open \"$STASH_TEXT\"", output: "none", kinds: "url,path" },
  { name: "Remove tracking", command: "python3 -c 'import re,sys\nT=re.compile(r\"(utm_\\w+|fbclid|gclid|gclsrc|dclid|gbraid|wbraid|msclkid|yclid|twclid|ttclid|li_fat_id|igshid|igsh|si|mc_cid|mc_eid|_hsenc|_hsmi|mkt_tok|vero_id|oly_\\w+|_ga|_gl|srsltid|spm|ref_src|ref_url|s_cid|trk|trkCampaign|epik|wickedid|rb_clickid|cvid|sxsrf|ved|ei|gs_lcrp|sca_esv)$\",re.I)\ndef keep(p):\n  return p and not T.match(p.split(\"=\")[0])\ndef clean(m):\n  u,_,frag=m.group(0).partition(\"#\")\n  base,_,q=u.partition(\"?\")\n  q=\"&\".join(filter(keep,q.split(\"&\")))\n  return base+(\"?\"+q if q else \"\")+(\"#\"+frag if frag else \"\")\nsys.stdout.write(re.sub(r\"https?://[^\\s<>\\\"]+\",clean,sys.stdin.read()))'", output: "copy", kinds: "url,text" },
  { name: "Format JSON", command: "jq .", output: "copy", kinds: "code,text" },
  { name: "Minify JSON", command: "jq -c .", output: "copy", kinds: "code,text" },
  { name: "Base64 encode", command: "base64 -w0", output: "copy", kinds: "" },
  { name: "Base64 decode", command: "base64 -d", output: "copy", kinds: "" },
  { name: "Trim whitespace", command: "sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'", output: "replace", kinds: "" },
  { name: "Search the web", command: "xdg-open \"https://duckduckgo.com/?q=$(printf %s \"$STASH_TEXT\" | jq -sRr @uri)\"", output: "none", kinds: "text,code,email" }
];

var outputs = ["copy", "paste", "replace", "none"];

function appliesTo(cmd, kind) {
  const k = (cmd.kinds || "").trim();
  return !k || k.split(",").map(s => s.trim()).indexOf(kind) >= 0;
}
