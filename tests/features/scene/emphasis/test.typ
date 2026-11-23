// Annotations (surround, brace) and emphasis animations (circumscribe,
// flash, focus-on, show-passing-flash, wiggle).
#import "/lib.typ": *
#import themes.simple: *

#show: simple-theme.with(aspect-ratio: "16-9")

#let sc = touying-scene

== Annotations

#sc.scene(
  id: "annot",
  width: 20cm,
  height: 6cm,
  objects: (
    eq: sc.obj(at: (10, 3.5), text(size: 28pt, $f(x) = x^2 + 1$)),
    box: sc.surround(of: "eq", radius: 4pt),
    br: sc.brace(of: "eq", label: [quadratic]),
    ring: sc.surround(of: "eq", shape: "circle", stroke: 1pt + gray),
    side: sc.brace(of: "box", side: right, label: $y$),
  ),
  timeline: (
    sc.play(sc.create("box"), sc.create("br")),
    sc.click,
    sc.play(sc.create("ring"), sc.create("side")),
  ),
)

== Emphasis

#let ax = sc.axes(x: (-3, 3, 1), y: (-1, 4, 1), at: (11, 0.5), size: (8, 5))
#sc.scene(
  id: "emph",
  width: 20cm,
  height: 6cm,
  objects: (
    eq: sc.obj(at: (4, 4), text(size: 28pt, $E = m c^2$)),
    dot: sc.obj(at: (4, 1.5), circle(radius: 0.3cm, fill: blue)),
    ax: ax,
    graph: sc.plot(ax, x => x * x / 2),
    glow: sc.plot(ax, x => x * x / 2, stroke: 4pt + yellow),
    glow2: sc.plot(ax, x => x * x / 2, stroke: 4pt + red),
  ),
  timeline: (
    // Segment 1: the outline is measured before the shift.
    sc.play(sc.shift("eq", (1, 0)), sc.circumscribe("eq")),
    sc.flash("dot"),
    sc.create("glow", run-time: 1),
    sc.click,
    // Segment 2: a lagged circumscribe measures the shifted equation.
    sc.play(
      sc.wiggle("dot"),
      sc.circumscribe("eq", shape: "circle", fade: true),
      lag-ratio: 0.5,
    ),
    sc.focus-on((15, 3)),
    sc.click,
    // Segment 3: passing flashes with two widths, then a custom-rate wiggle.
    sc.show-passing-flash("glow", run-time: 1, rate: "linear"),
    sc.show-passing-flash(
      "glow2",
      time-width: 1.5,
      run-time: 1,
      rate: "linear",
    ),
    sc.wiggle("eq", rate: x => x * x),
  ),
)
