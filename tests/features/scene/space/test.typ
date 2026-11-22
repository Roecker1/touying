// 3D scenes: surface, axes and labels with camera moves; non-commuting
// rotations; a deforming surface under a perspective camera.
#import "/lib.typ": *
#import themes.simple: *

#show: simple-theme.with(aspect-ratio: "16-9")

#let sc = touying-scene

== Surface

#sc.scene(
  id: "surf",
  width: 22cm,
  height: 10cm,
  camera: sc.camera(phi: 65deg, theta: -50deg),
  objects: (
    axes: sc.axes3d(x: (-3, 3), y: (-3, 3), z: (-1.5, 1.8)),
    surf: sc.surface(
      f: (x, y) => calc.sin(x) * calc.cos(y),
      x: (-3, 3),
      y: (-3, 3),
      samples: (20, 20),
      fill: gradient.linear(..color.map.viridis),
      shade: true,
    ),
    peak: sc.label3d((1.57, 0, 1.25), $max$),
    title: sc.obj(at: (0.5cm, 0.4cm), anchor: left + top, $z = sin x cos y$),
  ),
  timeline: (
    sc.play(sc.create("axes"), sc.fade-in("surf"), sc.fade-in("peak")),
    sc.click,
    sc.rotate-camera(by: 90deg, run-time: 3),
    sc.move-camera(phi: 35deg, zoom: 1.2),
  ),
)

== Rotations and deformation

#sc.scene(
  id: "rot",
  width: 22cm,
  height: 10cm,
  camera: sc.camera(phi: 70deg, theta: -60deg),
  objects: (
    axes: sc.axes3d(x: (-2.5, 2.5), y: (-2.5, 2.5), z: (-0.5, 2.5)),
    v: sc.vector3d((0, 0, 0), (0, 2, 0), stroke: 1.6pt + red),
    bowl: sc.tracked(a: 0.15, interpolate: true, v => sc.surface(
      f: (x, y) => v.a * (x * x + y * y),
      x: (-1.5, 1.5),
      y: (-1.5, 1.5),
      samples: (12, 12),
      fill: rgb("#60a5fa"),
      stroke: 0.3pt + white,
      shade: true,
    )),
  ),
  timeline: (
    sc.rotate-3d("v", 90deg, axis: "y", about: (0, 0, 0)),
    sc.rotate-3d("v", 90deg, axis: "x", about: (0, 0, 0)),
    sc.click,
    sc.play(
      sc.set-value("bowl", a: 0.7, run-time: 2),
      sc.move-camera(focal: 9, run-time: 2),
    ),
  ),
)
