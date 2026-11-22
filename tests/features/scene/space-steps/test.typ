// 3D transform steps: an asymmetric tracked polyline, instant updates before
// and after a rotation starts at the same instant, non-commuting rotations
// across a click, and a camera with phi = 350° (literal angles).
#import "/lib.typ": *
#import themes.simple: *

#show: simple-theme.with(aspect-ratio: "16-9")

#let sc = touying-scene

== Steps

#sc.scene(
  id: "steps",
  width: 22cm,
  height: 10cm,
  camera: sc.camera(phi: 350deg, theta: -60deg, zoom: 1.2),
  objects: (
    axes: sc.axes3d(x: (-3, 3), y: (-3, 3), z: (-3, 3), labels: (none,) * 3),
    hook: sc.tracked(s: 1, v => sc.line3d(
      (0, 0, 0),
      (v.s, 0, 0),
      (v.s, 1, 0),
      stroke: 2pt + red,
      subdivide: 1,
    )),
  ),
  timeline: (
    sc.set-value("hook", s: 2, run-time: 0),
    sc.play(
      sc.rotate-3d("hook", 90deg, axis: "y"),
      sc.set-value("hook", s: 3, run-time: 0),
    ),
    sc.click,
    sc.rotate-3d("hook", 90deg, axis: "x"),
    sc.move-camera(phi: 380deg),
  ),
)
