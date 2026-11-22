// Manim-style scenes: compile to PDF as usual, or export an animated,
// self-contained HTML file with touying-exporter:
//
//   typst compile examples/scene.typ --root .
//   touying compile examples/scene.typ --root .   (writes examples/scene.html)
#import "/lib.typ": *
#import themes.metropolis: *
#import "@preview/cetz:0.5.2"

#show: metropolis-theme.with(
  aspect-ratio: "16-9",
  config-info(
    title: [Animated scenes in Touying],
    subtitle: [Manim-style animations, scripted in Typst],
    author: [Touying],
  ),
)

#let sc = touying-scene
#import cetz.draw: circle, content, line, rect

#title-slide()

== Fourier series of a square wave

#let square-partial(x, n) = {
  let s = 0
  for k in range(1, int(calc.floor(n)) + 1, step: 2) {
    s += calc.sin(k * x) / k
  }
  4 / calc.pi * s
}

#sc.scene(
  id: "fourier",
  width: 24cm,
  height: 9cm,
  cetz: cetz,
  bounds: ((-3.4, -1.6), (3.4, 1.6)),
  alt: "Partial sums of the Fourier series converge to a square wave",
  objects: (
    axes: sc.cetz-obj({
      line((-3.3, 0), (3.3, 0), mark: (end: ">"), stroke: gray)
      line((0, -1.5), (0, 1.5), mark: (end: ">"), stroke: gray)
    }),
    square: sc.cetz-obj({
      line(
        (-3.14, -1),
        (0, -1),
        (0, 1),
        (3.14, 1),
        stroke: (paint: gray, dash: "dashed"),
      )
    }),
    wave: sc.tracked(n: 1, v => sc.cetz-obj({
      line(
        ..range(-157, 158).map(i => (i / 50, square-partial(i / 50, v.n))),
        stroke: blue + 1.8pt,
      )
    })),
    formula: sc.obj(
      at: (-3.3, 1.45),
      anchor: left + top,
      $f_N (x) = 4 / pi sum_(k "odd", k <= N) (sin k x) / k$,
    ),
  ),
  timeline: (
    sc.play(sc.create("axes"), sc.write("formula"), run-time: 1.2),
    sc.play(sc.create("square"), sc.create("wave")),
    sc.click,
    sc.play(sc.set-value("wave", n: 15), run-time: 4, rate: "linear"),
    sc.click,
    sc.indicate("formula"),
  ),
)

== Gradient descent

#sc.scene(
  id: "descent",
  width: 24cm,
  height: 9cm,
  cetz: cetz,
  bounds: ((-3, -0.6), (3, 4.6)),
  alt: "A ball rolls down a parabola to its minimum",
  objects: (
    curve: sc.cetz-obj({
      line(
        ..range(-21, 22).map(i => (i / 10, calc.pow(i / 10, 2))),
        stroke: blue + 2pt,
      )
    }),
    ball: sc.cetz-obj({
      circle((-2, 4), radius: .14, fill: red, stroke: none)
    }),
    rule: sc.obj(
      at: (-6.5, 3.5),
      anchor: left + horizon,
      $x_(k+1) = x_k - eta f'(x_k)$,
    ),
    rule2: sc.obj(
      at: (-6.5, 3.5),
      anchor: left + horizon,
      $x_(k+1) = x_k - 2 eta x_k$,
    ),
  ),
  timeline: (
    sc.create("curve"),
    sc.play(sc.fade-in("ball", shift: (0, 0.6)), sc.write("rule")),
    sc.click,
    sc.play(
      sc.move-along("ball", t => {
        let x = -2 + 2 * t
        (x, x * x)
      }),
      run-time: 2.5,
    ),
    sc.click,
    sc.play(sc.transform-matching("rule", "rule2")),
  ),
)

#pause

The step size $eta$ controls how fast the iterate approaches the minimum.

== Rotations and scaling

#sc.scene(
  id: "geometry",
  width: 24cm,
  height: 9cm,
  cetz: cetz,
  bounds: ((-4, -2), (4, 2)),
  objects: (
    square: sc.cetz-obj({
      rect(
        (-2.6, -0.6),
        (-1.4, 0.6),
        stroke: 2pt + eastern,
        fill: eastern.lighten(70%),
      )
    }),
    arrow: sc.cetz-obj({
      line((0.5, 0), (2, 0), stroke: 2pt, mark: (end: ">"))
      content((1.25, 0.35), $arrow(v)$)
    }),
    caption: sc.obj(
      at: (0, -1.6),
      [Pivots default to the centre of each object],
    ),
  ),
  timeline: (
    sc.play(sc.fade-in("square"), sc.create("arrow")),
    sc.click,
    sc.play(sc.rotate-by("square", 90deg), sc.rotate-by("arrow", 180deg)),
    sc.play(sc.scale-by("square", 1.5), sc.shift("arrow", (1, 0))),
    sc.write("caption"),
  ),
)
