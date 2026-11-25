.pragma library

// Light syntax colouring for code previews: comments, strings, numbers, common keywords.
// Returns StyledText HTML; plain text is escaped.
var re = /(\/\/[^\n]*|\/\*[\s\S]*?\*\/|<!--[\s\S]*?-->|(?:^|[ \t])#(?![0-9a-fA-F]{3,8}\b)[^\n]*)|("(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*'|`[^`]*`)|\b(\d+(?:\.\d+)?)\b|\b(function|return|const|let|var|if|elif|else|for|while|switch|case|break|continue|class|struct|enum|impl|trait|fn|pub|mod|use|import|from|export|default|def|lambda|try|catch|except|finally|throw|raise|new|delete|async|await|yield|static|void|int|float|double|char|bool|string|true|false|null|nil|None|True|False|self|this|in|of|then|fi|do|done|echo|local|readonly|property|signal)\b/gm;

function esc(t) {
  return t.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

function html(src, c) {
  var out = "", last = 0, m;
  re.lastIndex = 0;
  while ((m = re.exec(src)) !== null) {
    if (m[0] === "") { re.lastIndex++; continue; }
    out += esc(src.slice(last, m.index));
    var color = m[1] ? c.comment : m[2] ? c.string : m[3] ? c.number : c.keyword;
    out += "<font color='" + color + "'>" + esc(m[0]) + "</font>";
    last = m.index + m[0].length;
  }
  out += esc(src.slice(last));
  return out.replace(/\n/g, "<br>");
}
