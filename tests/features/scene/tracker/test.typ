// Value trackers: a 2 s dot and a 4 s family of curves (121 samples).
#import "/lib.typ": *
#import themes.simple: *
#import "@preview/cetz:0.5.2"

#show: simple-theme.with(aspect-ratio: "16-9")

#let sc = touying-scene
#import cetz.draw: circle, line

== Trackers

#sc.scene(
  id: "trk",
  width: 22cm,
  height: 9cm,
  cetz: cetz,
  bounds: ((-3, -0.5), (3, 4.5)),
  objects: (
    axes: sc.cetz-obj({
      line((-3, 0), (3, 0))
      line((0, -0.5), (0, 4.5))
    }),
    curve: sc.tracked(
      a: 0.25,
      v => sc.cetz-obj({
        let pts = range(-30, 31).map(i => (i / 10, v.a * calc.pow(i / 10, 2)))
        line(..pts.filter(p => p.at(1) <= 4.4), stroke: blue + 1.5pt)
      }),
    ),
    dot: sc.tracked(
      x: -2,
      v => sc.cetz-obj({
        circle((v.x, 0.25 * v.x * v.x), radius: .1, fill: red, stroke: none)
      }),
    ),
  ),
  timeline: (
    sc.play(sc.set-value("dot", x: 2), run-time: 2),
    sc.click,
    sc.play(sc.set-value("curve", a: 1.5), sc.fade-out("dot"), run-time: 4),
  ),
)
