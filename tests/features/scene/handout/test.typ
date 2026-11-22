// Handout mode shows one representative state per scene.
#import "/lib.typ": *
#import themes.simple: *

#show: simple-theme.with(aspect-ratio: "16-9", config-common(handout: true))

#let sc = touying-scene

== Handout

#let objects = (
  a: sc.obj(at: (2, 1.5), [Alpha]),
  b: sc.obj(at: (5, 1.5), [Beta]),
)
#let timeline = (
  sc.play(sc.fade-in("a"), sc.fade-in("b")),
  sc.click,
  sc.play(sc.fade-out("a"), sc.fade-out("b")),
)

#grid(
  columns: 3,
  gutter: 1em,
  [auto (final state: empty)], [`handout: 1`], [`handout: "start"`],
  rect(sc.scene(width: 7cm, height: 3cm, objects: objects, timeline: timeline)),
  rect(
    sc.scene(
      width: 7cm,
      height: 3cm,
      handout: 1,
      objects: objects,
      timeline: timeline,
    ),
  ),
  rect(
    sc.scene(
      width: 7cm,
      height: 3cm,
      handout: "start",
      objects: objects,
      timeline: timeline,
    ),
  ),
)
