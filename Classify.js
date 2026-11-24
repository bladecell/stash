.pragma library

var urlRe = /^(https?|ftp|file):\/\/\S+$/i;
var emailRe = /^[^\s@]+@[^\s@]+\.[a-z]{2,}$/i;
var pathRe = /^(~|\.{0,2})\/[^\s]*$/;
var hexRe = /^#([0-9a-f]{3}|[0-9a-f]{4}|[0-9a-f]{6}|[0-9a-f]{8})$/i;
var fnColorRe = /^(rgba?|hsla?)\(\s*([\d.]+%?)[\s,]+([\d.]+%?)[\s,]+([\d.]+%?)(?:[\s,/]+([\d.]+%?))?\s*\)$/i;
var codeRe = /(;\s*$|[{}]\s*$|=>|\b(const|let|var|function|def|class|import|return|fn|pub|struct|SELECT|FROM|WHERE)\b|^\s*(\$|#!|sudo |git |cd |ls |dms |niri |npm |cargo |python3? ))/m;

function parseColor(s) {
  var t = s.trim();
  if (hexRe.test(t)) {
    var h = t.slice(1);
    if (h.length <= 4)
      h = h.split("").map(function (c) { return c + c; }).join("");
    var n = parseInt(h.slice(0, 6), 16);
    var a = h.length === 8 ? parseInt(h.slice(6), 16) / 255 : 1;
    return { r: (n >> 16) / 255, g: ((n >> 8) & 255) / 255, b: (n & 255) / 255, a: a };
  }
  var m = fnColorRe.exec(t);
  if (!m)
    return null;
  var pct = function (v, max) { return v.endsWith("%") ? parseFloat(v) / 100 : parseFloat(v) / max; };
  var a2 = m[5] !== undefined ? pct(m[5], 1) : 1;
  if (m[1].toLowerCase().startsWith("rgb"))
    return { r: pct(m[2], 255), g: pct(m[3], 255), b: pct(m[4], 255), a: a2 };
  // hsl → rgb
  var hh = (parseFloat(m[2]) % 360) / 360, ss = pct(m[3], 100), ll = pct(m[4], 100);
  var q = ll < 0.5 ? ll * (1 + ss) : ll + ss - ll * ss, p = 2 * ll - q;
  var f = function (t2) {
    if (t2 < 0) t2 += 1;
    if (t2 > 1) t2 -= 1;
    if (t2 < 1 / 6) return p + (q - p) * 6 * t2;
    if (t2 < 1 / 2) return q;
    if (t2 < 2 / 3) return p + (q - p) * (2 / 3 - t2) * 6;
    return p;
  };
  return { r: f(hh + 1 / 3), g: f(hh), b: f(hh - 1 / 3), a: a2 };
}

// entry: DMS clipboard entry {id, isImage, mimeType, preview, size}
function kind(e) {
  if (e.isImage)
    return "image";
  var mime = e.mimeType || "";
  var t = (e.preview || "").trim();
  if (mime === "code/file-list" || mime === "text/uri-list" && t.startsWith("file://"))
    return "path";
  if (urlRe.test(t))
    return "url";
  if (emailRe.test(t))
    return "email";
  if (parseColor(t))
    return "color";
  if (pathRe.test(t))
    return "path";
  if (codeRe.test(t))
    return "code";
  return "text";
}

function rgbLabel(c) {
  var r = Math.round(c.r * 255), g = Math.round(c.g * 255), b = Math.round(c.b * 255);
  return c.a < 1 ? "rgb(" + r + " " + g + " " + b + " / " + Math.round(c.a * 100) + "%)" : "rgb(" + r + " " + g + " " + b + ")";
}

function age(ts) {
  var s = Math.max(0, (Date.now() - Date.parse(ts)) / 1000);
  if (s < 60) return "just now";
  if (s < 3600) return Math.floor(s / 60) + " min ago";
  if (s < 86400) return Math.floor(s / 3600) + " hr ago";
  if (s < 172800) return "yesterday";
  if (s < 604800) return Math.floor(s / 86400) + " days ago";
  return new Date(Date.parse(ts)).toLocaleDateString();
}

function fmtSize(n) {
  return n < 1024 ? n + " B" : n < 1048576 ? Math.round(n / 1024) + " KiB" : (n / 1048576).toFixed(1) + " MiB";
}

// "[[ image 718 KiB png 1434x801 ]]" → "1434×801 png"
function imageLabel(preview) {
  var m = /image\s+\S+\s+\S+\s+(\w+)\s+(\d+)x(\d+)/.exec(preview || "");
  return m ? m[2] + "×" + m[3] + " " + m[1] : "image";
}
