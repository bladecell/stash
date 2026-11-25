.pragma library

// Default custom commands. The item text arrives on stdin and in $STASH_TEXT ($STASH_KIND = item kind).
// output: copy | paste | replace (rewrite the item) | none. kinds: comma list (url,code,…), empty = all.
var defaults = [
  { name: "Open", command: "xdg-open \"$STASH_TEXT\"", output: "none", kinds: "url,path" },
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
