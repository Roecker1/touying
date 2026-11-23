// Graphs, shape morphs and emphasis in scenes. Compile to PDF as usual, or
// export an animated HTML deck:
//
//   typst compile examples/scene-graphs.typ --root .
//   touying compile examples/scene-graphs.typ --root .   (writes examples/scene-graphs.html)
#import "/lib.typ": *
#import themes.metropolis: *

#show: metropolis-theme.with(
  aspect-ratio: "16-9",
  config-scene(samples-per-second: 12),
  config-info(
    title: [Graphs in Touying scenes],
    subtitle: [Tangents, integrals and morphing shapes, scripted in Typst],
    author: [Touying],
  ),
)

#let sc = touying-scene
#let blue = rgb("#2563eb")
#let orange = rgb("#ea580c")
#let green = rgb("#16a34a")

#title-slide()

== From secant to tangent

#let f(x) = x * x / 2 + 0.5
#let ax = sc.axes(
  x: (-0.5, 3, 1),
  y: (-0.5, 5, 1),
  at: (1, 0.6),
  size: (12, 8.2),
  labels: ($x$, $y$),
)
#let x0 = 1

#sc.scene(
  id: "secant",
  width: 24cm,
  height: 9.5cm,
  alt: "A secant of a parabola turns into its tangent as h shrinks",
  objects: (
    ax: ax,
    graph: sc.plot(ax, f, stroke: 1.8pt + blue),
    sec: sc.tracked(h: 1.5, interpolate: true, v => sc.secant(
      ax,
      f,
      x0,
      x0 + v.h,
      guides: true,
      length: 5,
    )),
    tan: sc.tangent(ax, f, x0, df: x => x, length: 5, stroke: 1.8pt + orange),
    p: sc.dot(ax, (x0, f(x0))),
    formula: sc.tracked(h: 1.5, v => sc.obj(
      at: (14.5, 7.5),
      anchor: left + horizon,
      $(f(1 + h) - f(1)) / h = #calc.round((f(x0 + v.h) - f(x0)) / v.h, digits: 2)$,
    )),
    limit: sc.obj(
      at: (14.5, 5.5),
      anchor: left + horizon,
      $f'(1) = lim_(h -> 0) (f(1 + h) - f(1)) / h = 1$,
    ),
  ),
  timeline: (
    sc.play(sc.create("ax"), sc.create("graph")),
    sc.play(sc.fade-in("p"), sc.fade-in("sec"), sc.fade-in("formula")),
    sc.click,
    sc.play(
      sc.set-value("sec", h: 0.05, run-time: 3),
      sc.set-value("formula", h: 0.05, run-time: 3),
    ),
    sc.click,
    sc.play(sc.transform("sec", "tan", mode: "fade"), sc.write("limit")),
    sc.circumscribe("limit"),
  ),
)

== Signed area

#let g(x) = calc.sin(x)
#let ax2 = sc.axes(
  x: (-0.3, 6.6, 1),
  y: (-1.4, 1.4, 0.5),
  at: (1, 1),
  size: (13, 7),
)

#sc.scene(
  id: "area",
  width: 24cm,
  height: 9.5cm,
  alt: "The area under sin x, positive and negative parts, and Riemann sums",
  objects: (
    ax: ax2,
    graph: sc.plot(ax2, g, stroke: 1.8pt + blue),
    area: sc.area(
      ax2,
      g,
      domain: (0, 6),
      fill: blue.transparentize(60%),
      neg-fill: orange.transparentize(55%),
    ),
    sums: sc.tracked(n: 4, v => sc.riemann(
      ax2,
      g,
      domain: (0, 6),
      n: int(v.n),
      mode: "mid",
      fill: blue.transparentize(70%),
      neg-fill: orange.transparentize(65%),
    )),
    integral: sc.obj(
      at: (15, 7),
      anchor: left + horizon,
      $integral_0^6 sin x dif x = 1 - cos 6 approx 0.04$,
    ),
    brace: sc.brace(of: "integral", label: text(
      size: 0.8em,
    )[positive minus negative]),
  ),
  timeline: (
    sc.play(sc.create("ax"), sc.create("graph")),
    sc.fade-in("area"),
    sc.write("integral"),
    sc.create("brace"),
    sc.click,
    sc.play(sc.fade-out("area"), sc.fade-in("sums")),
    sc.set-value("sums", n: 24, run-time: 3, rate: "linear"),
  ),
)

== A discontinuous graph

#let ax3 = sc.axes(x: (-3, 3, 1), y: (-4, 4, 2), at: (5, 0.75), size: (14, 8))
#sc.scene(
  id: "pole",
  width: 24cm,
  height: 9.5cm,
  objects: (
    ax: ax3,
    hyp: sc.plot(ax3, x => 1 / x, discontinuities: (0,), stroke: 1.8pt + blue),
    root: sc.plot(
      ax3,
      x => if x < 0 { none } else { 2 * calc.sqrt(x) },
      stroke: 1.8pt + green,
    ),
    l1: sc.obj(at: (19.5, 3.4), text(fill: blue, $1 / x$)),
    l2: sc.obj(at: (19.5, 8.1), text(fill: green, $2 sqrt(x)$)),
  ),
  timeline: (
    sc.create("ax"),
    sc.play(sc.create("hyp"), sc.fade-in("l1")),
    sc.click,
    sc.play(sc.transform("hyp", "root"), sc.transform("l1", "l2")),
    sc.flash((5 + 7, 0.75 + 4)),
  ),
)

== Morphing shapes and equations

#sc.scene(
  id: "morph",
  width: 24cm,
  height: 9.5cm,
  alt: "A circle becomes a square, and x squared becomes sine x",
  objects: (
    circle: sc.obj(at: (5, 6.5), circle(radius: 1.8cm, fill: blue)),
    square: sc.obj(at: (12, 6.5), rect(
      width: 3.4cm,
      height: 3.4cm,
      fill: orange,
    )),
    star: sc.obj(at: (19, 6.5), polygon.regular(
      size: 4cm,
      vertices: 5,
      fill: green,
    )),
    sq: sc.obj(at: (8, 2), text(size: 36pt, $x^2$)),
    sin: sc.obj(at: (16, 2), text(size: 36pt, $sin x$)),
  ),
  timeline: (
    sc.play(sc.fade-in("circle"), sc.write("sq")),
    sc.click,
    sc.transform("circle", "square", run-time: 1.5),
    sc.transform("square", "star", run-time: 1.5),
    sc.click,
    sc.transform("sq", "sin", run-time: 1.5),
    sc.wiggle("sin"),
  ),
)
