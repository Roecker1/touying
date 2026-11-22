// 3D scenes: compile to PDF as usual, or export an animated HTML deck in
// which the camera moves smoothly and 3D scenes can be dragged to look around:
//
//   typst compile examples/scene3d.typ --root .
//   touying compile examples/scene3d.typ --root .   (writes examples/scene3d.html)
#import "/lib.typ": *
#import themes.metropolis: *

#show: metropolis-theme.with(
  aspect-ratio: "16-9",
  // Interpolated trackers need few samples.
  config-scene(samples-per-second: 12),
  config-info(
    title: [3D scenes in Touying],
    subtitle: [Surfaces, vectors and camera moves, scripted in Typst],
    author: [Touying],
  ),
)

#let sc = touying-scene

#title-slide()

== A surface from every side

#sc.scene(
  id: "saddle",
  width: 24cm,
  height: 10cm,
  camera: sc.camera(phi: 70deg, theta: -60deg, zoom: 1.3),
  alt: "The surface z = sin x cos y, seen from several sides",
  objects: (
    axes: sc.axes3d(x: (-3.4, 3.4), y: (-3.4, 3.4), z: (-1.6, 2)),
    surf: sc.surface(
      f: (x, y) => calc.sin(x) * calc.cos(y),
      x: (-3, 3),
      y: (-3, 3),
      samples: (24, 24),
      fill: gradient.linear(..color.map.viridis),
      stroke: 0.25pt + white.transparentize(40%),
      shade: true,
    ),
    top: sc.label3d((1.57, 0, 1.35), [max], depth: true),
    formula: sc.obj(
      at: (0.4cm, 0.3cm),
      anchor: left + top,
      $z = sin x cos y$,
    ),
    hint: sc.obj(
      at: (0.4cm, 9.6cm),
      anchor: left + bottom,
      text(size: 0.7em, fill: gray)[drag to look around · 0 resets],
    ),
  ),
  timeline: (
    sc.play(sc.create("axes"), sc.fade-in("formula")),
    sc.play(sc.fade-in("surf"), sc.fade-in("top"), sc.fade-in("hint")),
    sc.click,
    sc.rotate-camera(by: 120deg, run-time: 4),
    sc.click,
    sc.move-camera(phi: 10deg, theta: 0deg, zoom: 1.1, run-time: 2),
  ),
)

== Rotations do not commute

#let red = rgb("#e11d48")
#let blue = rgb("#2563eb")
#let frame(o) = sc.group3d(
  sc.line3d((o - 1.6, 0, 0), (o + 1.6, 0, 0), stroke: 0.6pt + gray),
  sc.line3d((o, -1.6, 0), (o, 1.6, 0), stroke: 0.6pt + gray),
  sc.line3d((o, 0, -1.6), (o, 0, 1.6), stroke: 0.6pt + gray),
  sc.label3d((o, 0, 1.9), $z$),
  sc.label3d((o + 1.9, 0, 0), $x$),
)

#sc.scene(
  id: "commute",
  width: 24cm,
  height: 10cm,
  camera: sc.camera(phi: 65deg, theta: -80deg, zoom: 1.3),
  alt: "Rotating a vector about y then x differs from x then y",
  objects: (
    frames: sc.group3d(frame(-3), frame(3)),
    v1: sc.vector3d((-3, 0, 0), (-3, 1.4, 0), stroke: 1.8pt + red),
    v2: sc.vector3d((3, 0, 0), (3, 1.4, 0), stroke: 1.8pt + blue),
    l1: sc.obj(at: (5.5cm, 0.5cm), anchor: center + top, text(
      fill: red,
    )[first about $y$, then about $x$]),
    l2: sc.obj(at: (18.5cm, 0.5cm), anchor: center + top, text(
      fill: blue,
    )[first about $x$, then about $y$]),
  ),
  timeline: (
    sc.add("frames"),
    sc.add("v1"),
    sc.add("v2"),
    sc.add("l1"),
    sc.add("l2"),
    sc.click,
    sc.play(
      sc.rotate-3d("v1", 90deg, axis: "y", about: (-3, 0, 0)),
      sc.rotate-3d("v2", 90deg, axis: "x", about: (3, 0, 0)),
      run-time: 1.2,
    ),
    sc.play(
      sc.rotate-3d("v1", 90deg, axis: "x", about: (-3, 0, 0)),
      sc.rotate-3d("v2", 90deg, axis: "y", about: (3, 0, 0)),
      run-time: 1.2,
    ),
  ),
)

== A paraboloid under perspective

#sc.scene(
  id: "bowl",
  width: 24cm,
  height: 10cm,
  camera: sc.camera(phi: 68deg, theta: -50deg, zoom: 1.2),
  objects: (
    axes: sc.axes3d(x: (-2.4, 2.4), y: (-2.4, 2.4), z: (-0.3, 2.6)),
    bowl: sc.tracked(a: 0.1, interpolate: true, v => sc.surface(
      f: (x, y) => v.a * (x * x + y * y),
      x: (-1.8, 1.8),
      y: (-1.8, 1.8),
      samples: (16, 16),
      fill: rgb("#60a5fa"),
      stroke: 0.3pt + white,
      shade: true,
    )),
    eq: sc.tracked(a: 0.1, v => sc.obj(
      at: (0.4cm, 0.3cm),
      anchor: left + top,
      $z = #calc.round(v.a, digits: 2) (x^2 + y^2)$,
    )),
  ),
  timeline: (
    sc.play(sc.create("axes"), sc.fade-in("bowl"), sc.fade-in("eq")),
    sc.click,
    sc.play(
      sc.set-value("bowl", a: 0.5, run-time: 3),
      sc.set-value("eq", a: 0.5, run-time: 3),
      sc.move-camera(focal: 10, phi: 60deg, run-time: 3),
    ),
  ),
)
