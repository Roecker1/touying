// Render parity: the terminal state of transformed objects must look the same
// in the PDF (Typst transforms) and in the HTML player (SVG wrapper).
#import "/lib.typ": *
#import themes.simple: *
#import "@preview/cetz:0.5.2"

#show: simple-theme.with(aspect-ratio: "16-9")

#let sc = touying-scene
#import cetz.draw: circle, content, line

== Parity

#sc.scene(
  id: "parity",
  width: 22cm,
  height: 9cm,
  cetz: cetz,
  bounds: ((-6, -3), (6, 3)),
  objects: (
    group: sc.cetz-obj({
      circle((2, 1), radius: .6, stroke: 2pt + blue)
      line((1, 0), (3, 2), stroke: 1.5pt, mark: (end: ">"))
      content((2, -0.25), $a^2 + b^2$)
    }),
    label: sc.obj(at: (-4, 2), [Label *text*]),
  ),
  timeline: (
    sc.play(
      sc.shift("group", (-3, -0.5)),
      sc.rotate-by("group", 90deg),
      sc.scale-by("group", 2),
    ),
    sc.play(
      sc.rotate-by("label", -30deg),
      sc.scale-by("label", 1.5),
      sc.shift("label", (1, -1)),
    ),
  ),
)
