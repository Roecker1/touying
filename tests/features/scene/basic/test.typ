#import "/lib.typ": *
#import themes.simple: *
#import "@preview/cetz:0.5.2"

#show: simple-theme.with(aspect-ratio: "16-9")

#let sc = touying-scene
#import cetz.draw: circle, content, line

== Gradient descent

#sc.scene(
  id: "gd",
  width: 22cm,
  height: 7.5cm,
  cetz: cetz,
  bounds: ((-3, -1), (3, 5)),
  alt: "A parabola with a dot rolling to its minimum",
  objects: (
    axes: sc.cetz-obj({
      line((-3, 0), (3, 0), mark: (end: ">"))
      line((0, -1), (0, 5), mark: (end: ">"))
    }),
    curve: sc.cetz-obj({
      line(
        ..range(-22, 23).map(i => (i / 10, calc.pow(i / 10, 2))),
        stroke: blue + 2pt,
      )
    }),
    eq: sc.obj(
      at: (-6, 4),
      anchor: left + horizon,
      visible: false,
      $f(x) = x^2$,
    ),
    eq2: sc.obj(
      at: (-6, 4),
      anchor: left + horizon,
      visible: false,
      $f'(x) = 2x$,
    ),
    dot: sc.tracked(
      visible: false,
      x: -2,
      v => sc.cetz-obj({
        circle((v.x, v.x * v.x), radius: .12, fill: red, stroke: none)
      }),
    ),
  ),
  timeline: (
    sc.play(sc.create("axes"), sc.write("eq"), run-time: 1.5),
    sc.play(sc.create("curve"), rate: "smooth"),
    sc.click,
    sc.play(sc.fade-in("dot", shift: (0, 1))),
    sc.play(sc.set-value("dot", x: 0), run-time: 2),
    sc.wait(.5),
    sc.click,
    sc.play(sc.transform("eq", "eq2")),
  ),
)

#pause

Converges to the minimum.
