// 3D for touying scenes: geometry kernel, 3D objects, projection and drawing.
//
// The HTML player (touying-exporter, player.js) implements the same
// specification in JavaScript; both sides must stay in sync:
//
// - camera: phi (polar angle from +z, degrees), theta (azimuth, degrees),
//   zoom, ifocal = 1 / focal distance (0 = orthographic), centre (cx, cy, cz);
//   `unit` (pt per world unit) and `at` (scene point of the centre, pt).
// - basis: c = (sinφcosθ, sinφsinθ, cosφ) towards the viewer,
//   right = (−sinθ, cosθ, 0), up = (−cosφcosθ, −cosφsinθ, sinφ).
// - projection of p: q = p − centre, u = q·right, v = q·up, d = q·c,
//   w = 1 − d·ifocal (near plane w ≥ 0.05),
//   x = at.x + u/w·zoom·unit, y = at.y − v/w·zoom·unit.
// - primitives are clipped against the near plane before division, sorted far
//   to near by mean d (ties: object, primitive, sub-index) and drawn with the
//   painter's algorithm. Clip edges and triangle diagonals are never stroked.
// - shading: colour × (0.35 + 0.65·|n·c|) on the 8-bit sRGB channels, with n
//   the normalised world normal of the triangle (none if |n| < 1e-9).

#let near-plane = 0.05
#let _tiny = 1e-9

// ---------------------------------------------------------------------------
// Vectors and affine matrices (3×4, row-major: r00 r01 r02 t0 r10 … t2)
// ---------------------------------------------------------------------------

#let _add(a, b) = (a.at(0) + b.at(0), a.at(1) + b.at(1), a.at(2) + b.at(2))
#let _sub(a, b) = (a.at(0) - b.at(0), a.at(1) - b.at(1), a.at(2) - b.at(2))
#let _mul(a, k) = (a.at(0) * k, a.at(1) * k, a.at(2) * k)
#let _dot(a, b) = a.at(0) * b.at(0) + a.at(1) * b.at(1) + a.at(2) * b.at(2)
#let _cross(a, b) = (
  a.at(1) * b.at(2) - a.at(2) * b.at(1),
  a.at(2) * b.at(0) - a.at(0) * b.at(2),
  a.at(0) * b.at(1) - a.at(1) * b.at(0),
)
#let _len(a) = calc.sqrt(_dot(a, a))

#let mat-identity = (1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0)

// a ∘ b: apply b first, then a.
#let mat-mul(a, b) = {
  let out = ()
  for i in range(3) {
    for j in range(4) {
      let v = (
        a.at(i * 4) * b.at(j)
          + a.at(i * 4 + 1) * b.at(4 + j)
          + a.at(i * 4 + 2) * b.at(8 + j)
      )
      if j == 3 { v += a.at(i * 4 + 3) }
      out.push(v)
    }
  }
  out
}

#let mat-apply(m, p) = (
  m.at(0) * p.at(0) + m.at(1) * p.at(1) + m.at(2) * p.at(2) + m.at(3),
  m.at(4) * p.at(0) + m.at(5) * p.at(1) + m.at(6) * p.at(2) + m.at(7),
  m.at(8) * p.at(0) + m.at(9) * p.at(1) + m.at(10) * p.at(2) + m.at(11),
)

#let mat-translation(v) = (
  1.0,
  0.0,
  0.0,
  float(v.at(0)),
  0.0,
  1.0,
  0.0,
  float(v.at(1)),
  0.0,
  0.0,
  1.0,
  float(v.at(2)),
)

// Rotation by `deg` degrees about the axis through `pivot` (right-handed).
#let mat-rotation(axis, deg, pivot) = {
  let n = _mul(axis, 1 / _len(axis))
  let (x, y, z) = n
  let c = calc.cos(deg * 1deg)
  let s = calc.sin(deg * 1deg)
  let k = 1 - c
  let r = (
    (c + x * x * k, x * y * k - z * s, x * z * k + y * s),
    (y * x * k + z * s, c + y * y * k, y * z * k - x * s),
    (z * x * k - y * s, z * y * k + x * s, c + z * z * k),
  )
  let t = _sub(pivot, r.map(row => _dot(row, pivot)))
  (
    r.at(0).at(0),
    r.at(0).at(1),
    r.at(0).at(2),
    t.at(0),
    r.at(1).at(0),
    r.at(1).at(1),
    r.at(1).at(2),
    t.at(1),
    r.at(2).at(0),
    r.at(2).at(1),
    r.at(2).at(2),
    t.at(2),
  )
}

// The object matrix: steps applied in order, each at its progress e.
#let steps-matrix(steps, progress) = {
  let m = mat-identity
  for (k, st) in steps.enumerate() {
    let e = progress.at(k, default: 0.0)
    if calc.abs(e) < _tiny { continue }
    let s = if st.kind == "rot" {
      mat-rotation(st.axis, st.angle * e, st.pivot)
    } else { mat-translation(_mul(st.vec, e)) }
    m = mat-mul(s, m)
  }
  m
}

// ---------------------------------------------------------------------------
// Camera and projection
// ---------------------------------------------------------------------------

/// A 3D camera for `scene(camera: ..)`, with manim's conventions.
///
/// - phi (angle): Polar angle from the +z axis (0° looks straight down).
/// - theta (angle): Azimuth.
/// - zoom (int, float): Magnification.
/// - focal (none, int, float): Focal distance in world units for perspective;
///   `none` is orthographic.
/// - center (array): The point the camera looks at.
/// - at (auto, array): Where `center` appears in the scene (scene coordinates
///   or lengths); `auto` is the middle of the scene.
/// - unit (auto, length): Length of one world unit at zoom 1; `auto` is the
///   scene unit.
/// -> dictionary
#let camera(
  phi: 70deg,
  theta: -45deg,
  zoom: 1,
  focal: none,
  center: (0, 0, 0),
  at: auto,
  unit: auto,
) = {
  assert(
    focal == none or (type(focal) in (int, float) and focal > 0),
    message: "touying-scene.camera: `focal` must be none or a positive number.",
  )
  assert(zoom > 0, message: "touying-scene.camera: `zoom` must be positive.")
  (
    kind: "touying-scene-camera",
    phi: phi,
    theta: theta,
    zoom: zoom,
    focal: focal,
    center: center,
    at: at,
    unit: unit,
  )
}

#let _deg(a) = if type(a) == angle { a.deg() } else { float(a) }

// The animatable camera values.
#let camera-values(cam) = (
  phi: _deg(cam.phi),
  theta: _deg(cam.theta),
  zoom: float(cam.zoom),
  ifocal: if cam.focal == none { 0.0 } else { 1 / float(cam.focal) },
  cx: float(cam.center.at(0)),
  cy: float(cam.center.at(1)),
  cz: float(cam.center.at(2)),
)

// A view: camera values plus `unit` and `at` (pt).
#let make-view(values, unit, at) = {
  let p = values.phi * 1deg
  let t = values.theta * 1deg
  (
    c: (calc.sin(p) * calc.cos(t), calc.sin(p) * calc.sin(t), calc.cos(p)),
    right: (-calc.sin(t), calc.cos(t), 0.0),
    up: (
      -calc.cos(p) * calc.cos(t),
      -calc.cos(p) * calc.sin(t),
      calc.sin(p),
    ),
    center: (values.cx, values.cy, values.cz),
    ifocal: values.ifocal,
    scale: values.zoom * unit,
    at: at,
  )
}

// Camera coordinates (u, v, d, w) of a world point.
#let to-camera(view, p) = {
  let q = _sub(p, view.center)
  let d = _dot(q, view.c)
  (_dot(q, view.right), _dot(q, view.up), d, 1 - d * view.ifocal)
}

// Screen point (pt in the scene box) of camera coordinates.
#let to-screen(view, cam) = {
  let (u, v, d, w) = cam
  (
    view.at.at(0) + u / w * view.scale,
    view.at.at(1) - v / w * view.scale,
  )
}

// ---------------------------------------------------------------------------
// Paints and materials
// ---------------------------------------------------------------------------

// (hex "#rrggbb", alpha) of a colour.
#let _paint(c) = {
  let c = rgb(c)
  (c.to-hex().slice(0, 7), c.components().at(3) / 100%)
}

// Material: fill/stroke paints, stroke width (pt), point radius (pt),
// arrowhead size (pt), shading.
#let _material(
  fill: none,
  stroke: none,
  radius: 0,
  head: 0,
  shade: false,
) = {
  let (f, fa) = if fill == none { (none, 0.0) } else { _paint(fill) }
  let (s, sa, sw) = if stroke == none { (none, 0.0, 0.0) } else {
    let st = std.stroke(stroke)
    let paint = if st.paint == auto { black } else { st.paint }
    let width = if st.thickness == auto { 1pt } else { st.thickness }
    let (hex, a) = _paint(paint)
    (hex, a, width.to-absolute() / 1pt)
  }
  (
    f: f,
    fa: fa,
    s: s,
    sa: sa,
    sw: sw,
    r: if type(radius) == length { radius.to-absolute() / 1pt } else {
      float(radius)
    },
    h: if type(head) == length { head.to-absolute() / 1pt } else {
      float(head)
    },
    shade: shade,
  )
}

// ---------------------------------------------------------------------------
// Geometry: (pos: flat floats, prims, mats, labels)
//
// prims are compact arrays:
//   ("t", a, b, c, mat, mask)  triangle; mask bits 1 = ab, 2 = bc, 4 = ca stroked
//   ("s", a, b, mat, s0, s1)   segment of a line, s = arc-length fraction
//   ("h", tip, base, mat)      arrowhead (screen-space, shown when drawn)
//   ("p", a, mat)              point
//   ("l", a, label)            label anchor
// ---------------------------------------------------------------------------

#let _empty-geometry = (pos: (), prims: (), mats: (), labels: ())

#let _vec3(p) = {
  assert(
    type(p) == array and p.len() == 3,
    message: "touying-scene: expected a 3D point (x, y, z), got " + repr(p),
  )
  let out = p.map(float)
  assert(
    out.all(x => x == x and calc.abs(x) < 1e300),
    message: "touying-scene: non-finite 3D coordinate " + repr(p),
  )
  out
}

// Builder helpers working on a geometry dictionary.
#let _add-points(g, pts) = {
  let base = calc.quo(g.pos.len(), 3)
  for p in pts { g.pos += _vec3(p) }
  (g, range(base, base + pts.len()))
}

#let _add-mat(g, m) = {
  let i = g.mats.position(x => x == m)
  if i == none {
    g.mats.push(m)
    i = g.mats.len() - 1
  }
  (g, i)
}

// A polyline, tessellated (each edge split into `sub` pieces), with arc
// coordinates for `create`.
#let _add-polyline(g, pts, mat, sub: 1, closed: false) = {
  let pts = pts.map(_vec3)
  if closed { pts.push(pts.first()) }
  let fine = (pts.first(),)
  for i in range(pts.len() - 1) {
    let (a, b) = (pts.at(i), pts.at(i + 1))
    for j in range(1, sub + 1) {
      fine.push(_add(a, _mul(_sub(b, a), j / sub)))
    }
  }
  let lengths = range(fine.len() - 1).map(i => _len(_sub(
    fine.at(i + 1),
    fine.at(i),
  )))
  let total = lengths.sum(default: 0.0)
  let (g, idx) = _add-points(g, fine)
  let acc = 0.0
  for (i, l) in lengths.enumerate() {
    let s0 = if total > _tiny { acc / total } else { i / lengths.len() }
    acc += l
    let s1 = if total > _tiny { acc / total } else { (i + 1) / lengths.len() }
    g.prims.push(("s", idx.at(i), idx.at(i + 1), mat, s0, s1))
  }
  (g, idx)
}

#let _merge(a, b) = {
  let off = calc.quo(a.pos.len(), 3)
  let moff = a.mats.len()
  let loff = a.labels.len()
  let prims = b.prims.map(p => {
    let kind = p.first()
    if kind == "t" {
      (
        "t",
        p.at(1) + off,
        p.at(2) + off,
        p.at(3) + off,
        p.at(4) + moff,
        p.at(5),
      )
    } else if kind == "s" {
      ("s", p.at(1) + off, p.at(2) + off, p.at(3) + moff, p.at(4), p.at(5))
    } else if kind == "h" {
      ("h", p.at(1) + off, p.at(2) + off, p.at(3) + moff)
    } else if kind == "p" {
      ("p", p.at(1) + off, p.at(2) + moff)
    } else { ("l", p.at(1) + off, p.at(2) + loff) }
  })
  (
    pos: a.pos + b.pos,
    prims: a.prims + prims,
    mats: a.mats + b.mats,
    labels: a.labels + b.labels,
  )
}

// ---------------------------------------------------------------------------
// 3D objects
// ---------------------------------------------------------------------------

#let _obj3d(shape, params, visible) = (
  kind: "touying-scene-obj",
  type: "3d",
  shape: shape,
  params: params,
  visible: visible,
  pivot: auto,
  behind: false,
)

/// A point (screen-space radius).
#let point3d(p, radius: 2.5pt, fill: black, visible: auto) = _obj3d(
  "point",
  (p: p, radius: radius, fill: fill),
  visible,
)

/// A polyline through 3D points. Each edge is split into `subdivide` pieces so
/// it interleaves correctly with surfaces in the depth order.
#let line3d(
  ..pts,
  closed: false,
  stroke: 1pt + black,
  subdivide: 16,
  visible: auto,
) = _obj3d(
  "line",
  (pts: pts.pos(), closed: closed, stroke: stroke, subdivide: subdivide),
  visible,
)

/// A parametric curve `t => (x, y, z)`.
#let curve3d(
  fn,
  t: (0, 1),
  samples: 64,
  stroke: 1pt + black,
  subdivide: 1,
  visible: auto,
) = _obj3d(
  "curve",
  (fn: fn, t: t, samples: samples, stroke: stroke, subdivide: subdivide),
  visible,
)

/// An arrow from `from` to `to` (screen-space head).
#let vector3d(
  from,
  to,
  stroke: 1.2pt + black,
  head: 7pt,
  subdivide: 16,
  visible: auto,
) = _obj3d(
  "vector",
  (from: from, to: to, stroke: stroke, head: head, subdivide: subdivide),
  visible,
)

/// A planar convex polygon.
#let polygon3d(..pts, fill: luma(200), stroke: none, visible: auto) = _obj3d(
  "polygon",
  (pts: pts.pos(), fill: fill, stroke: stroke),
  visible,
)

/// A surface: `f: (x, y) => z` over `x`/`y` ranges, or a parametric
/// `fn: (u, v) => (x, y, z)` over `u`/`v` ranges. `fill` is a colour, a
/// gradient (sampled along the height) or a function `(x, y, z) => color`.
/// Cells are split into two triangles; only the mesh lines are stroked.
#let surface(
  f: none,
  fn: none,
  x: (-1, 1),
  y: (-1, 1),
  u: (0, 1),
  v: (0, 1),
  samples: (24, 24),
  fill: rgb("#3b82f6"),
  stroke: 0.3pt + white,
  shade: false,
  visible: auto,
) = {
  assert(
    (f == none) != (fn == none),
    message: "touying-scene.surface: give either `f: (x, y) => z` or `fn: (u, v) => (x, y, z)`.",
  )
  _obj3d(
    "surface",
    (
      f: f,
      fn: fn,
      x: x,
      y: y,
      u: u,
      v: v,
      samples: samples,
      fill: fill,
      stroke: stroke,
      shade: shade,
    ),
    visible,
  )
}

/// Three axes with arrow tips, tick marks every `ticks` units and labels at
/// the ends.
#let axes3d(
  x: (-3, 3),
  y: (-3, 3),
  z: (-2, 2),
  stroke: 0.8pt + black,
  ticks: 1,
  labels: ($x$, $y$, $z$),
  head: 6pt,
  visible: auto,
) = _obj3d(
  "axes",
  (
    x: x,
    y: y,
    z: z,
    stroke: stroke,
    ticks: ticks,
    labels: labels,
    head: head,
  ),
  visible,
)

/// Content anchored at a 3D point, always facing the viewer. By default it is
/// drawn above all 3D geometry; `depth: true` sorts it with the geometry at
/// its anchor's depth.
#let label3d(p, body, depth: false, visible: auto) = _obj3d(
  "label",
  (p: p, body: body, depth: depth),
  visible,
)

/// Several 3D objects as one object (animated together).
#let group3d(..items, visible: auto) = _obj3d(
  "group",
  (items: items.pos()),
  visible,
)

#let is-3d(o) = type(o) == dictionary and o.at("type", default: none) == "3d"

// Geometry of a 3D object. Needs context (lengths).
#let build(o) = {
  let p = o.params
  let g = _empty-geometry
  if o.shape == "point" {
    let (g2, m) = _add-mat(g, _material(fill: p.fill, radius: p.radius))
    let (g3, idx) = _add-points(g2, (p.p,))
    g = g3
    g.prims.push(("p", idx.first(), m))
  } else if o.shape in ("line", "curve") {
    let pts = if o.shape == "line" { p.pts } else {
      let (a, b) = p.t
      range(p.samples + 1).map(i => (p.fn)(a + (b - a) * i / p.samples))
    }
    assert(pts.len() >= 2, message: "touying-scene: a line needs two points.")
    let (g2, m) = _add-mat(g, _material(stroke: p.stroke))
    g = _add-polyline(
      g2,
      pts,
      m,
      sub: p.subdivide,
      closed: p.at("closed", default: false),
    ).first()
  } else if o.shape == "vector" {
    let (g2, m) = _add-mat(g, _material(stroke: p.stroke, head: p.head))
    let (g3, idx) = _add-polyline(g2, (p.from, p.to), m, sub: p.subdivide)
    g = g3
    g.prims.push(("h", idx.last(), idx.at(idx.len() - 2), m))
  } else if o.shape == "polygon" {
    assert(
      p.pts.len() >= 3,
      message: "touying-scene.polygon3d: needs three points.",
    )
    let (g2, m) = _add-mat(g, _material(fill: p.fill, stroke: p.stroke))
    let (g3, idx) = _add-points(g2, p.pts)
    g = g3
    let n = idx.len()
    // Fan triangulation; only the polygon's own edges are stroked.
    for i in range(1, n - 1) {
      // Triangle (a, b, c) = (v0, vi, vi+1): ab = v0–vi, bc = edge, ca = vi+1–v0.
      let mask = (
        (if i == 1 { 1 } else { 0 }) + 2 + (if i == n - 2 { 4 } else { 0 })
      )
      g.prims.push(("t", idx.at(0), idx.at(i), idx.at(i + 1), m, mask))
    }
  } else if o.shape == "surface" {
    let (nu, nv) = p.samples
    let grid = ()
    for i in range(nu + 1) {
      for j in range(nv + 1) {
        let pt = if p.f != none {
          let x = p.x.at(0) + (p.x.at(1) - p.x.at(0)) * i / nu
          let y = p.y.at(0) + (p.y.at(1) - p.y.at(0)) * j / nv
          (x, y, (p.f)(x, y))
        } else {
          (p.fn)(
            p.u.at(0) + (p.u.at(1) - p.u.at(0)) * i / nu,
            p.v.at(0) + (p.v.at(1) - p.v.at(0)) * j / nv,
          )
        }
        grid.push(_vec3(pt))
      }
    }
    let (g2, idx) = _add-points(g, grid)
    g = g2
    let at(i, j) = idx.at(i * (nv + 1) + j)
    let zs = grid.map(q => q.at(2))
    let (z0, z1) = (calc.min(..zs), calc.max(..zs))
    for i in range(nu) {
      for j in range(nv) {
        let (a, b, c, d) = (
          at(i, j),
          at(i + 1, j),
          at(i + 1, j + 1),
          at(i, j + 1),
        )
        let colour = if type(p.fill) == color { p.fill } else {
          let corners = (a, b, c, d).map(k => grid.at(k - idx.first()))
          let mid = _mul(corners.fold((0.0, 0.0, 0.0), _add), 0.25)
          if type(p.fill) == gradient {
            let t = if z1 - z0 > _tiny { (mid.at(2) - z0) / (z1 - z0) } else {
              0.5
            }
            p.fill.sample(t * 100%)
          } else { (p.fill)(..mid) }
        }
        let (g3, m) = _add-mat(g, _material(
          fill: colour,
          stroke: p.stroke,
          shade: p.shade,
        ))
        g = g3
        // a→b→c and c→d→a: the diagonal a–c is the unstroked closing edge.
        g.prims.push(("t", a, b, c, m, 3))
        g.prims.push(("t", c, d, a, m, 3))
      }
    }
  } else if o.shape == "axes" {
    let (g2, m) = _add-mat(g, _material(stroke: p.stroke, head: p.head))
    g = g2
    let ranges = (p.x, p.y, p.z)
    for (k, r) in ranges.enumerate() {
      if r == none { continue }
      let e(t) = range(3).map(i => if i == k { float(t) } else { 0.0 })
      let (g3, idx) = _add-polyline(g, (e(r.at(0)), e(r.at(1))), m, sub: 16)
      g = g3
      g.prims.push(("h", idx.last(), idx.at(idx.len() - 2), m))
      if p.ticks != none {
        let other = calc.rem(k + 1, 3)
        let t = calc.ceil(r.at(0) / p.ticks) * p.ticks
        while t < r.at(1) - p.ticks / 2 {
          if calc.abs(t) > _tiny {
            let a = e(t)
            let off = range(3).map(i => if i == other { 0.08 } else { 0.0 })
            g = _add-polyline(g, (_sub(a, off), _add(a, off)), m).first()
          }
          t += p.ticks
        }
      }
      let lab = p.labels.at(k, default: none)
      if lab != none {
        let (g3, li) = _add-points(g, (e(r.at(1) * 1.08 + 0.15),))
        g = g3
        g.labels.push((body: lab, depth: false))
        g.prims.push(("l", li.first(), g.labels.len() - 1))
      }
    }
  } else if o.shape == "label" {
    let (g2, li) = _add-points(g, (p.p,))
    g = g2
    g.labels.push((body: p.body, depth: p.depth))
    g.prims.push(("l", li.first(), 0))
  } else if o.shape == "group" {
    for item in p.items {
      assert(
        is-3d(item),
        message: "touying-scene.group3d: only 3D objects can be grouped.",
      )
      g = _merge(g, build(item))
    }
  } else {
    panic("touying-scene: unknown 3D shape " + o.shape)
  }
  g
}

// Topology of a geometry: everything but the positions. Tracked 3D objects
// must keep it across values.
#let topology(g) = (
  n: g.pos.len(),
  // Arc fractions of segments follow the positions; they are not structure.
  prims: g.prims.map(p => if p.first() == "s" { p.slice(0, 4) } else { p }),
  mats: g.mats,
  labels: g.labels.len(),
)

#let points(g) = range(calc.quo(g.pos.len(), 3)).map(i => (
  g.pos.at(3 * i),
  g.pos.at(3 * i + 1),
  g.pos.at(3 * i + 2),
))

#let bbox-center(pts) = {
  if pts.len() == 0 { return (0.0, 0.0, 0.0) }
  range(3).map(k => {
    let xs = pts.map(p => p.at(k))
    (calc.min(..xs) + calc.max(..xs)) / 2
  })
}

// ---------------------------------------------------------------------------
// Drawing list (shared by PDF rendering; mirrored by the player)
// ---------------------------------------------------------------------------

#let _hex-rgb(hex) = {
  let c = rgb(hex).components()
  range(3).map(i => int(calc.round(c.at(i) / 100% * 255)))
}

#let _rgb-hex(ch) = rgb(..ch.map(x => calc.clamp(x, 0, 255))).to-hex()

#let shade-hex(hex, world-tri, view) = {
  let (a, b, c) = world-tri
  let n = _cross(_sub(b, a), _sub(c, a))
  let l = _len(n)
  if l < _tiny { return hex }
  let k = 0.35 + 0.65 * calc.abs(_dot(_mul(n, 1 / l), view.c))
  _rgb-hex(_hex-rgb(hex).map(x => int(calc.round(x * k))))
}

// Clip a polygon (camera coordinates, with "stroked" flags of the edge that
// ends at each vertex) against w ≥ near. Returns (points, flags).
#let _clip-polygon(pts, flags) = {
  let out = ()
  let out-flags = ()
  let n = pts.len()
  for i in range(n) {
    let p = pts.at(calc.rem(i + n - 1, n))
    let q = pts.at(i)
    let f = flags.at(i)
    let pin = p.at(3) >= near-plane - _tiny
    let qin = q.at(3) >= near-plane - _tiny
    let cut() = {
      let t = (near-plane - p.at(3)) / (q.at(3) - p.at(3))
      range(4).map(k => p.at(k) + (q.at(k) - p.at(k)) * t)
    }
    if pin and qin {
      out.push(q)
      out-flags.push(f)
    } else if pin and not qin {
      out.push(cut())
      out-flags.push(f)
    } else if not pin and qin {
      out.push(cut())
      out-flags.push(false)
      out.push(q)
      out-flags.push(f)
    }
  }
  // Drop repeated points.
  let pts2 = ()
  let flags2 = ()
  for (i, p) in out.enumerate() {
    if (
      pts2.len() > 0
        and _len(_sub(p.slice(0, 3), pts2.last().slice(0, 3))) < _tiny
    ) {
      flags2.at(flags2.len() - 1) = flags2.last() or out-flags.at(i)
      continue
    }
    pts2.push(p)
    flags2.push(out-flags.at(i))
  }
  if (
    pts2.len() > 1
      and _len(_sub(pts2.first().slice(0, 3), pts2.last().slice(0, 3))) < _tiny
  ) {
    pts2.pop()
    let last-flag = flags2.pop()
    flags2.at(0) = flags2.at(0) or last-flag
  }
  (pts2, flags2)
}

#let _area2(pts) = {
  let s = 0.0
  for i in range(pts.len()) {
    let (a, b) = (pts.at(i), pts.at(calc.rem(i + 1, pts.len())))
    s += a.at(0) * b.at(1) - b.at(0) * a.at(1)
  }
  calc.abs(s) / 2
}

// Build the sorted drawing list of all 3D objects of a scene.
//
// items: array of (geom, matrix, opacity, draw), in declaration order.
// Returns drawables, far to near:
//   (kind: "poly", pts, flags, fill, fa, stroke, sa, sw) — flags[i] stroked
//     edge ending at pts[i]
//   (kind: "line", pts, stroke, sa, sw)
//   (kind: "point", at, r, fill, fa)
//   (kind: "label", at, obj, label, alpha, depth)
#let drawables(view, items) = {
  let list = ()
  for (oi, item) in items.enumerate() {
    let (geom, matrix, opacity, draw) = item
    if opacity <= _tiny { continue }
    let world = points(geom).map(p => mat-apply(matrix, p))
    let cam = world.map(p => to-camera(view, p))
    let partial = calc.clamp(draw, 0, 1)
    for (pi, pr) in geom.prims.enumerate() {
      let kind = pr.first()
      if kind == "t" {
        let (_, a, b, c, mi, mask) = pr
        let m = geom.mats.at(mi)
        let fa = m.fa * opacity * partial
        let sa = m.sa * opacity * partial
        let fill = if m.f != none and m.shade {
          shade-hex(m.f, (world.at(a), world.at(b), world.at(c)), view)
        } else { m.f }
        // flags[i] = stroked edge ending at vertex i: ca→a, ab→b, bc→c.
        let flags = (
          calc.rem(int(mask / 4), 2) == 1,
          calc.rem(mask, 2) == 1,
          calc.rem(int(mask / 2), 2) == 1,
        )
        let tri = (cam.at(a), cam.at(b), cam.at(c))
        let (pts, fl) = if tri.all(q => q.at(3) >= near-plane) {
          (tri, flags)
        } else { _clip-polygon(tri, flags) }
        if pts.len() < 3 { continue }
        let screen = pts.map(q => to-screen(view, q))
        if _area2(screen) < 1e-12 { continue }
        list.push((
          key: (pts.map(q => q.at(2)).sum() / pts.len(), oi, pi, 0),
          kind: "poly",
          pts: screen,
          flags: fl,
          fill: fill,
          fa: fa,
          stroke: m.s,
          sa: sa,
          sw: m.sw,
        ))
      } else if kind == "s" {
        let (_, a, b, mi, s0, s1) = pr
        if partial <= s0 + _tiny { continue }
        let m = geom.mats.at(mi)
        let pb = if partial < s1 {
          let f = (partial - s0) / (s1 - s0)
          to-camera(view, _add(world.at(a), _mul(
            _sub(world.at(b), world.at(a)),
            f,
          )))
        } else { cam.at(b) }
        let pa = cam.at(a)
        let ain = pa.at(3) >= near-plane
        let bin = pb.at(3) >= near-plane
        if not ain and not bin { continue }
        let cut(p, q) = {
          let t = (near-plane - p.at(3)) / (q.at(3) - p.at(3))
          range(4).map(k => p.at(k) + (q.at(k) - p.at(k)) * t)
        }
        let (p, q) = if ain and bin { (pa, pb) } else if ain {
          (pa, cut(pa, pb))
        } else { (cut(pa, pb), pb) }
        let sp = to-screen(view, p)
        let sq = to-screen(view, q)
        let dist = calc.sqrt(
          calc.pow(sp.at(0) - sq.at(0), 2) + calc.pow(sp.at(1) - sq.at(1), 2),
        )
        if dist < 1e-9 { continue }
        list.push((
          key: ((p.at(2) + q.at(2)) / 2, oi, pi, 0),
          kind: "line",
          pts: (sp, sq),
          stroke: m.s,
          sa: m.sa * opacity,
          sw: m.sw,
        ))
      } else if kind == "h" {
        let (_, tip, base, mi) = pr
        if partial < 1 - 1e-6 { continue }
        let (t, b) = (cam.at(tip), cam.at(base))
        if t.at(3) < near-plane or b.at(3) < near-plane { continue }
        let st = to-screen(view, t)
        let sb = to-screen(view, b)
        let dx = st.at(0) - sb.at(0)
        let dy = st.at(1) - sb.at(1)
        let l = calc.sqrt(dx * dx + dy * dy)
        if l < 1e-9 { continue }
        let m = geom.mats.at(mi)
        let (ux, uy) = (dx / l, dy / l)
        let h = m.h
        let back = (st.at(0) - ux * h, st.at(1) - uy * h)
        let pts = (
          st,
          (back.at(0) - uy * h * 0.4, back.at(1) + ux * h * 0.4),
          (back.at(0) + uy * h * 0.4, back.at(1) - ux * h * 0.4),
        )
        list.push((
          key: (t.at(2), oi, pi, 0),
          kind: "poly",
          pts: pts,
          flags: (false, false, false),
          fill: m.s,
          fa: m.sa * opacity,
          stroke: none,
          sa: 0.0,
          sw: 0.0,
        ))
      } else if kind == "p" {
        let (_, a, mi) = pr
        let q = cam.at(a)
        if q.at(3) < near-plane { continue }
        let m = geom.mats.at(mi)
        list.push((
          key: (q.at(2), oi, pi, 0),
          kind: "point",
          at: to-screen(view, q),
          r: m.r,
          fill: m.f,
          fa: m.fa * opacity * partial,
        ))
      } else if kind == "l" {
        let (_, a, li) = pr
        let q = cam.at(a)
        if q.at(3) < near-plane { continue }
        list.push((
          key: (q.at(2), oi, pi, 0),
          kind: "label",
          at: to-screen(view, q),
          obj: oi,
          label: li,
          alpha: opacity * partial,
          depth: geom.labels.at(li).depth,
        ))
      }
    }
  }
  list.sorted(key: d => d.key)
}

// ---------------------------------------------------------------------------
// PDF drawing
// ---------------------------------------------------------------------------

#let _color(hex, a) = {
  let (r, g, b, _) = rgb(hex).components()
  rgb(r, g, b, calc.clamp(a, 0, 1) * 100%)
}

#let _stroke-of(hex, a, w) = if hex == none or w <= 0 { none } else {
  (paint: _color(hex, a), thickness: w * 1pt, cap: "butt", join: "miter")
}

// Draw one drawable (labels via `label-fn(drawable)`).
#let draw-one(d, label-fn) = {
  if d.kind == "poly" {
    let fill = if d.fill == none { none } else { _color(d.fill, d.fa) }
    let stroke = _stroke-of(d.stroke, d.sa, d.sw)
    let pts = d.pts.map(p => (p.at(0) * 1pt, p.at(1) * 1pt))
    let n = pts.len()
    let off = d.flags.filter(f => not f).len()
    if stroke == none or off == 0 {
      place(curve(
        fill: fill,
        stroke: stroke,
        curve.move(pts.first()),
        ..pts.slice(1).map(curve.line),
        curve.close(),
      ))
    } else if off == 1 and n == 3 {
      // Rotate so that the unstroked edge closes the open path.
      let i = d.flags.position(f => not f)
      let order = range(n).map(k => pts.at(calc.rem(i + k, n)))
      place(curve(
        fill: fill,
        stroke: stroke,
        curve.move(order.first()),
        ..order.slice(1).map(curve.line),
      ))
    } else {
      place(curve(
        fill: fill,
        stroke: none,
        curve.move(pts.first()),
        ..pts.slice(1).map(curve.line),
        curve.close(),
      ))
      for i in range(n) {
        if d.flags.at(i) {
          place(curve(
            stroke: stroke,
            curve.move(pts.at(calc.rem(i + n - 1, n))),
            curve.line(pts.at(i)),
          ))
        }
      }
    }
  } else if d.kind == "line" {
    let stroke = _stroke-of(d.stroke, d.sa, d.sw)
    if stroke != none {
      place(curve(
        stroke: stroke,
        curve.move((d.pts.at(0).at(0) * 1pt, d.pts.at(0).at(1) * 1pt)),
        curve.line((d.pts.at(1).at(0) * 1pt, d.pts.at(1).at(1) * 1pt)),
      ))
    }
  } else if d.kind == "point" {
    if d.fill != none and d.r > 0 {
      place(
        dx: (d.at.at(0) - d.r) * 1pt,
        dy: (d.at.at(1) - d.r) * 1pt,
        circle(radius: d.r * 1pt, fill: _color(d.fill, d.fa), stroke: none),
      )
    }
  } else if d.kind == "label" {
    label-fn(d)
  }
}
