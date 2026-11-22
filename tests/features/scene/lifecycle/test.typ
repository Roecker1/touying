// Two scenes sharing a click boundary, followed by a pause.
// Subslides: 1 = A1 (B before), 2 = A2 + B1, 3 = B2 (A held), 4 = text (both held).
#import "/lib.typ": *
#import themes.simple: *

#show: simple-theme.with(aspect-ratio: "16-9")

#let sc = touying-scene

== Lifecycle

#speaker-note[Notes for the lifecycle slide.]

#sc.scene(
  id: "a",
  width: 10cm,
  height: 3cm,
  objects: (
    x: sc.obj(at: (2, 1.5), [*A*: first]),
    y: sc.obj(at: (7, 1.5), [*A*: second]),
  ),
  timeline: (sc.fade-in("x"), sc.click, sc.fade-in("y", shift: (0, -1))),
)

#sc.scene(
  id: "b",
  width: 10cm,
  height: 3cm,
  objects: (
    x: sc.obj(at: (2, 1.5), [*B*: first]),
    y: sc.obj(at: (7, 1.5), [*B*: second]),
  ),
  timeline: (
    sc.write("x"),
    sc.click,
    sc.play(sc.fade-in("y"), sc.indicate("x")),
  ),
)

#pause

Both scenes are finished.
