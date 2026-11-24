import QtQuick
import "icons.js" as Icons

// Font Awesome SVG tinted via the data URI; Qt caches each (name, color, size) image.
Image {
  id: root
  property string name: ""
  property color color: "white"
  property int size: 16

  readonly property var path: Icons.paths[name]
  readonly property string hex: "#" + [color.r, color.g, color.b].map(v => Math.round(v * 255).toString(16).padStart(2, "0")).join("")

  width: size
  height: size
  sourceSize: Qt.size(size * 2, size * 2)
  fillMode: Image.PreserveAspectFit
  opacity: color.a
  source: path ? "data:image/svg+xml;utf8," + encodeURIComponent(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${path[0]} 512"><path fill="${hex}" d="${path[1]}"/></svg>`) : ""
}
