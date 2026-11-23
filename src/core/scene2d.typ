// 2D shapes and graph helpers for touying scenes.
//
// This module only builds descriptors and does the numerics; `scene.typ`
// resolves (draws) them. Everything here is in scene coordinates (numbers,
// y up) unless stated otherwise.
//
// A `shape` object is a list of leaves. Each leaf is drawn as its own Typst
// `curve` made only of cubic segments (lines get their control points at 1/3
// and 2/3) and closed straight. Typst then writes every leaf's SVG path as
// `M 0 0c .. c ..Z`, whatever the coordinates are, so a tracked shape keeps
// its SVG structure while its numbers change and the HTML player can
// interpolate it (see "interpolation contract" in the scene tutorial).

#let _obj-kind = "touying-scene-obj"

#let _is-num(x) = type(x) == int or type(x) == float

#let _finite(v) = (
  _is-num(v)
    and not (type(v) == float and (float.is-nan(v) or float.is-infinite(v)))
)

#let _lerp2(a, b, t) = (
  a.at(0) + (b.at(0) - a.at(0)) * t,
  a.at(1) + (b.at(1) - a.at(1)) * t,
)

// A straight segment as a cubic.
#let _line(a, b) = (a, _lerp2(a, b, 1 / 3), _lerp2(a, b, 2 / 3), b)

// A polyline (list of points) as cubic segments.
#let _polyline(pts) = range(pts.len() - 1).map(i => _line(
  pts.at(i),
  pts.at(i + 1),
))

/// A leaf of a `shape`: a path made of points (polyline) or cubic segments.
///
/// - pts (array): Points `(x, y)` of a polyline, or `none`.
/// - segs (array): Cubic segments `((p0, c1, c2, p1), ..)`, or `none`.
/// - closed (bool): Close the path.
/// - fill (none, color): Fill.
/// - stroke (none, stroke): Stroke.
#let path(
  pts: none,
  segs: none,
  closed: false,
  fill: none,
  stroke: 1pt + black,
) = {
  let segs = if segs != none { segs } else {
    assert(
      type(pts) == array and pts.len() >= 2,
      message: "touying-scene.path: needs `pts` (at least two points) or `segs`.",
    )
    _polyline(pts)
  }
  (segs: segs, closed: closed, fill: fill, stroke: stroke)
}

// A circle leaf: radius is a length (screen size) or a number (scene units).
#let _circle(center, radius, fill: none, stroke: none) = (
  circle: (center, radius),
  closed: true,
  fill: fill,
  stroke: stroke,
)

/// A 2D object made of paths (`path(..)`) and labels, drawn natively (no CeTZ
/// needed). Labels are `(at: (x, y), anchor: alignment, body: content)`.
#let shape(
  paths: (),
  labels: (),
  visible: auto,
  pivot: auto,
  behind: false,
) = (
  kind: _obj-kind,
  type: "shape",
  paths: paths,
  labels: labels,
  visible: visible,
  pivot: pivot,
  behind: behind,
)

/// Several objects (`obj`, `cetz-obj`, `shape`, `group`) drawn as one, e.g. as
/// the result of a `tracked` function. The children cannot be animated
/// separately; their own `visible`, `pivot` and `behind` are ignored.
#let group(..objs, visible: auto, pivot: auto, behind: false) = {
  assert(
    objs.named().len() == 0,
    message: "touying-scene.group: unexpected named arguments "
      + repr(objs.named().keys()),
  )
  for o in objs.pos() {
    assert(
      type(o) == dictionary
        and o.at("kind", default: none) == _obj-kind
        and o.type in ("content", "cetz", "shape", "group"),
      message: "touying-scene.group: children must be obj, cetz-obj, shape or group objects, got "
        + repr(o),
    )
  }
  (
    kind: _obj-kind,
    type: "group",
    children: objs.pos(),
    visible: visible,
    pivot: pivot,
    behind: behind,
  )
}

#let _with-dash(s, dash) = if dash == none or s == none { s } else {
  let s = std.stroke(s)
  std.stroke(
    paint: if s.paint == auto { black } else { s.paint },
    thickness: if s.thickness == auto { 1pt } else { s.thickness },
    dash: dash,
  )
}

// ---------------------------------------------------------------------------
// Axes
// ---------------------------------------------------------------------------

#let _range(r, name) = {
  assert(
    type(r) == array
      and r.len() in (2, 3)
      and r.slice(0, 2).all(_is-num)
      and r.at(1) > r.at(0),
    message: "touying-scene.axes: `"
      + name
      + "` must be (min, max) or (min, max, step) with min < max.",
  )
  let step = r.at(2, default: none)
  assert(
    step == none or (_is-num(step) and step > 0),
    message: "touying-scene.axes: the step of `" + name + "` must be positive.",
  )
  (float(r.at(0)), float(r.at(1)), step)
}

/// Convert axis (data) coordinates to scene coordinates.
#let c2p(ax, p) = {
  let m = ax.map
  (
    m.at.at(0) + (p.at(0) - m.x0) / (m.x1 - m.x0) * m.size.at(0),
    m.at.at(1) + (p.at(1) - m.y0) / (m.y1 - m.y0) * m.size.at(1),
  )
}

#let _ticks(lo, hi, step) = if step == none { () } else {
  let k0 = calc.ceil(lo / step - 1e-9)
  let k1 = calc.floor(hi / step + 1e-9)
  range(int(k0), int(k1) + 1).map(k => k * step)
}

#let _number(v) = {
  let r = calc.round(v, digits: 6)
  if calc.abs(r - calc.round(r)) < 1e-9 { str(int(calc.round(r))) } else {
    str(r)
  }
}

/// Coordinate axes with ticks, numbers and an optional grid.
///
/// - x (array): `(min, max)` or `(min, max, step)` of the horizontal axis.
/// - y (array): The same for the vertical axis.
/// - at (array): Scene coordinates of the bottom-left corner of the plot
///   rectangle.
/// - size (array): Width and height of the plot rectangle in scene units.
/// - numbers (auto, none, array): `auto` labels every tick (except where the
///   axes cross); or an array of values or `(value, content)` pairs, for the
///   x axis only, or a dictionary `(x: .., y: ..)`.
/// - labels (array): Axis labels `(x-label, y-label)`, drawn at the axis ends.
/// - tips (bool): Arrow tips at the positive ends.
/// - grid (bool): Grid lines at the ticks.
/// -> dictionary
#let axes(
  x: (-5, 5, 1),
  y: (-3, 3, 1),
  at: (0, 0),
  size: (10, 6),
  ticks: true,
  numbers: auto,
  labels: (none, none),
  tips: true,
  grid: false,
  stroke: 0.8pt + black,
  grid-stroke: 0.4pt + luma(80%),
  tick-size: 0.12,
  tip-size: 0.22,
  number-size: 0.75em,
  visible: auto,
  pivot: auto,
  behind: false,
) = {
  let (x0, x1, xs) = _range(x, "x")
  let (y0, y1, ys) = _range(y, "y")
  assert(
    type(size) == array and size.len() == 2 and size.all(v => v > 0),
    message: "touying-scene.axes: `size` must be (width, height) in scene units.",
  )
  let ax = (map: (x0: x0, x1: x1, y0: y0, y1: y1, at: at, size: size))
  let p(q) = c2p(ax, q)
  // Each axis line lies at the other axis' 0 if it is in range.
  let ox = if x0 <= 0 and 0 <= x1 { 0.0 } else { x0 }
  let oy = if y0 <= 0 and 0 <= y1 { 0.0 } else { y0 }
  let paths = ()
  let lbls = ()
  let xt = _ticks(x0, x1, xs)
  let yt = _ticks(y0, y1, ys)
  if grid {
    for v in xt {
      paths.push(path(pts: (p((v, y0)), p((v, y1))), stroke: grid-stroke))
    }
    for v in yt {
      paths.push(path(pts: (p((x0, v)), p((x1, v))), stroke: grid-stroke))
    }
  }
  let ts = if tips { tip-size } else { 0 }
  // Axis lines (ending at the tip's base) and tips.
  let (ax0, ay0) = p((x0, oy))
  let (ax1, _) = p((x1, oy))
  paths.push(path(pts: ((ax0, ay0), (ax1 - ts, ay0)), stroke: stroke))
  let (bx0, by0) = p((ox, y0))
  let (_, by1) = p((ox, y1))
  paths.push(path(pts: ((bx0, by0), (bx0, by1 - ts)), stroke: stroke))
  let paint = std.stroke(stroke).paint
  let paint = if paint == auto { black } else { paint }
  if tips {
    paths.push(path(
      pts: (
        (ax1, ay0),
        (ax1 - ts, ay0 + ts * 0.4),
        (ax1 - ts, ay0 - ts * 0.4),
      ),
      closed: true,
      fill: paint,
      stroke: none,
    ))
    paths.push(path(
      pts: (
        (bx0, by1),
        (bx0 - ts * 0.4, by1 - ts),
        (bx0 + ts * 0.4, by1 - ts),
      ),
      closed: true,
      fill: paint,
      stroke: none,
    ))
  }
  if ticks {
    for v in xt {
      let (tx, ty) = p((v, oy))
      paths.push(path(
        pts: ((tx, ty - tick-size / 2), (tx, ty + tick-size / 2)),
        stroke: stroke,
      ))
    }
    for v in yt {
      let (tx, ty) = p((ox, v))
      paths.push(path(
        pts: ((tx - tick-size / 2, ty), (tx + tick-size / 2, ty)),
        stroke: stroke,
      ))
    }
  }
  // Numbers: skip the value where the axes cross.
  let entries(spec, ticks, cross) = if spec == none { () } else if (
    spec == auto
  ) {
    ticks
      .filter(v => calc.abs(v - cross) > 1e-9)
      .map(v => (v, text(size: number-size, $#_number(v)$)))
  } else {
    spec.map(e => if type(e) == array { e } else {
      (e, text(size: number-size, $#_number(e)$))
    })
  }
  let (nx, ny) = if type(numbers) == dictionary {
    (numbers.at("x", default: auto), numbers.at("y", default: auto))
  } else if numbers == auto or numbers == none { (numbers, numbers) } else {
    (numbers, auto)
  }
  let crossing-x = if oy == 0.0 { ox } else { none }
  let crossing-y = if ox == 0.0 { oy } else { none }
  for (v, body) in entries(nx, xt, if crossing-x == none { calc.inf } else {
    crossing-x
  }) {
    let (tx, ty) = p((v, oy))
    lbls.push((at: (tx, ty - tick-size), anchor: center + top, body: body))
  }
  for (v, body) in entries(ny, yt, if crossing-y == none { calc.inf } else {
    crossing-y
  }) {
    let (tx, ty) = p((ox, v))
    lbls.push((at: (tx - tick-size, ty), anchor: right + horizon, body: body))
  }
  let (xl, yl) = labels
  if xl != none {
    lbls.push((at: (ax1 + 0.1, ay0), anchor: left + horizon, body: xl))
  }
  if yl != none {
    lbls.push((at: (bx0 + 0.2, by1), anchor: left + horizon, body: yl))
  }
  (
    shape(
      paths: paths,
      labels: lbls,
      visible: visible,
      pivot: pivot,
      behind: behind,
    )
      + ax
  )
}

// ---------------------------------------------------------------------------
// Clipping (scene coordinates)
// ---------------------------------------------------------------------------

#let _plot-rect(ax) = {
  let m = ax.map
  (
    m.at.at(0),
    m.at.at(1),
    m.at.at(0) + m.size.at(0),
    m.at.at(1) + m.size.at(1),
  )
}

// Liang–Barsky: the part of segment a-b inside the rectangle, or none.
#let _clip-segment(a, b, rect) = {
  let (xmin, ymin, xmax, ymax) = rect
  let (dx, dy) = (b.at(0) - a.at(0), b.at(1) - a.at(1))
  let t0 = 0.0
  let t1 = 1.0
  for (p, q) in (
    (-dx, a.at(0) - xmin),
    (dx, xmax - a.at(0)),
    (-dy, a.at(1) - ymin),
    (dy, ymax - a.at(1)),
  ) {
    if calc.abs(p) < 1e-12 {
      if q < 0 { return none }
    } else {
      let r = q / p
      if p < 0 { t0 = calc.max(t0, r) } else { t1 = calc.min(t1, r) }
    }
  }
  if t0 > t1 + 1e-12 { return none }
  (_lerp2(a, b, t0), _lerp2(a, b, t1), t0 > 1e-12, t1 < 1 - 1e-12)
}

// Split a polyline into the runs visible inside the rectangle.
#let _clip-polyline(pts, rect) = {
  let runs = ()
  let run = ()
  for i in range(pts.len() - 1) {
    let c = _clip-segment(pts.at(i), pts.at(i + 1), rect)
    if c == none {
      if run.len() >= 2 { runs.push(run) }
      run = ()
      continue
    }
    let (a, b, cut-a, cut-b) = c
    if run.len() == 0 or cut-a {
      if run.len() >= 2 { runs.push(run) }
      run = (a, b)
    } else {
      run.push(b)
    }
    if cut-b {
      runs.push(run)
      run = ()
    }
  }
  if run.len() >= 2 { runs.push(run) }
  runs
}

// Sutherland–Hodgman: a polygon clipped to the rectangle.
#let _clip-polygon(pts, rect) = {
  let (xmin, ymin, xmax, ymax) = rect
  let edges = (
    (p => p.at(0) >= xmin, (a, b) => (xmin - a.at(0)) / (b.at(0) - a.at(0))),
    (p => p.at(0) <= xmax, (a, b) => (xmax - a.at(0)) / (b.at(0) - a.at(0))),
    (p => p.at(1) >= ymin, (a, b) => (ymin - a.at(1)) / (b.at(1) - a.at(1))),
    (p => p.at(1) <= ymax, (a, b) => (ymax - a.at(1)) / (b.at(1) - a.at(1))),
  )
  let poly = pts
  for (inside, cut) in edges {
    if poly.len() == 0 { break }
    let out = ()
    for i in range(poly.len()) {
      let cur = poly.at(i)
      let prev = poly.at(i - 1)
      let (ic, ip) = (inside(cur), inside(prev))
      if ic {
        if not ip { out.push(_lerp2(prev, cur, cut(prev, cur))) }
        out.push(cur)
      } else if ip {
        out.push(_lerp2(prev, cur, cut(prev, cur)))
      }
    }
    poly = out
  }
  poly
}

// ---------------------------------------------------------------------------
// Graphs
// ---------------------------------------------------------------------------

#let _domain(ax, domain) = {
  let (a, b) = if domain == auto { (ax.map.x0, ax.map.x1) } else { domain }
  (float(calc.min(a, b)), float(calc.max(a, b)))
}

// Sample points (x, f(x) or none) of f on [a, b], never at a discontinuity.
#let _sample(f, a, b, samples, discontinuities) = {
  let span = b - a
  let delta = 1e-6 * span
  let cuts = discontinuities.filter(d => d > a and d < b).sorted()
  let bounds = (a,) + cuts + (b,)
  let out = () // list of runs-to-be: (x, y | none); gaps as none markers
  for i in range(bounds.len() - 1) {
    let lo = bounds.at(i) + if i > 0 { delta } else { 0 }
    let hi = bounds.at(i + 1) - if i < bounds.len() - 2 { delta } else { 0 }
    if hi <= lo { continue }
    let n = calc.max(2, int(calc.round(samples * (hi - lo) / span)))
    if i > 0 { out.push(none) } // a discontinuity always splits
    for k in range(n) {
      let x = lo + (hi - lo) * k / (n - 1)
      let y = f(x)
      out.push(if _finite(y) { (x, float(y)) } else { none })
    }
  }
  out
}

// Runs of consecutive valid samples.
#let _runs(samples) = {
  let runs = ()
  let run = ()
  for s in samples {
    if s == none {
      if run.len() > 0 { runs.push(run) }
      run = ()
    } else { run.push(s) }
  }
  if run.len() > 0 { runs.push(run) }
  runs
}

/// The graph of `f` on the axes `ax`. `f` may return `none` where it is
/// undefined; `discontinuities` are x values where the graph is split and `f`
/// is never evaluated. The graph is clipped to the plot rectangle.
#let plot(
  ax,
  f,
  domain: auto,
  samples: 128,
  discontinuities: (),
  stroke: 1.5pt + rgb("#2563eb"),
  dash: none,
  visible: auto,
  pivot: auto,
  behind: false,
) = {
  let (a, b) = _domain(ax, domain)
  let rect = _plot-rect(ax)
  let s = _with-dash(stroke, dash)
  let paths = ()
  for run in _runs(_sample(f, a, b, samples, discontinuities)) {
    if run.len() < 2 { continue }
    for pts in _clip-polyline(run.map(q => c2p(ax, q)), rect) {
      paths.push(path(pts: pts, stroke: s))
    }
  }
  shape(paths: paths, visible: visible, pivot: pivot, behind: behind)
}

/// A function of progress in [0, 1] that runs along the graph of `f`, for
/// `move-along`.
#let graph-path(ax, f, domain: auto) = {
  let (a, b) = _domain(ax, domain)
  p => c2p(ax, (a + (b - a) * p, f(a + (b - a) * p)))
}

/// A dot at axis coordinates `p`. `radius` is a length (screen size) or a
/// number (scene units).
#let dot(
  ax,
  p,
  radius: 2.5pt,
  fill: black,
  stroke: none,
  visible: auto,
  pivot: auto,
  behind: false,
) = shape(
  paths: (_circle(c2p(ax, p), radius, fill: fill, stroke: stroke),),
  visible: visible,
  pivot: pivot,
  behind: behind,
)

#let _slope(f, x, df, h) = if df != none { float(df(x)) } else {
  (f(x + h) - f(x - h)) / (2 * h)
}

// A line of `length` (scene units, on screen) through scene point c along the
// data-space direction (1, m).
#let _line-through(ax, c, m, length) = {
  let sx = ax.map.size.at(0) / (ax.map.x1 - ax.map.x0)
  let sy = ax.map.size.at(1) / (ax.map.y1 - ax.map.y0)
  let (dx, dy) = (sx, sy * m)
  let n = calc.sqrt(dx * dx + dy * dy)
  let (ux, uy) = (dx / n * length / 2, dy / n * length / 2)
  ((c.at(0) - ux, c.at(1) - uy), (c.at(0) + ux, c.at(1) + uy))
}

/// The tangent of `f` at `x`, `length` scene units long. `df` is the
/// derivative (optional; otherwise a central difference with step `h`).
#let tangent(
  ax,
  f,
  x,
  length: 2,
  df: none,
  h: 1e-4,
  stroke: 1.2pt + rgb("#ea580c"),
  visible: auto,
  pivot: auto,
  behind: false,
) = {
  let c = c2p(ax, (x, f(x)))
  let m = _slope(f, x, df, h)
  shape(
    paths: (path(pts: _line-through(ax, c, m, length), stroke: stroke),),
    visible: visible,
    pivot: pivot,
    behind: behind,
  )
}

/// The secant of `f` through `x1` and `x2`, `length` scene units long
/// (`auto`: 1 unit beyond each point) and centred between them. `guides: true`
/// adds the Δx and Δy legs and labels.
#let secant(
  ax,
  f,
  x1,
  x2,
  length: auto,
  guides: false,
  labels: ($Delta x$, $Delta y$),
  stroke: 1.2pt + rgb("#ea580c"),
  guide-stroke: 1pt + rgb("#16a34a"),
  visible: auto,
  pivot: auto,
  behind: false,
) = {
  assert(
    x1 != x2,
    message: "touying-scene.secant: x1 and x2 are equal; use `tangent` for the limit.",
  )
  let (y1, y2) = (f(x1), f(x2))
  let p1 = c2p(ax, (x1, y1))
  let p2 = c2p(ax, (x2, y2))
  let mid = _lerp2(p1, p2, 0.5)
  let m = (y2 - y1) / (x2 - x1)
  let length = if length == auto {
    let d = calc.pow(p2.at(0) - p1.at(0), 2) + calc.pow(p2.at(1) - p1.at(1), 2)
    calc.sqrt(d) + 2
  } else { length }
  let paths = (path(pts: _line-through(ax, mid, m, length), stroke: stroke),)
  let lbls = ()
  if guides {
    let corner = c2p(ax, (x2, y1))
    paths.push(path(pts: (p1, corner), stroke: guide-stroke))
    paths.push(path(pts: (corner, p2), stroke: guide-stroke))
    let (lx, ly) = labels
    let below = if y2 >= y1 { center + top } else { center + bottom }
    let side = if x2 >= x1 { left + horizon } else { right + horizon }
    if lx != none {
      let off = if y2 >= y1 { -0.1 } else { 0.1 }
      lbls.push((
        at: (_lerp2(p1, corner, 0.5).at(0), corner.at(1) + off),
        anchor: below,
        body: lx,
      ))
    }
    if ly != none {
      let off = if x2 >= x1 { 0.1 } else { -0.1 }
      lbls.push((
        at: (corner.at(0) + off, _lerp2(corner, p2, 0.5).at(1)),
        anchor: side,
        body: ly,
      ))
    }
  }
  shape(
    paths: paths,
    labels: lbls,
    visible: visible,
    pivot: pivot,
    behind: behind,
  )
}

#let _guide-stroke = std.stroke(
  paint: luma(45%),
  thickness: 0.8pt,
  dash: "dashed",
)

/// A vertical line from the x axis to the point `p` (axis coordinates).
#let v-line(ax, p, stroke: _guide-stroke, visible: auto, behind: false) = {
  let oy = if ax.map.y0 <= 0 and 0 <= ax.map.y1 { 0.0 } else { ax.map.y0 }
  shape(
    paths: (
      path(pts: (c2p(ax, (p.at(0), oy)), c2p(ax, p)), stroke: stroke),
    ),
    visible: visible,
    behind: behind,
  )
}

/// A horizontal line from the y axis to the point `p` (axis coordinates).
#let h-line(ax, p, stroke: _guide-stroke, visible: auto, behind: false) = {
  let ox = if ax.map.x0 <= 0 and 0 <= ax.map.x1 { 0.0 } else { ax.map.x0 }
  shape(
    paths: (
      path(pts: (c2p(ax, (ox, p.at(1))), c2p(ax, p)), stroke: stroke),
    ),
    visible: visible,
    behind: behind,
  )
}

/// The region between `f` and `g` (default: the x axis) over `domain`. Parts
/// where `f < g` use `neg-fill`. Reversed limits draw the same region; where
/// `f` or `g` returns `none` the region is split. Clipped to the plot
/// rectangle.
#let area(
  ax,
  f,
  domain: auto,
  g: none,
  fill: rgb("#2563eb").transparentize(65%),
  neg-fill: auto,
  samples: 64,
  visible: auto,
  pivot: auto,
  behind: false,
) = {
  let (a, b) = _domain(ax, domain)
  let neg = if neg-fill == auto { fill } else { neg-fill }
  let rect = _plot-rect(ax)
  let paths = ()
  if b - a > 1e-12 {
    let g = if g == none { x => 0.0 } else { g }
    let n = calc.max(2, samples)
    let pts = range(n).map(k => {
      let x = a + (b - a) * k / (n - 1)
      let (fy, gy) = (f(x), g(x))
      if _finite(fy) and _finite(gy) { (x, float(fy), float(gy)) } else {
        none
      }
    })
    for run in _runs(pts) {
      if run.len() < 2 { continue }
      // Split into lobes at the crossings of f and g.
      let lobes = ()
      let lobe = (run.first(),)
      for i in range(1, run.len()) {
        let (x0, f0, g0) = run.at(i - 1)
        let (x1, f1, g1) = run.at(i)
        let (d0, d1) = (f0 - g0, f1 - g1)
        if d0 * d1 < 0 {
          let t = d0 / (d0 - d1)
          let xc = x0 + (x1 - x0) * t
          let yc = f0 + (f1 - f0) * t
          let c = (xc, yc, yc)
          lobe.push(c)
          lobes.push(lobe)
          lobe = (c,)
        }
        lobe.push(run.at(i))
      }
      lobes.push(lobe)
      for lobe in lobes {
        if lobe.len() < 2 { continue }
        let mean = lobe.map(((x, fy, gy)) => fy - gy).sum() / lobe.len()
        let poly = (
          lobe.map(((x, fy, gy)) => c2p(ax, (x, fy)))
            + lobe.rev().map(((x, fy, gy)) => c2p(ax, (x, gy)))
        )
        let clipped = _clip-polygon(poly, rect)
        if clipped.len() >= 3 {
          paths.push(path(
            pts: clipped,
            closed: true,
            fill: if mean < 0 { neg } else { fill },
            stroke: none,
          ))
        }
      }
    }
  }
  shape(paths: paths, visible: visible, pivot: pivot, behind: behind)
}

/// Riemann rectangles of `f` over `domain`: `n` rectangles sampled at their
/// left or right edge or midpoint. Rectangles below the axis use `neg-fill`.
#let riemann(
  ax,
  f,
  domain: auto,
  n: 10,
  mode: "left",
  fill: rgb("#2563eb").transparentize(55%),
  neg-fill: auto,
  stroke: 0.5pt + rgb("#1e3a8a"),
  visible: auto,
  pivot: auto,
  behind: false,
) = {
  assert(
    mode in ("left", "right", "mid"),
    message: "touying-scene.riemann: `mode` must be \"left\", \"right\" or \"mid\".",
  )
  assert(
    type(n) == int and n >= 1,
    message: "touying-scene.riemann: `n` must be a positive integer.",
  )
  let (a, b) = _domain(ax, domain)
  let neg = if neg-fill == auto { fill } else { neg-fill }
  let rect = _plot-rect(ax)
  let base = calc.clamp(0.0, ax.map.y0, ax.map.y1)
  let dx = (b - a) / n
  let paths = ()
  for i in range(n) {
    let (xl, xr) = (a + i * dx, a + (i + 1) * dx)
    let xs = if mode == "left" { xl } else if mode == "right" { xr } else {
      (xl + xr) / 2
    }
    let y = f(xs)
    if not _finite(y) { continue }
    let poly = _clip-polygon(
      (
        c2p(ax, (xl, base)),
        c2p(ax, (xr, base)),
        c2p(ax, (xr, y)),
        c2p(ax, (xl, y)),
      ),
      rect,
    )
    if poly.len() >= 3 {
      paths.push(path(
        pts: poly,
        closed: true,
        fill: if y < base { neg } else { fill },
        stroke: stroke,
      ))
    }
  }
  shape(paths: paths, visible: visible, pivot: pivot, behind: behind)
}

// ---------------------------------------------------------------------------
// Annotations (resolved against their target by scene.typ)
// ---------------------------------------------------------------------------

/// A rectangle or circle around the object `of`, at its untransformed layout
/// box (tracked objects: at their initial values). It does not follow later
/// transforms of the target. `buff` is in scene units; `radius` rounds the
/// rectangle's corners (a length or scene units).
#let surround(
  of: none,
  buff: 0.15,
  shape: "rect",
  radius: 0pt,
  stroke: 1.5pt + rgb("#f59e0b"),
  fill: none,
  visible: auto,
  pivot: auto,
  behind: false,
) = {
  assert(
    type(of) == str,
    message: "touying-scene.surround: `of` must name an object.",
  )
  assert(
    shape in ("rect", "circle"),
    message: "touying-scene.surround: `shape` must be \"rect\" or \"circle\".",
  )
  (
    kind: _obj-kind,
    type: "annot",
    annot: "surround",
    of: of,
    params: (
      buff: buff,
      shape: shape,
      radius: radius,
      stroke: stroke,
      fill: fill,
    ),
    visible: visible,
    pivot: pivot,
    behind: behind,
  )
}

/// A curly brace along one side of the object `of` (at its untransformed
/// layout box), with an optional label centred outside it. `buff`, `gap` and
/// `size` (the brace's depth) are in scene units.
#let brace(
  of: none,
  side: bottom,
  label: none,
  buff: 0.1,
  gap: 0.15,
  size: 0.25,
  stroke: 1.2pt + black,
  visible: auto,
  pivot: auto,
  behind: false,
) = {
  assert(
    type(of) == str,
    message: "touying-scene.brace: `of` must name an object.",
  )
  assert(
    side in (top, bottom, left, right),
    message: "touying-scene.brace: `side` must be top, bottom, left or right.",
  )
  (
    kind: _obj-kind,
    type: "annot",
    annot: "brace",
    of: of,
    params: (
      side: side,
      label: label,
      buff: buff,
      gap: gap,
      size: size,
      stroke: stroke,
    ),
    visible: visible,
    pivot: pivot,
    behind: behind,
  )
}

#let _kappa = 0.5522847498307936

// Cubic segments of a circle (scene coordinates).
#let _circle-segs(c, r) = {
  let (cx, cy) = c
  let k = r * _kappa
  (
    ((cx + r, cy), (cx + r, cy + k), (cx + k, cy + r), (cx, cy + r)),
    ((cx, cy + r), (cx - k, cy + r), (cx - r, cy + k), (cx - r, cy)),
    ((cx - r, cy), (cx - r, cy - k), (cx - k, cy - r), (cx, cy - r)),
    ((cx, cy - r), (cx + k, cy - r), (cx + r, cy - k), (cx + r, cy)),
  )
}

// Cubic segments of a rectangle with rounded corners (scene coordinates).
#let _rect-segs(x0, y0, x1, y1, r) = {
  let r = calc.min(r, (x1 - x0) / 2, (y1 - y0) / 2)
  if r <= 1e-9 {
    return _polyline(((x0, y0), (x1, y0), (x1, y1), (x0, y1), (x0, y0)))
  }
  let k = r * _kappa
  (
    _line((x0 + r, y0), (x1 - r, y0)),
    ((x1 - r, y0), (x1 - r + k, y0), (x1, y0 + r - k), (x1, y0 + r)),
    _line((x1, y0 + r), (x1, y1 - r)),
    ((x1, y1 - r), (x1, y1 - r + k), (x1 - r + k, y1), (x1 - r, y1)),
    _line((x1 - r, y1), (x0 + r, y1)),
    ((x0 + r, y1), (x0 + r - k, y1), (x0, y1 - r + k), (x0, y1 - r)),
    _line((x0, y1 - r), (x0, y0 + r)),
    ((x0, y0 + r), (x0, y0 + r - k), (x0 + r - k, y0), (x0 + r, y0)),
  )
}

// A curly brace from `start` along unit vector `dir` (length w), bulging
// towards unit vector `normal` by depth d. Returns (segments, tip).
#let _brace-segs(start, dir, normal, w, d) = {
  let r = calc.min(d, w / 4)
  let p(u, v) = (
    start.at(0) + dir.at(0) * u + normal.at(0) * v,
    start.at(1) + dir.at(1) * u + normal.at(1) * v,
  )
  let h = d / 2
  let m = w / 2
  (
    (
      (p(0, 0), p(0, h), p(r / 2, h), p(r, h)),
      _line(p(r, h), p(m - r, h)),
      (p(m - r, h), p(m - r / 2, h), p(m, h), p(m, d)),
      (p(m, d), p(m, h), p(m + r / 2, h), p(m + r, h)),
      _line(p(m + r, h), p(w - r, h)),
      (p(w - r, h), p(w - r / 2, h), p(w, h), p(w, 0)),
    ),
    p(m, d),
  )
}

// The shape of an annotation around a box (scene coordinates:
// left, right, bottom, top). `u` converts lengths (pt) to scene units.
#let _annot-shape(o, b, u) = {
  let q = o.params
  let to-units(v) = if type(v) == length { v.to-absolute() / 1pt / u } else {
    float(v)
  }
  if o.annot == "surround" {
    let segs = if q.shape == "circle" {
      let r = (
        calc.sqrt(
          calc.pow(b.right - b.left, 2) + calc.pow(b.top - b.bottom, 2),
        )
          / 2
          + q.buff
      )
      _circle-segs(((b.left + b.right) / 2, (b.bottom + b.top) / 2), r)
    } else {
      _rect-segs(
        b.left - q.buff,
        b.bottom - q.buff,
        b.right + q.buff,
        b.top + q.buff,
        to-units(q.radius),
      )
    }
    shape(
      paths: (path(segs: segs, closed: true, fill: q.fill, stroke: q.stroke),),
      visible: o.visible,
      pivot: o.pivot,
      behind: o.behind,
    )
  } else {
    let (start, dir, normal, w, anchor) = if q.side == bottom {
      (
        (b.left, b.bottom - q.buff),
        (1, 0),
        (0, -1),
        b.right - b.left,
        center + top,
      )
    } else if q.side == top {
      (
        (b.left, b.top + q.buff),
        (1, 0),
        (0, 1),
        b.right - b.left,
        center + bottom,
      )
    } else if q.side == left {
      (
        (b.left - q.buff, b.bottom),
        (0, 1),
        (-1, 0),
        b.top - b.bottom,
        right + horizon,
      )
    } else {
      (
        (b.right + q.buff, b.bottom),
        (0, 1),
        (1, 0),
        b.top - b.bottom,
        left + horizon,
      )
    }
    let (segs, tip) = _brace-segs(start, dir, normal, w, q.size)
    let labels = if q.label == none { () } else {
      (
        (
          at: (
            tip.at(0) + normal.at(0) * q.gap,
            tip.at(1) + normal.at(1) * q.gap,
          ),
          anchor: anchor,
          body: q.label,
        ),
      )
    }
    shape(
      paths: (path(segs: segs, stroke: q.stroke),),
      labels: labels,
      visible: o.visible,
      pivot: o.pivot,
      behind: o.behind,
    )
  }
}
