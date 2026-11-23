// transform: point-by-point shape morphs, their eligibility and fallbacks.
#import "/lib.typ": *
#import themes.simple: *

#show: simple-theme.with(aspect-ratio: "16-9")

#let sc = touying-scene
#let blue = rgb("#2563eb")
#let red = rgb("#e11d48")
#let morph(id, objects, timeline: auto) = sc.scene(
  id: id,
  width: 20cm,
  height: 6cm,
  objects: objects,
  timeline: if timeline == auto {
    (sc.transform("a", "b", run-time: 1),)
  } else {
    timeline
  },
)

== Circle to square

#morph("sq", (
  a: sc.obj(at: (5, 3), circle(radius: 1.5cm, fill: blue)),
  b: sc.obj(at: (15, 3), rect(width: 3cm, height: 3cm, fill: red)),
))

== Ring to disc

#let ring = curve(
  fill: blue,
  fill-rule: "non-zero",
  curve.move((0cm, 1.5cm)),
  curve.cubic((0cm, 0.67cm), (0.67cm, 0cm), (1.5cm, 0cm)),
  curve.cubic((2.33cm, 0cm), (3cm, 0.67cm), (3cm, 1.5cm)),
  curve.cubic((3cm, 2.33cm), (2.33cm, 3cm), (1.5cm, 3cm)),
  curve.cubic((0.67cm, 3cm), (0cm, 2.33cm), (0cm, 1.5cm)),
  curve.close(mode: "straight"),
  curve.move((0.8cm, 1.5cm)),
  curve.cubic((0.8cm, 1.89cm), (1.11cm, 2.2cm), (1.5cm, 2.2cm)),
  curve.cubic((1.89cm, 2.2cm), (2.2cm, 1.89cm), (2.2cm, 1.5cm)),
  curve.cubic((2.2cm, 1.11cm), (1.89cm, 0.8cm), (1.5cm, 0.8cm)),
  curve.cubic((1.11cm, 0.8cm), (0.8cm, 1.11cm), (0.8cm, 1.5cm)),
  curve.close(mode: "straight"),
)
#morph("ring", (
  a: sc.obj(at: (5, 3), ring),
  b: sc.obj(at: (15, 3), circle(radius: 1.5cm, fill: red)),
))

== One to three

#morph("split", (
  a: sc.obj(at: (10, 3), rect(width: 4cm, height: 1cm, fill: blue)),
  b: sc.obj(at: (10, 3), stack(
    dir: ltr,
    spacing: 0.5cm,
    circle(radius: 0.6cm, fill: red),
    circle(radius: 0.6cm, fill: red),
    circle(radius: 0.6cm, stroke: 2pt + red),
  )),
))

== Equation

#morph("eq", (
  a: sc.obj(at: (6, 3), text(size: 40pt, $x^2$)),
  b: sc.obj(at: (14, 3), text(size: 40pt, $sin x$)),
))

== Open to closed

#let ax = sc.axes(
  x: (-1, 1),
  y: (-1, 1),
  at: (2, 1),
  size: (4, 4),
  tips: false,
  ticks: false,
)
#morph("open", (
  a: sc.plot(ax, x => x * x, stroke: 2pt + blue),
  b: sc.obj(at: (15, 3), circle(radius: 1.5cm, stroke: 2pt + red)),
))

== Concurrent rotation

#morph(
  "rot",
  (
    a: sc.obj(at: (5, 3), circle(radius: 1.5cm, fill: blue)),
    b: sc.obj(at: (15, 3), rect(width: 3cm, height: 3cm, fill: red)),
  ),
  timeline: (
    sc.play(sc.transform("a", "b"), sc.rotate-by("b", 45deg, run-time: 0.5)),
  ),
)

== Half transparent

#morph(
  "half",
  (
    a: sc.obj(at: (5, 3), circle(radius: 1.5cm, fill: blue)),
    b: sc.obj(at: (15, 3), rect(width: 3cm, height: 3cm, fill: red)),
  ),
  timeline: (
    sc.fade-out("a", run-time: 0.5, rate: x => x / 2),
    sc.transform("a", "b"),
  ),
)

== Strokes under transforms

#morph(
  "strokes",
  (
    a: sc.obj(at: (5, 3), scale(x: 200%, y: 100%, circle(
      radius: 1cm,
      stroke: 2pt + blue,
    ))),
    b: sc.obj(at: (15, 3), rect(width: 3cm, height: 2cm, stroke: 2pt + red)),
    c: sc.obj(at: (5, 3), rotate(30deg, rect(
      width: 2cm,
      height: 2cm,
      stroke: 2pt + blue,
    ))),
    d: sc.obj(at: (15, 3), circle(radius: 1cm, stroke: 2pt + red)),
  ),
  timeline: (sc.play(sc.transform("a", "b"), sc.transform("c", "d")),),
)

== Chains

#morph(
  "chain",
  (
    a: sc.obj(at: (3, 3), circle(radius: 1cm, fill: blue)),
    b: sc.obj(at: (8, 3), rect(width: 2cm, height: 2cm, fill: red)),
    c: sc.obj(at: (13, 3), polygon.regular(
      size: 2.5cm,
      vertices: 3,
      fill: blue,
    )),
    d: sc.obj(at: (17, 3), $a + b$),
    e: sc.obj(at: (17, 1.5), $b + a$),
    f: sc.obj(at: (10, 1), rect(width: 1cm, height: 1cm, fill: green)),
  ),
  timeline: (
    sc.transform("a", "b"),
    sc.transform("b", "c"),
    sc.transform("c", "d", mode: "fade"),
    sc.transform-matching("d", "e"),
    sc.transform("e", "f"),
  ),
)

== Latency

#morph("big", (
  a: sc.obj(at: (10, 4), text(size: 28pt, $sum_(k=1)^n k^2$)),
  b: sc.obj(at: (10, 2), text(size: 28pt, $(n(n+1)(2n+1))/6$)),
))

== Stroked parts appear

#morph("ghost", (
  a: sc.obj(at: (10, 3), circle(radius: 1cm, stroke: 3pt + blue)),
  b: sc.obj(at: (10, 3), stack(
    dir: ltr,
    spacing: 1cm,
    circle(radius: 1cm, stroke: 3pt + blue),
    circle(radius: 1cm, stroke: 3pt + blue),
  )),
))
