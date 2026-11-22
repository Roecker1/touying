// Shared by test.typ and probe.typ: the probe renders the same tracked
// drawings at exact values, as an oracle for the HTML player's interpolation.
#import "/lib.typ": *
#import "@preview/cetz:0.5.2"

#let sc = touying-scene

#let plateau(t) = if t < 0.3 { t / 0.3 * 0.5 } else if t < 0.7 { 0.5 } else {
  0.5 + (t - 0.7) / 0.3 * 0.5
}

#let dot-fn(v) = sc.cetz-obj({
  cetz.draw.circle((v.x, v.y), radius: .15, fill: red, stroke: none)
})

#let wave-fn(v) = sc.cetz-obj({
  cetz.draw.line(
    ..range(0, 101).map(i => (i / 10, 2 + 0.8 * calc.sin(v.k * i / 10))),
    stroke: blue,
  )
})

#let interp-scene(objects, timeline) = sc.scene(
  id: "interp",
  width: 22cm,
  height: 9cm,
  cetz: cetz,
  bounds: ((0, 0), (10, 4)),
  objects: objects,
  timeline: timeline,
)
