// Graph helpers: axes, plots with gaps and clipping, dots, tangents, areas,
// Riemann sums and secants, drawn natively (no CeTZ).
#import "/lib.typ": *
#import themes.simple: *

#show: simple-theme.with(aspect-ratio: "16-9")

#let sc = touying-scene
#let f(x) = x * x * x - 3 * x
#let ax = sc.axes(
  x: (-2.5, 2.5, 1),
  y: (-3, 3, 1),
  at: (1, 0.5),
  size: (10, 6),
  labels: ($x$, $y$),
)

// Descriptor checks (pure numerics, no layout needed).
#{
  let ax = sc.axes(x: (-3, 3, 1), y: (-2, 2, 1), at: (0, 0), size: (6, 4))
  let sin-area(d) = sc.area(ax, calc.sin, domain: d, neg-fill: red)
  // Crossings split the region into lobes with their own fill.
  let a = sin-area((-3, 3))
  assert.eq(a.paths.len(), 2)
  assert.eq(a.paths.map(p => p.fill), (red, a.paths.at(1).fill))
  assert(a.paths.at(1).fill != red)
  // Reversed limits draw the same region; equal limits draw nothing.
  assert.eq(sin-area((3, -3)), a)
  assert.eq(sin-area((1, 1)).paths.len(), 0)
  // A gap (none) splits the region.
  let gapped = sc.area(
    ax,
    x => if calc.abs(x) < 0.5 { none } else { 1 },
    domain: (-2, 2),
  )
  assert.eq(gapped.paths.len(), 2)
  // Clipped to the plot rectangle (y <= 2).
  let tall = sc.area(ax, x => 10, domain: (-1, 1))
  assert(tall.paths.first().segs.all(sg => sg.all(q => q.at(1) <= 4 + 1e-9)))
  // Negative rectangles use neg-fill; a none sample omits its rectangle.
  let r = sc.riemann(
    ax,
    x => if x == 0.5 { none } else { x },
    domain: (-2, 2),
    n: 4,
    mode: "mid",
    neg-fill: red,
  )
  assert.eq(r.paths.len(), 3)
  assert.eq(r.paths.filter(p => p.fill == red).len(), 2)
  // Discontinuities split the graph, and f is never evaluated there.
  let inv = sc.plot(ax, x => 1 / x, discontinuities: (0,))
  assert(inv.paths.len() >= 2)
  // A segment with both ends outside, crossing the rectangle, is drawn.
  let steep = sc.plot(ax, x => 100 * x, domain: (-1, 1), samples: 2)
  assert.eq(steep.paths.len(), 1)
  // The canonical encoding: every leaf is cubic segments.
  assert(steep.paths.first().segs.all(sg => sg.len() == 4))
}

== Tangent

#sc.scene(
  id: "tangent",
  width: 12cm,
  height: 7cm,
  objects: (
    ax: ax,
    graph: sc.plot(ax, f),
    t: sc.tracked(x: -2, interpolate: true, v => sc.group(
      sc.tangent(ax, f, v.x, df: x => 3 * x * x - 3),
      sc.dot(ax, (v.x, f(v.x))),
    )),
  ),
  timeline: (
    sc.play(sc.create("ax"), sc.create("graph")),
    sc.fade-in("t"),
    sc.click,
    sc.set-value("t", x: 2, run-time: 2, rate: "linear"),
  ),
)

== Gaps and clipping

#let ax2 = sc.axes(
  x: (-3, 3, 1),
  y: (-4, 4, 2),
  at: (1, 0.5),
  size: (10, 6),
  grid: true,
)
#sc.scene(
  id: "gaps",
  width: 12cm,
  height: 7cm,
  objects: (
    ax: ax2,
    inv: sc.plot(ax2, x => 1 / x, discontinuities: (0,)),
    root: sc.plot(
      ax2,
      x => if x < 0 { none } else { calc.sqrt(x) },
      stroke: 1.5pt + red,
    ),
    // Both ends outside the rectangle, crossing it.
    cross: sc.plot(
      ax2,
      x => 20 * x,
      domain: (-1, 1),
      samples: 2,
      stroke: 1pt + green,
    ),
  ),
  timeline: (),
)

== Areas and sums

#let g(x) = calc.sin(x)
#sc.scene(
  id: "areas",
  width: 12cm,
  height: 7cm,
  objects: (
    ax: sc.axes(
      x: (-4, 4, 1),
      y: (-1.5, 1.5, 0.5),
      at: (1, 0.5),
      size: (10, 6),
    ),
    area: sc.area(
      sc.axes(x: (-4, 4, 1), y: (-1.5, 1.5, 0.5), at: (1, 0.5), size: (10, 6)),
      g,
      domain: (3, -3),
      neg-fill: red.transparentize(60%),
    ),
    sum: sc.riemann(
      sc.axes(x: (-4, 4, 1), y: (-1.5, 1.5, 0.5), at: (1, 0.5), size: (10, 6)),
      x => 0.5 * x,
      domain: (-3, 3),
      n: 6,
      mode: "mid",
      neg-fill: red.transparentize(50%),
    ),
    graph: sc.plot(
      sc.axes(x: (-4, 4, 1), y: (-1.5, 1.5, 0.5), at: (1, 0.5), size: (10, 6)),
      g,
    ),
  ),
  timeline: (),
)

== Secant

#let ax3 = sc.axes(x: (-1, 3, 1), y: (-1, 5, 1), at: (1, 0.5), size: (10, 6))
#sc.scene(
  id: "secant",
  width: 12cm,
  height: 7cm,
  objects: (
    ax: ax3,
    graph: sc.plot(ax3, x => x * x / 2),
    sec: sc.secant(ax3, x => x * x / 2, 1, 2.5, guides: true),
    v: sc.v-line(ax3, (1, 0.5)),
    h: sc.h-line(ax3, (1, 0.5)),
  ),
  timeline: (),
)
