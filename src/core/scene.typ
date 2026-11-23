// Manim-style scenes for touying.
//
// A scene is a fixed-size box holding named objects and a declarative
// timeline of `play`, `wait` and `click` entries. Each `click` starts a new
// segment, and every segment is one touying subslide. A timeline compiler turns
// the declaration into a history-free model (per-object property tracks), which
// drives three things from one source of truth:
//
// - PDF/handout/article output: the state at the end of each segment,
// - the HTML export (`--input touying-scene=html`): every object is wrapped in
//   a labelled box, and a `<touying-scene>` metadata record carries the tracks
//   that the HTML player (touying-exporter) animates,
// - value trackers: objects re-rendered by Typst at sampled times.
//
// Conventions: times are numbers in seconds, numeric coordinates are scene
// coordinates (y up, scaled by the scene unit), lengths are layout distances
// (y down, from the scene's top-left corner), angles are counter-clockwise.

#import "../utils.typ"
#import "animation.typ": touying-fn-wrapper
#import "scene3d.typ" as s3
#import "scene2d.typ" as s2
#import "scene2d.typ": (
  area, axes, brace, c2p, dot, graph-path, group, h-line, path, plot, riemann,
  secant, shape, surround, tangent, v-line,
)
#import "scene3d.typ": (
  axes3d, camera, curve3d, group3d, label3d, line3d, point3d, polygon3d,
  surface, vector3d,
)

#let _schema-version = 1

// ---------------------------------------------------------------------------
// Rate functions (easing)
// ---------------------------------------------------------------------------

#let _sigmoid(x) = 1 / (1 + calc.exp(-x))

#let _smooth(t, inflection: 10.0) = {
  let err = _sigmoid(-inflection / 2)
  calc.min(
    calc.max((_sigmoid(inflection * (t - 0.5)) - err) / (1 - 2 * err), 0),
    1,
  )
}

/// Built-in rate functions, named as in manim. Each maps progress in [0, 1]
/// to eased progress. They are shipped to the HTML player as sampled tables,
/// and Typst evaluates the same tables, so both agree exactly.
#let rate-functions = (
  linear: t => t,
  smooth: t => _smooth(t),
  rush-into: t => 2 * _smooth(t / 2),
  rush-from: t => 2 * _smooth(t / 2 + 0.5) - 1,
  there-and-back: t => _smooth(if t < 0.5 { 2 * t } else { 2 * (1 - t) }),
  ease-in-quad: t => t * t,
  ease-out-quad: t => 1 - (1 - t) * (1 - t),
  ease-in-cubic: t => t * t * t,
  ease-out-cubic: t => 1 - calc.pow(1 - t, 3),
  ease-in-out-cubic: t => if t < 0.5 { 4 * t * t * t } else {
    1 - calc.pow(-2 * t + 2, 3) / 2
  },
  ease-in-out-sine: t => -(calc.cos(calc.pi * t) - 1) / 2,
)

#let _ease-steps = 64

#let _sample-rate(f) = range(_ease-steps + 1).map(i => float(
  f(i / _ease-steps),
))

// Evaluate a sampled rate table at progress p (linear interpolation).
#let _ease-eval(table, p) = {
  let p = calc.clamp(float(p), 0.0, 1.0)
  let x = p * (table.len() - 1)
  let i = calc.min(int(calc.floor(x)), table.len() - 2)
  let f = x - i
  table.at(i) + (table.at(i + 1) - table.at(i)) * f
}

// ---------------------------------------------------------------------------
// Objects
// ---------------------------------------------------------------------------

/// An ordinary content object (text, equation, image, ...).
///
/// - body (content): The content.
/// - at (array): Position of the anchor point: numbers are scene coordinates,
///   lengths are distances from the scene's top-left corner.
/// - anchor (alignment): Which point of the object sits at `at`.
/// - visible (auto, bool): Whether the object is visible when the scene
///   starts. `auto`: hidden if its first animation introduces it (`fade-in`,
///   `create`, `write`, `add`, or the target of `transform`), visible otherwise.
/// - pivot (auto, array): Centre for rotations and scaling; `auto` is the
///   centre of the object's box.
/// -> dictionary
#let obj(
  body,
  at: (0, 0),
  anchor: center + horizon,
  visible: auto,
  pivot: auto,
  behind: false,
) = (
  kind: "touying-scene-obj",
  type: "content",
  body: body,
  at: at,
  anchor: anchor,
  visible: visible,
  pivot: pivot,
  behind: behind,
)

/// A CeTZ object drawn in the scene's shared coordinate system. All CeTZ
/// objects of a scene align, because each one is drawn on a canvas that spans
/// exactly the scene bounds.
///
/// - body (array): CeTZ draw commands, e.g. `{ circle((0, 0)) }`.
/// - visible (auto, bool): Whether the object is visible when the scene
///   starts; see `obj`.
/// - pivot (auto, array): Centre for rotations and scaling in scene
///   coordinates; `auto` is the centre of the drawing's bounding box.
/// -> dictionary
#let cetz-obj(body, visible: auto, pivot: auto, behind: false) = (
  kind: "touying-scene-obj",
  type: "cetz",
  body: body,
  visible: visible,
  pivot: pivot,
  behind: behind,
)

/// An object that depends on numeric values, like manim's `ValueTracker` with
/// `always_redraw`. `fn` receives a dictionary of the current values and
/// returns an `obj` or `cetz-obj`. Change values with `set-value`.
///
/// Example: `tracked(x: 0, v => cetz-obj({ circle((v.x, 0)) }))`
///
/// In the HTML export the object is re-rendered by Typst at sampled values
/// (`config-scene(samples-per-second: ..)`). With `interpolate: true` the
/// player interpolates linearly between samples whose SVG structure matches,
/// so far fewer samples give smooth motion; only use it when the drawing
/// changes continuously with the values (no rounding, thresholds or branches).
///
/// - samples-per-second (auto, int, float): Samples per second for this
///   object in the HTML export; `auto` uses `config-scene(samples-per-second:
///   ..)`. Raise it for objects that cannot interpolate, such as a changing
///   number, without making every other tracker heavier.
/// -> dictionary
#let tracked(
  fn,
  visible: auto,
  pivot: auto,
  interpolate: false,
  behind: false,
  samples-per-second: auto,
  ..values,
) = {
  assert(
    values.pos().len() == 0,
    message: "touying-scene.tracked: values must be named, e.g. `tracked(x: 0, v => ..)`.",
  )
  assert(
    samples-per-second == auto
      or (
        (type(samples-per-second) == int or type(samples-per-second) == float)
          and samples-per-second > 0
      ),
    message: "touying-scene.tracked: `samples-per-second` must be auto or a positive number.",
  )
  (
    samples-per-second: samples-per-second,
    kind: "touying-scene-obj",
    type: "tracked",
    fn: fn,
    values: values.named(),
    visible: visible,
    pivot: pivot,
    interpolate: interpolate,
    behind: behind,
  )
}

// ---------------------------------------------------------------------------
// Timeline entries
// ---------------------------------------------------------------------------

/// Wait for a click: ends the current segment (subslide).
#let click = (kind: "touying-scene-click")

/// Pause the timeline for `duration` seconds.
#let wait(duration) = (kind: "touying-scene-wait", duration: duration)

/// Play animations together.
///
/// - run-time (auto, int, float): Duration in seconds of each animation that
///   does not set its own; `auto` uses `config-scene(run-time: ..)`.
/// - rate (auto, str, function): Rate function for animations that do not set
///   their own.
/// - lag-ratio (int, float): Offset between consecutive animations as a
///   fraction of their run time (0 = simultaneous, 1 = one after another).
/// -> dictionary
#let play(run-time: auto, rate: auto, lag-ratio: 0, ..anims) = {
  assert(
    anims.named().len() == 0,
    message: "touying-scene.play: unexpected named arguments "
      + repr(anims.named().keys()),
  )
  (
    kind: "touying-scene-play",
    anims: anims.pos(),
    run-time: run-time,
    rate: rate,
    lag-ratio: lag-ratio,
  )
}

#let _anim(type, targets, run-time: auto, rate: auto, ..params) = (
  kind: "touying-scene-anim",
  type: type,
  targets: targets,
  run-time: run-time,
  rate: rate,
  params: params.named(),
)

/// Fade an object in, optionally moving it by `shift` while it appears.
#let fade-in(target, shift: none, run-time: auto, rate: auto) = _anim(
  "fade-in",
  (target,),
  shift: shift,
  run-time: run-time,
  rate: rate,
)

/// Fade an object out, optionally moving it by `shift` while it disappears.
#let fade-out(target, shift: none, run-time: auto, rate: auto) = _anim(
  "fade-out",
  (target,),
  shift: shift,
  run-time: run-time,
  rate: rate,
)

/// Draw an object's strokes progressively (other parts fade in).
#let create(target, run-time: auto, rate: auto) = _anim(
  "create",
  (target,),
  run-time: run-time,
  rate: rate,
)

/// Reverse of `create`; the object is invisible afterwards.
#let uncreate(target, run-time: auto, rate: auto) = _anim(
  "uncreate",
  (target,),
  run-time: run-time,
  rate: rate,
)

/// Reveal an object from left to right.
#let write(target, run-time: auto, rate: auto) = _anim(
  "write",
  (target,),
  run-time: run-time,
  rate: rate,
)

/// Reverse of `write`; the object is invisible afterwards.
#let unwrite(target, run-time: auto, rate: auto) = _anim(
  "unwrite",
  (target,),
  run-time: run-time,
  rate: rate,
)

/// Move an object by a vector (scene units or lengths).
#let shift(target, by, run-time: auto, rate: auto) = _anim(
  "shift",
  (target,),
  by: by,
  run-time: run-time,
  rate: rate,
)

/// Move an object's anchor point (its pivot for CeTZ objects) to `pos`.
#let move-to(target, pos, run-time: auto, rate: auto) = _anim(
  "move-to",
  (target,),
  pos: pos,
  run-time: run-time,
  rate: rate,
)

/// Rotate an object counter-clockwise by `angle` (an angle or degrees).
#let rotate-by(target, angle, run-time: auto, rate: auto) = _anim(
  "rotate-by",
  (target,),
  angle: angle,
  run-time: run-time,
  rate: rate,
)

/// Scale an object by `factor` around its pivot.
#let scale-by(target, factor, run-time: auto, rate: auto) = _anim(
  "scale-by",
  (target,),
  factor: factor,
  run-time: run-time,
  rate: rate,
)

/// Move an object's anchor point (pivot for CeTZ objects) along a path:
/// an array of points or a function `t => (x, y)` for `t` in [0, 1].
#let move-along(target, path, samples: 64, run-time: auto, rate: auto) = _anim(
  "move-along",
  (target,),
  path: path,
  samples: samples,
  run-time: run-time,
  rate: rate,
)

/// Briefly enlarge an object to draw attention to it.
#let indicate(target, scale: 1.2, run-time: auto, rate: auto) = _anim(
  "indicate",
  (target,),
  factor: scale,
  run-time: run-time,
  rate: rate,
)

#let _amber = rgb("#f59e0b")

// Emphasis on an object (`target` names it) or at a point (scene
// coordinates): the animation's targets are the object, or none.
#let _emphasis(kind, target, run-time, rate, ..params) = {
  let point = if type(target) == array { target } else { none }
  assert(
    type(target) == str or point != none,
    message: "touying-scene."
      + kind
      + ": the target must be an object name or a point (x, y).",
  )
  _anim(
    kind,
    if point == none { (target,) } else { () },
    run-time: run-time,
    rate: rate,
    point: point,
    ..params,
  )
}

/// Draw a passing outline around an object (manim's `Circumscribe`): a
/// rectangle or circle whose stroke runs around it once. With `fade: true`
/// the outline is drawn in, held and faded out instead. The outline is
/// measured when the animation starts and does not follow later motion.
#let circumscribe(
  target,
  shape: "rect",
  buff: 0.15,
  stroke: 2pt + _amber,
  time-width: 0.3,
  fade: false,
  run-time: auto,
  rate: auto,
) = {
  assert(
    shape in ("rect", "circle"),
    message: "touying-scene.circumscribe: `shape` must be \"rect\" or \"circle\".",
  )
  assert(
    time-width > 0,
    message: "touying-scene.circumscribe: `time-width` must be positive.",
  )
  _emphasis(
    "circumscribe",
    target,
    run-time,
    rate,
    shape: shape,
    buff: buff,
    stroke: stroke,
    time-width: time-width,
    fade: fade,
  )
}

/// Lines flashing outwards around an object or a point (manim's `Flash`).
/// `radius` is where the lines start (`auto`: just outside the object) and
/// `line-length` their length, both in scene units.
#let flash(
  target,
  lines: 12,
  radius: auto,
  line-length: 0.3,
  stroke: 2pt + _amber,
  time-width: 1,
  run-time: auto,
  rate: auto,
) = {
  assert(
    time-width > 0,
    message: "touying-scene.flash: `time-width` must be positive.",
  )
  _emphasis(
    "flash",
    target,
    run-time,
    rate,
    lines: lines,
    radius: radius,
    line-length: line-length,
    stroke: stroke,
    time-width: time-width,
  )
}

/// A spotlight that shrinks onto an object or a point (manim's `FocusOn`).
/// `radius` is its starting radius in scene units (`auto`: the scene's
/// diagonal).
#let focus-on(
  target,
  color: luma(40%).transparentize(70%),
  radius: auto,
  run-time: auto,
  rate: auto,
) = _emphasis(
  "focus-on",
  target,
  run-time,
  rate,
  color: color,
  radius: radius,
)

/// Show only a window of the object's strokes travelling along them (manim's
/// `ShowPassingFlash`); the object is invisible afterwards. Use it on a
/// highlighted copy of a curve. Fills and text are hidden meanwhile.
#let show-passing-flash(target, time-width: 0.3, run-time: auto, rate: auto) = {
  assert(
    time-width > 0,
    message: "touying-scene.show-passing-flash: `time-width` must be positive.",
  )
  _anim(
    "show-passing-flash",
    (target,),
    run-time: run-time,
    rate: rate,
    time-width: time-width,
  )
}

/// Wiggle an object: it rotates back and forth while it briefly grows
/// (manim's `Wiggle`). A custom `rate` must start at 0 and end at 1.
#let wiggle(
  target,
  scale: 1.1,
  angle: 3.6deg,
  n: 6,
  run-time: auto,
  rate: auto,
) = _anim(
  "wiggle",
  (target,),
  run-time: run-time,
  rate: rate,
  factor: scale,
  angle: angle,
  n: n,
)

/// Morph `source` into `target` (like manim's `ReplacementTransform`:
/// `source` is invisible afterwards).
///
/// In the HTML export the outlines morph into each other point by point:
/// paths and glyphs are paired by position, and parts without a partner grow
/// from or shrink to a point. Where that is not possible (another animation
/// of either object at the same time, partially drawn objects, images,
/// gradients, ...) both objects crossfade while moving and scaling between
/// their bounding boxes, as with `mode: "fade"`.
///
/// - mode (auto, str): `auto` morphs shapes where possible; `"shape"` also,
///   but reports a compile error when the timeline rules it out; `"fade"`
///   always crossfades.
#let transform(source, target, mode: auto, run-time: auto, rate: auto) = {
  assert(
    mode in (auto, "shape", "fade"),
    message: "touying-scene.transform: `mode` must be auto, \"shape\" or \"fade\".",
  )
  _anim(
    "transform",
    (source, target),
    run-time: run-time,
    rate: rate,
    mode: mode,
  )
}

/// Morph `source` into `target` symbol by symbol, like manim's
/// `TransformMatchingShapes`: glyphs that occur in both move to their new
/// places, parts marked with the same `key` move as a group, everything else
/// fades. `source` is invisible afterwards. In PDF, the target replaces the
/// source; the rate must start at 0 and end at 1.
#let transform-matching(source, target, run-time: auto, rate: auto) = _anim(
  "transform-matching",
  (source, target),
  run-time: run-time,
  rate: rate,
)

/// Mark part of an object (usually of an equation) as corresponding to the
/// part with the same name in another object, for `transform-matching`:
/// `$f(x) = #key("sq")[$x^2$]$`. Names may contain letters, digits, `-`, `_`.
#let key(name, body) = {
  assert(
    type(name) == str and name.match(regex("^[A-Za-z0-9_-]+$")) != none,
    message: "touying-scene.key: the name may only contain letters, digits, `-` and `_`.",
  )
  [#box(body)#label("tysk-" + name)]
}

/// Animate the values of a `tracked` object, e.g. `set-value("dot", x: 2)`.
#let set-value(target, run-time: auto, rate: auto, ..values) = {
  assert(
    values.pos().len() == 0,
    message: "touying-scene.set-value: values must be named.",
  )
  _anim(
    "set-value",
    (target,),
    values: values.named(),
    run-time: run-time,
    rate: rate,
  )
}

/// Move the 3D camera (like manim's `move_camera`). Angles are taken
/// literally: going from 350° to 10° turns back by 340° (use 370° for the
/// short way).
#let move-camera(
  phi: auto,
  theta: auto,
  zoom: auto,
  focal: auto,
  center: auto,
  run-time: auto,
  rate: auto,
) = _anim(
  "move-camera",
  ("@camera",),
  phi: phi,
  theta: theta,
  zoom: zoom,
  focal: focal,
  center: center,
  run-time: run-time,
  rate: rate,
)

/// Orbit the 3D camera around the vertical axis by `by` (ambient rotation);
/// the rate is linear unless given.
#let rotate-camera(by: 360deg, run-time: auto, rate: auto) = _anim(
  "rotate-camera",
  ("@camera",),
  by: by,
  run-time: run-time,
  rate: rate,
)

/// Rotate a 3D object by `angle` about a world axis (`"x"`, `"y"`, `"z"` or a
/// vector) through `about` (`auto`: the centre of its bounding box).
#let rotate-3d(
  target,
  angle,
  axis: "z",
  about: auto,
  run-time: auto,
  rate: auto,
) = _anim(
  "rotate-3d",
  (target,),
  angle: angle,
  axis: axis,
  about: about,
  run-time: run-time,
  rate: rate,
)

/// Move a 3D object by a world vector `(dx, dy, dz)`.
#let shift-3d(target, by, run-time: auto, rate: auto) = _anim(
  "shift-3d",
  (target,),
  by: by,
  run-time: run-time,
  rate: rate,
)

/// Make an object visible instantly.
#let add(target) = _anim("add", (target,), run-time: 0)

/// Make an object invisible instantly.
#let remove(target) = _anim("remove", (target,), run-time: 0)

// ---------------------------------------------------------------------------
// Geometry
// ---------------------------------------------------------------------------

#let _pt(x) = if type(x) == length {
  x.to-absolute() / 1pt
} else if type(x) == int or type(x) == float {
  float(x)
} else {
  panic("touying-scene: expected a length, got " + repr(x))
}

// Needs context (lengths may be relative to the font size).
#let _make-geometry(spec) = {
  let w = _pt(spec.width)
  let h = _pt(spec.height)
  let ((x0, y0), (x1, y1)) = if spec.bounds == auto {
    let u = _pt(if spec.unit == auto { 1cm } else { spec.unit })
    ((0, 0), (w / u, h / u))
  } else {
    spec.bounds
  }
  assert(
    x1 > x0 and y1 > y0,
    message: "touying-scene: `bounds` must be ((xmin, ymin), (xmax, ymax)).",
  )
  let u = if spec.unit == auto {
    calc.min(w / (x1 - x0), h / (y1 - y0))
  } else { _pt(spec.unit) }
  // The scene box is authoritative: centre the bounds and widen them to it.
  let (cx, cy) = ((x0 + x1) / 2, (y0 + y1) / 2)
  (
    w: w,
    h: h,
    u: u,
    xmin: cx - w / u / 2,
    xmax: cx + w / u / 2,
    ymin: cy - h / u / 2,
    ymax: cy + h / u / 2,
  )
}

#let _coord(geo, v, axis) = {
  if type(v) == int or type(v) == float {
    if axis == 0 { (v - geo.xmin) * geo.u } else { (geo.ymax - v) * geo.u }
  } else if type(v) == ratio {
    (v / 100%) * (if axis == 0 { geo.w } else { geo.h })
  } else if type(v) == length or type(v) == relative {
    _pt(v)
  } else {
    panic("touying-scene: invalid coordinate " + repr(v))
  }
}

// Position (scene coordinates or lengths) -> pt from the scene's top-left.
#let _pos(geo, p) = {
  assert(
    type(p) == array and p.len() == 2,
    message: "touying-scene: expected a position (x, y), got " + repr(p),
  )
  (_coord(geo, p.at(0), 0), _coord(geo, p.at(1), 1))
}

// Vector (scene units or lengths) -> pt, y down.
#let _vec(geo, v) = {
  assert(
    type(v) == array and v.len() == 2,
    message: "touying-scene: expected a vector (dx, dy), got " + repr(v),
  )
  v
    .enumerate()
    .map(((i, c)) => if type(c) == int or type(c) == float {
      if i == 0 { c * geo.u } else { -c * geo.u }
    } else { _pt(c) })
}

#let _align-factors(a) = {
  let x = if a.x == left or a.x == start { 0 } else if (
    a.x == right or a.x == end
  ) { 1 } else if a.x == center { 0.5 } else { 0.5 }
  let y = if a.y == top { 0 } else if a.y == bottom { 1 } else if (
    a.y == horizon
  ) { 0.5 } else { 0.5 }
  (x, y)
}

// ---------------------------------------------------------------------------
// Layers: every object is rendered on a scene-sized box, so all objects share
// one local frame (pt, origin at the scene's top-left corner, y down).
// ---------------------------------------------------------------------------

#let _cetz-canvas(spec, geo, body, extra: none) = {
  let cetz = spec.cetz
  assert(
    cetz != none,
    message: "touying-scene: `cetz-obj` needs the cetz module, e.g. `scene(cetz: cetz, ..)`.",
  )
  cetz.canvas(
    length: geo.u * 1pt,
    padding: 0,
    {
      if extra == none {
        cetz.draw.rect(
          (geo.xmin, geo.ymin),
          (geo.xmax, geo.ymax),
          stroke: none,
          fill: none,
        )
      } else {
        cetz.draw.rect(extra, extra, stroke: none, fill: none)
      }
      body
    },
  )
}

// Bounding box of a CeTZ drawing in scene coordinates, from two canvases that
// each add one corner of the bounds (no introspection needed).
#let _cetz-bbox(spec, geo, body) = {
  let a = measure(_cetz-canvas(spec, geo, body, extra: (geo.xmin, geo.ymax)))
  let b = measure(_cetz-canvas(spec, geo, body, extra: (geo.xmax, geo.ymin)))
  let right = geo.xmin + a.width / 1pt / geo.u
  let bottom = geo.ymax - a.height / 1pt / geo.u
  let left = geo.xmax - b.width / 1pt / geo.u
  let top = geo.ymin + b.height / 1pt / geo.u
  (left: left, right: right, bottom: bottom, top: top)
}

// A length (screen size) or a number of scene units, in pt.
#let _len(geo, v) = if type(v) == length { _pt(v) } else { float(v) * geo.u }

#let _kappa = 0.5522847498307936

// Cubic segments (pt, y down) of a shape leaf.
#let _leaf-segs(geo, leaf) = if "circle" in leaf {
  let (c, r) = leaf.circle
  let (cx, cy) = _pos(geo, c)
  let r = _len(geo, r)
  let k = r * _kappa
  (
    ((cx + r, cy), (cx + r, cy + k), (cx + k, cy + r), (cx, cy + r)),
    ((cx, cy + r), (cx - k, cy + r), (cx - r, cy + k), (cx - r, cy)),
    ((cx - r, cy), (cx - r, cy - k), (cx - k, cy - r), (cx, cy - r)),
    ((cx, cy - r), (cx + k, cy - r), (cx + r, cy - k), (cx + r, cy)),
  )
} else {
  leaf.segs.map(sg => sg.map(q => _pos(geo, q)))
}

#let _stroke-width(st) = if st == none { 0.0 } else {
  let t = stroke(st).thickness
  if t == auto { 1.0 } else { _pt(t) }
}

// Draw a shape: every leaf is its own curve, placed at its first point, with
// cubic segments only and a straight close, so its SVG structure does not
// depend on the coordinates (see scene2d.typ).
#let _resolve-shape(spec, geo, o) = {
  let (x0, y0, x1, y1) = (calc.inf, calc.inf, -calc.inf, -calc.inf)
  let items = ()
  for leaf in o.paths {
    let segs = _leaf-segs(geo, leaf)
    if segs.len() == 0 { continue }
    // Control points bound a cubic (convex hull); pad for miter joins.
    let pad = _stroke-width(leaf.stroke) * 2
    for sg in segs {
      for (x, y) in sg {
        x0 = calc.min(x0, x - pad)
        y0 = calc.min(y0, y - pad)
        x1 = calc.max(x1, x + pad)
        y1 = calc.max(y1, y + pad)
      }
    }
    let (px, py) = segs.first().first()
    let rel(q) = ((q.at(0) - px) * 1pt, (q.at(1) - py) * 1pt)
    let parts = (curve.move((0pt, 0pt)),)
    for sg in segs {
      parts.push(curve.cubic(rel(sg.at(1)), rel(sg.at(2)), rel(sg.at(3))))
    }
    if leaf.closed { parts.push(curve.close(mode: "straight")) }
    items.push(place(
      top + left,
      dx: px * 1pt,
      dy: py * 1pt,
      curve(fill: leaf.fill, stroke: leaf.stroke, ..parts),
    ))
  }
  for l in o.labels {
    let size = measure(l.body)
    let (w, h) = (size.width / 1pt, size.height / 1pt)
    let (ax, ay) = _pos(geo, l.at)
    let (fx, fy) = _align-factors(l.at("anchor", default: center + horizon))
    let (lx, ly) = (ax - w * fx, ay - h * fy)
    x0 = calc.min(x0, lx)
    y0 = calc.min(y0, ly)
    x1 = calc.max(x1, lx + w)
    y1 = calc.max(y1, ly + h)
    items.push(place(top + left, dx: lx * 1pt, dy: ly * 1pt, l.body))
  }
  if x0 > x1 { (x0, y0, x1, y1) = (0.0, 0.0, 0.0, 0.0) }
  (
    layer: box(width: geo.w * 1pt, height: geo.h * 1pt, items.join()),
    bbox: (x: x0, y: y0, w: x1 - x0, h: y1 - y0),
  )
}

// Resolve a (non-tracked) object to its geometry: the layer content plus
// helpers. `o` is an obj, cetz-obj, shape or group dictionary.
#let _resolve(spec, geo, id, o) = {
  assert(
    type(o) == dictionary
      and o.at("kind", default: none) == "touying-scene-obj"
      and o.type in ("content", "cetz", "shape", "group", "annot"),
    message: "touying-scene: object `"
      + id
      + "` must be `obj(..)`, `cetz-obj(..)`, `shape(..)` or `group(..)`, got "
      + repr(o),
  )
  if o.type == "annot" {
    // Measure the target at its untransformed layout (initial values).
    let chain = o.at("chain", default: ()) + (id,)
    assert(
      o.of in spec.objects,
      message: "touying-scene: `"
        + id
        + "` refers to the unknown object `"
        + o.of
        + "`.",
    )
    assert(
      o.of not in chain,
      message: "touying-scene: annotations refer to each other in a cycle: "
        + (chain + (o.of,)).join(" -> "),
    )
    let t = spec.objects.at(o.of)
    let inner = if t.type == "tracked" { (t.fn)(t.values) } else { t }
    assert(
      not s3.is-3d(inner),
      message: "touying-scene: `"
        + id
        + "` cannot annotate the 3D object `"
        + o.of
        + "`.",
    )
    let r = _resolve(
      spec,
      geo,
      o.of,
      if inner.type == "annot" { inner + (chain: chain) } else { inner },
    )
    let b = (r.bbox)()
    let box-scene = (
      left: geo.xmin + b.x / geo.u,
      right: geo.xmin + (b.x + b.w) / geo.u,
      top: geo.ymax - b.y / geo.u,
      bottom: geo.ymax - (b.y + b.h) / geo.u,
    )
    return _resolve(spec, geo, id, s2._annot-shape(o, box-scene, geo.u))
  }
  if o.type in ("shape", "group") {
    let (layer, b) = if o.type == "shape" {
      let r = _resolve-shape(spec, geo, o)
      (r.layer, r.bbox)
    } else {
      let rs = o.children.map(c => _resolve(spec, geo, id, c))
      let boxes = rs.map(r => (r.bbox)())
      let (x0, y0, x1, y1) = (0.0, 0.0, 0.0, 0.0)
      if boxes.len() > 0 {
        x0 = calc.min(..boxes.map(b => b.x))
        y0 = calc.min(..boxes.map(b => b.y))
        x1 = calc.max(..boxes.map(b => b.x + b.w))
        y1 = calc.max(..boxes.map(b => b.y + b.h))
      }
      (
        box(
          width: geo.w * 1pt,
          height: geo.h * 1pt,
          rs.map(r => place(top + left, r.layer)).join(),
        ),
        (x: x0, y: y0, w: x1 - x0, h: y1 - y0),
      )
    }
    let pivot = if o.pivot == auto { (b.x + b.w / 2, b.y + b.h / 2) } else {
      _pos(geo, o.pivot)
    }
    return (
      layer: layer,
      anchor: none,
      pivot: () => pivot,
      bbox: () => b,
    )
  }
  if o.type == "content" {
    let size = measure(o.body, width: geo.w * 1pt)
    let (w, h) = (size.width / 1pt, size.height / 1pt)
    let (ax, ay) = _pos(geo, o.at)
    let (fx, fy) = _align-factors(o.anchor)
    let (x, y) = (ax - w * fx, ay - h * fy)
    let pivot = if o.pivot == auto { (x + w / 2, y + h / 2) } else {
      _pos(geo, o.pivot)
    }
    (
      layer: box(
        width: geo.w * 1pt,
        height: geo.h * 1pt,
        place(
          top + left,
          dx: x * 1pt,
          dy: y * 1pt,
          o.body,
        ),
      ),
      anchor: (ax, ay),
      pivot: () => pivot,
      bbox: () => (x: x, y: y, w: w, h: h),
    )
  } else {
    let canvas = _cetz-canvas(spec, geo, o.body)
    let size = measure(canvas)
    if (
      calc.abs(size.width / 1pt - geo.w) > 0.5
        or calc.abs(size.height / 1pt - geo.h) > 0.5
    ) {
      panic(
        "touying-scene: cetz object `"
          + id
          + "` draws outside the scene bounds ("
          + repr((geo.xmin, geo.ymin))
          + " to "
          + repr((geo.xmax, geo.ymax))
          + "), which would misalign it. Enlarge the scene's `bounds` or keep the drawing inside them.",
      )
    }
    let bbox-scene = () => _cetz-bbox(spec, geo, o.body)
    let pivot = () => if o.pivot == auto {
      let b = bbox-scene()
      _pos(geo, ((b.left + b.right) / 2, (b.bottom + b.top) / 2))
    } else { _pos(geo, o.pivot) }
    (
      layer: box(width: geo.w * 1pt, height: geo.h * 1pt, canvas),
      anchor: none,
      pivot: pivot,
      bbox: () => {
        let b = bbox-scene()
        let (x, y) = _pos(geo, (b.left, b.top))
        (
          x: x,
          y: y,
          w: (b.right - b.left) * geo.u,
          h: (b.top - b.bottom) * geo.u,
        )
      },
    )
  }
}

// Resolve an object (including tracked ones, at the given values).
#let _resolve-at(spec, geo, id, o, values) = {
  if o.type == "tracked" {
    let inner = (o.fn)(values)
    let r = _resolve(spec, geo, id, inner)
    if o.pivot != auto {
      let p = _pos(geo, o.pivot)
      r.pivot = () => p
    }
    r
  } else {
    _resolve(spec, geo, id, o)
  }
}

// The point that `move-to` / `move-along` move: the anchor point for content
// objects, the pivot for CeTZ objects.
#let _handle(r) = if r.anchor != none { r.anchor } else { (r.pivot)() }

// 3D objects: plain 3D objects, or tracked objects that return one.
#let _is3d(o) = (
  s3.is-3d(o) or (o.type == "tracked" and s3.is-3d((o.fn)(o.values)))
)

#let _geom3d(o, values) = if o.type == "tracked" {
  let inner = (o.fn)(values)
  assert(
    s3.is-3d(inner),
    message: "touying-scene: a tracked 3D object must always return a 3D object.",
  )
  s3.build(inner)
} else { s3.build(o) }

#let _anims3d = (
  "fade-in",
  "fade-out",
  "add",
  "remove",
  "create",
  "uncreate",
  "set-value",
  "rotate-3d",
  "shift-3d",
)

#let _axis3d(a) = if a == "x" { (1.0, 0.0, 0.0) } else if a == "y" {
  (0.0, 1.0, 0.0)
} else if a == "z" { (0.0, 0.0, 1.0) } else {
  assert(
    type(a) == array and a.len() == 3 and a.any(x => x != 0),
    message: "touying-scene.rotate-3d: `axis` must be \"x\", \"y\", \"z\" or a non-zero vector.",
  )
  a.map(float)
}

#let _step-progress(st, n) = range(n).map(k => st.at(
  "step:" + str(k),
  default: 0.0,
))

// ---------------------------------------------------------------------------
// Timeline compiler
// ---------------------------------------------------------------------------

#let _props = (
  "opacity",
  "tx",
  "ty",
  "rot",
  "scale",
  "draw",
  "reveal",
  "pass",
)

// Emphasis animations that draw an auxiliary object.
#let _aux-types = ("circumscribe", "flash", "focus-on")

#let _intro-types = (
  "fade-in",
  "create",
  "write",
  "add",
  "show-passing-flash",
)

// Whether the first animation of `id` introduces it (manim semantics: an
// object appears when it is first played in).
#let _introduced(timeline, id) = {
  for e in timeline {
    if e.kind != "touying-scene-play" { continue }
    for a in e.anims {
      if type(a) != dictionary or id not in a.at("targets", default: ()) {
        continue
      }
      return (
        a.type in _intro-types
          or (
            a.type in ("transform", "transform-matching")
              and a.targets.at(1) == id
          )
      )
    }
  }
  false
}

#let _initial-state(o, visible) = (
  opacity: if visible { 1.0 } else { 0.0 },
  tx: 0.0,
  ty: 0.0,
  rot: 0.0,
  scale: 1.0,
  draw: 1.0,
  reveal: 1.0,
  pass: -1.0,
  values: if o.type == "tracked" { o.values } else { (:) },
)

// Normalise a timeline: bare animations become one-animation plays.
#let _normalise(timeline) = {
  assert(
    type(timeline) == array,
    message: "touying-scene: `timeline` must be an array.",
  )
  timeline.map(e => {
    let kind = if type(e) == dictionary { e.at("kind", default: none) } else {
      none
    }
    if kind == "touying-scene-anim" { play(e) } else if (
      kind
        in (
          "touying-scene-play",
          "touying-scene-wait",
          "touying-scene-click",
        )
    ) { e } else {
      panic("touying-scene: invalid timeline entry " + repr(e))
    }
  })
}

#let _count-segments(timeline) = (
  _normalise(timeline).filter(e => e.kind == "touying-scene-click").len() + 1
)

#let _eps = 1e-9

// Arc-length position on a polyline at progress p.
#let _path-at(points, p) = {
  let lengths = ()
  let total = 0.0
  for i in range(points.len() - 1) {
    let (a, b) = (points.at(i), points.at(i + 1))
    let l = calc.sqrt(
      calc.pow(b.at(0) - a.at(0), 2) + calc.pow(b.at(1) - a.at(1), 2),
    )
    lengths.push(l)
    total += l
  }
  if total <= _eps { return points.first() }
  let target = calc.clamp(p, 0, 1) * total
  let acc = 0.0
  for (i, l) in lengths.enumerate() {
    if acc + l >= target - _eps or i == lengths.len() - 1 {
      let f = if l <= _eps { 0 } else { calc.clamp((target - acc) / l, 0, 1) }
      let (a, b) = (points.at(i), points.at(i + 1))
      return (
        a.at(0) + (b.at(0) - a.at(0)) * f,
        a.at(1) + (b.at(1) - a.at(1)) * f,
      )
    }
    acc += l
  }
  points.last()
}

// State of one object at segment-local time t.
// With `left: true`, the limit from the left at t: tracks starting at t
// (including instant updates at t) are not applied yet. With `before-ev`,
// tracks starting exactly at t from that event or later in the timeline are
// not applied (pivots of 3D steps).
#let _state-at(model, seg, id, t, left: false, before-ev: none) = {
  let st = seg.start.at(id)
  for tr in seg.tracks.at(id, default: ()) {
    if t + _eps < tr.t0 { continue }
    if left and tr.t0 >= t - _eps { continue }
    if (
      before-ev != none
        and calc.abs(tr.t0 - t) <= _eps
        and tr.at("ev", default: -1) >= before-ev
    ) { continue }
    let p = if tr.t1 - tr.t0 <= _eps { 1.0 } else {
      calc.clamp((t - tr.t0) / (tr.t1 - tr.t0), 0.0, 1.0)
    }
    let e = _ease-eval(model.rates.at(tr.ease), p)
    if tr.prop == "path" {
      let (x, y) = _path-at(tr.points, e)
      st.tx = x
      st.ty = y
    } else {
      let v = tr.v0 + (tr.v1 - tr.v0) * e
      if tr.prop.starts-with("val:") {
        st.values.insert(tr.prop.slice(4), v)
      } else {
        st.insert(tr.prop, v)
      }
    }
  }
  st
}


// Compile the scene into segments. Needs context (measurements).
#let _compile(spec, geo, config) = {
  let objects = spec.objects
  let ids = objects.keys()
  let default-run-time = config.at("run-time", default: 1)
  let default-rate = config.at("rate", default: "smooth")

  let rates = (:) // name -> sampled table
  let custom-rates = 0
  let state = (:)
  for (id, o) in objects {
    assert(
      type(o) == dictionary
        and o.at("kind", default: none) == "touying-scene-obj",
      message: "touying-scene: object `"
        + id
        + "` must be created with obj, cetz-obj or tracked.",
    )
    let visible = if o.visible == auto {
      not _introduced(_normalise(spec.timeline), id)
    } else { o.visible }
    state.insert(id, _initial-state(o, visible))
  }
  // Auxiliary objects of emphasis animations (`@e1`, ...), allocated before
  // any segment is built so every segment's states know them.
  let aux-list = ()
  for e in _normalise(spec.timeline) {
    if e.kind != "touying-scene-play" { continue }
    for a in e.anims {
      if type(a) == dictionary and a.at("type", default: none) in _aux-types {
        let aid = "@e" + str(aux-list.len() + 1)
        aux-list.push(aid)
        state.insert(aid, _initial-state((type: "shape"), false))
      }
    }
  }
  let aux-seen = 0
  let aux-entries = (:)
  let has-camera = spec.camera != none
  let cam = if has-camera {
    assert(
      type(spec.camera) == dictionary
        and spec.camera.at("kind", default: none) == "touying-scene-camera",
      message: "touying-scene.scene: `camera` must be made with `camera(..)`.",
    )
    state.insert("@camera", (
      opacity: 1.0,
      tx: 0.0,
      ty: 0.0,
      rot: 0.0,
      scale: 1.0,
      draw: 1.0,
      reveal: 1.0,
      values: s3.camera-values(spec.camera),
    ))
    (
      unit: if spec.camera.unit == auto { geo.u } else {
        _pt(spec.camera.unit)
      },
      at: if spec.camera.at == auto { (geo.w / 2, geo.h / 2) } else {
        _pos(geo, spec.camera.at)
      },
    )
  } else { none }
  let is3d = (:)
  for aid in aux-list { is3d.insert(aid, false) }
  for (id, o) in objects {
    is3d.insert(id, _is3d(o))
    if is3d.at(id) {
      assert(
        has-camera,
        message: "touying-scene: the 3D object `"
          + id
          + "` needs `scene(camera: camera(..))`.",
      )
    }
  }
  let steps = (:) // id -> 3D transform steps
  let ev = -1 // event index (timeline order)
  let shape-morphs = () // transform candidates for shape morphing

  let segments = ()
  let seg = (start: state, tracks: (:), morphs: (), duration: 0.0)
  let last-end = (:) // "id/prop" -> end time in the current segment
  let cursor = 0.0

  for entry in _normalise(spec.timeline) {
    if entry.kind == "touying-scene-click" {
      seg.duration = cursor
      seg.insert("end", state)
      segments.push(seg)
      seg = (start: state, tracks: (:), morphs: (), duration: 0.0)
      last-end = (:)
      cursor = 0.0
    } else if entry.kind == "touying-scene-wait" {
      cursor += float(entry.duration)
    } else {
      let play-end = cursor
      for (i, a) in entry.anims.enumerate() {
        assert(
          type(a) == dictionary
            and a.at("kind", default: none) == "touying-scene-anim",
          message: "touying-scene.play: expected animations, got " + repr(a),
        )
        ev += 1
        if a.targets == ("@camera",) {
          assert(
            has-camera,
            message: "touying-scene: `"
              + a.type
              + "` needs `scene(camera: camera(..))`.",
          )
        }
        for t in a.targets {
          if t == "@camera" { continue }
          if is3d.at(t, default: false) {
            assert(
              a.type in _anims3d,
              message: "touying-scene: `"
                + a.type
                + "` does not apply to the 3D object `"
                + t
                + "`. 3D objects support "
                + _anims3d.join(", ")
                + ".",
            )
            assert(
              a.params.at("shift", default: none) == none,
              message: "touying-scene: `"
                + a.type
                + "` with `shift` does not apply to 3D objects; use shift-3d.",
            )
          } else if a.type in ("rotate-3d", "shift-3d") and t in ids {
            panic(
              "touying-scene: `"
                + a.type
                + "` needs a 3D object, `"
                + t
                + "` is not one.",
            )
          }
          assert(
            t in ids,
            message: "touying-scene: unknown object `"
              + str(t)
              + "` in `"
              + a.type
              + "`. Known objects: "
              + ids.join(", "),
          )
        }
        let rt = float(if a.run-time != auto { a.run-time } else if (
          entry.run-time != auto
        ) { entry.run-time } else { default-run-time })
        let rate = if a.rate != auto { a.rate } else if a.type == "indicate" {
          "there-and-back"
        } else if a.type in ("rotate-camera", "wiggle") { "linear" } else if (
          entry.rate != auto
        ) { entry.rate } else { default-rate }
        let ease = if type(rate) == str {
          assert(
            rate in rate-functions,
            message: "touying-scene: unknown rate `"
              + rate
              + "`. Available: "
              + rate-functions.keys().join(", "),
          )
          if rate not in rates {
            rates.insert(rate, _sample-rate(rate-functions.at(rate)))
          }
          rate
        } else if type(rate) == function {
          custom-rates += 1
          let name = "custom-" + str(custom-rates)
          rates.insert(name, _sample-rate(rate))
          name
        } else {
          panic(
            "touying-scene: a rate must be a name or a function, got "
              + repr(rate),
          )
        }
        if "linear" not in rates {
          rates.insert("linear", _sample-rate(rate-functions.linear))
        }
        let table = rates.at(ease)
        if a.type == "wiggle" {
          // Dedicated tables (manim's wiggle), composed with the rate.
          assert(
            calc.abs(table.first()) <= 1e-6
              and calc.abs(table.last() - 1) <= 1e-6,
            message: "touying-scene.wiggle: the rate must start at 0 and end at 1 (got `"
              + ease
              + "`).",
          )
          let n = a.params.n
          let name = "wiggle-" + str(n) + "-" + ease
          if name not in rates {
            rates.insert(
              name,
              range(257).map(i => {
                let p = _ease-eval(table, i / 256)
                float(
                  (rate-functions.there-and-back)(p)
                    * calc.sin(n * calc.pi * p),
                )
              }),
            )
            rates.insert(
              name + "-scale",
              range(257).map(i => float(
                (rate-functions.there-and-back)(_ease-eval(table, i / 256)),
              )),
            )
          }
        }
        let t0 = cursor + i * float(entry.lag-ratio) * rt
        let t1 = t0 + rt
        play-end = calc.max(play-end, t1)

        // Push a track and update the state to its end value.
        let push(
          seg,
          state,
          last-end,
          id,
          prop,
          v0,
          v1,
          ease: ease,
          t0: t0,
          t1: t1,
          extra: (:),
        ) = {
          // `create` and passing flashes share the stroke dash state.
          let channel = if prop in ("draw", "pass") { "dash" } else { prop }
          let key = id + "/" + channel
          if last-end.at(key, default: -1.0) > t0 + _eps {
            panic(
              "touying-scene: overlapping animations on `"
                + id
                + "` ("
                + channel
                + ") at "
                + str(calc.round(t0, digits: 3))
                + "s. Run them one after another, or animate different properties.",
            )
          }
          last-end.insert(key, t1)
          let tracks = seg.tracks.at(id, default: ())
          tracks.push(
            (
              prop: prop,
              t0: t0,
              t1: t1,
              v0: float(v0),
              v1: float(v1),
              ease: ease,
              ev: ev,
            )
              + extra,
          )
          seg.tracks.insert(id, tracks)
          let end = v0 + (v1 - v0) * _ease-eval(rates.at(ease), 1)
          if prop.starts-with("val:") {
            let st = state.at(id)
            st.values.insert(prop.slice(4), end)
            state.insert(id, st)
          } else {
            state.at(id).insert(prop, end)
          }
          (seg, state, last-end)
        }
        let instant(seg, state, last-end, id, prop, v, at) = push(
          seg,
          state,
          last-end,
          id,
          prop,
          v,
          v,
          ease: "linear",
          t0: at,
          t1: at,
        )

        let ty = a.type
        // Emphasis with an auxiliary object: it is the animated object.
        let aux-id = none
        if ty in _aux-types {
          aux-seen += 1
          aux-id = "@e" + str(aux-seen)
          aux-entries.insert(aux-id, (
            kind: ty,
            target: a.targets.at(0, default: none),
            point: a.params.at("point", default: none),
            params: a.params,
            seg: segments.len(),
            t0: t0,
            t1: t1,
            ev: ev,
          ))
        }
        let id = if aux-id != none { aux-id } else { a.targets.first() }
        let st = state.at(id)
        if ty == "circumscribe" {
          let w = float(a.params.time-width)
          (seg, state, last-end) = instant(
            seg,
            state,
            last-end,
            id,
            "opacity",
            1,
            t0,
          )
          if a.params.fade {
            let tm = (t0 + t1) / 2
            (seg, state, last-end) = push(
              seg,
              state,
              last-end,
              id,
              "draw",
              0,
              1,
              t1: tm,
            )
            (seg, state, last-end) = push(
              seg,
              state,
              last-end,
              id,
              "opacity",
              1,
              0,
              t0: tm,
            )
          } else {
            (seg, state, last-end) = push(
              seg,
              state,
              last-end,
              id,
              "pass",
              0,
              1,
              extra: (w: w),
            )
            (seg, state, last-end) = instant(
              seg,
              state,
              last-end,
              id,
              "opacity",
              0,
              t1,
            )
            (seg, state, last-end) = instant(
              seg,
              state,
              last-end,
              id,
              "pass",
              -1,
              t1,
            )
          }
        } else if ty == "flash" {
          (seg, state, last-end) = instant(
            seg,
            state,
            last-end,
            id,
            "opacity",
            1,
            t0,
          )
          (seg, state, last-end) = push(
            seg,
            state,
            last-end,
            id,
            "pass",
            0,
            1,
            extra: (w: float(a.params.time-width)),
          )
          (seg, state, last-end) = instant(
            seg,
            state,
            last-end,
            id,
            "opacity",
            0,
            t1,
          )
          (seg, state, last-end) = instant(
            seg,
            state,
            last-end,
            id,
            "pass",
            -1,
            t1,
          )
        } else if ty == "focus-on" {
          (seg, state, last-end) = push(
            seg,
            state,
            last-end,
            id,
            "opacity",
            0,
            1,
          )
          (seg, state, last-end) = push(
            seg,
            state,
            last-end,
            id,
            "scale",
            1,
            0,
          )
          for (prop, v) in (("opacity", 0), ("scale", 1)) {
            (seg, state, last-end) = instant(
              seg,
              state,
              last-end,
              id,
              prop,
              v,
              t1,
            )
          }
        } else if ty == "show-passing-flash" {
          if st.opacity < 1 {
            (seg, state, last-end) = instant(
              seg,
              state,
              last-end,
              id,
              "opacity",
              1,
              t0,
            )
          }
          (seg, state, last-end) = push(
            seg,
            state,
            last-end,
            id,
            "pass",
            0,
            1,
            extra: (w: float(a.params.time-width)),
          )
          (seg, state, last-end) = instant(
            seg,
            state,
            last-end,
            id,
            "opacity",
            0,
            t1,
          )
          (seg, state, last-end) = instant(
            seg,
            state,
            last-end,
            id,
            "pass",
            -1,
            t1,
          )
        } else if ty == "wiggle" {
          let deg = s3._deg(a.params.angle)
          let name = "wiggle-" + str(a.params.n) + "-" + ease
          (seg, state, last-end) = push(
            seg,
            state,
            last-end,
            id,
            "rot",
            st.rot,
            st.rot + deg,
            ease: name,
          )
          (seg, state, last-end) = push(
            seg,
            state,
            last-end,
            id,
            "scale",
            st.scale,
            st.scale * a.params.factor,
            ease: name + "-scale",
          )
          // Restore exactly (tables end at 0 only up to rounding).
          for (prop, v) in (("rot", st.rot), ("scale", st.scale)) {
            (seg, state, last-end) = instant(
              seg,
              state,
              last-end,
              id,
              prop,
              v,
              t1,
            )
          }
        } else if ty == "fade-in" {
          if a.params.shift != none {
            let (dx, dy) = _vec(geo, a.params.shift)
            (seg, state, last-end) = push(
              seg,
              state,
              last-end,
              id,
              "tx",
              st.tx - dx,
              st.tx,
            )
            (seg, state, last-end) = push(
              seg,
              state,
              last-end,
              id,
              "ty",
              st.ty - dy,
              st.ty,
            )
          }
          (seg, state, last-end) = push(
            seg,
            state,
            last-end,
            id,
            "opacity",
            0,
            1,
          )
        } else if ty == "fade-out" {
          (seg, state, last-end) = push(
            seg,
            state,
            last-end,
            id,
            "opacity",
            st.opacity,
            0,
          )
          if a.params.shift != none {
            let (dx, dy) = _vec(geo, a.params.shift)
            (seg, state, last-end) = push(
              seg,
              state,
              last-end,
              id,
              "tx",
              st.tx,
              st.tx + dx,
            )
            (seg, state, last-end) = push(
              seg,
              state,
              last-end,
              id,
              "ty",
              st.ty,
              st.ty + dy,
            )
            // Restore the position once invisible.
            (seg, state, last-end) = instant(
              seg,
              state,
              last-end,
              id,
              "tx",
              st.tx,
              t1,
            )
            (seg, state, last-end) = instant(
              seg,
              state,
              last-end,
              id,
              "ty",
              st.ty,
              t1,
            )
          }
        } else if ty in ("create", "write") {
          let prop = if ty == "create" { "draw" } else { "reveal" }
          if st.opacity < 1 {
            (seg, state, last-end) = instant(
              seg,
              state,
              last-end,
              id,
              "opacity",
              1,
              t0,
            )
          }
          (seg, state, last-end) = push(seg, state, last-end, id, prop, 0, 1)
        } else if ty in ("uncreate", "unwrite") {
          let prop = if ty == "uncreate" { "draw" } else { "reveal" }
          (seg, state, last-end) = push(seg, state, last-end, id, prop, 1, 0)
          (seg, state, last-end) = instant(
            seg,
            state,
            last-end,
            id,
            "opacity",
            0,
            t1,
          )
          (seg, state, last-end) = instant(
            seg,
            state,
            last-end,
            id,
            prop,
            1,
            t1,
          )
        } else if ty == "shift" {
          let (dx, dy) = _vec(geo, a.params.by)
          (seg, state, last-end) = push(
            seg,
            state,
            last-end,
            id,
            "tx",
            st.tx,
            st.tx + dx,
          )
          (seg, state, last-end) = push(
            seg,
            state,
            last-end,
            id,
            "ty",
            st.ty,
            st.ty + dy,
          )
        } else if ty == "move-to" {
          let r = _resolve-at(spec, geo, id, objects.at(id), st.values)
          let (hx, hy) = _handle(r)
          let (px, py) = _pos(geo, a.params.pos)
          (seg, state, last-end) = push(
            seg,
            state,
            last-end,
            id,
            "tx",
            st.tx,
            px - hx,
          )
          (seg, state, last-end) = push(
            seg,
            state,
            last-end,
            id,
            "ty",
            st.ty,
            py - hy,
          )
        } else if ty == "rotate-by" {
          let deg = if type(a.params.angle) == angle {
            a.params.angle.deg()
          } else {
            float(a.params.angle)
          }
          (seg, state, last-end) = push(
            seg,
            state,
            last-end,
            id,
            "rot",
            st.rot,
            st.rot + deg,
          )
        } else if ty in ("scale-by", "indicate") {
          (seg, state, last-end) = push(
            seg,
            state,
            last-end,
            id,
            "scale",
            st.scale,
            st.scale * a.params.factor,
          )
        } else if ty == "move-along" {
          let r = _resolve-at(spec, geo, id, objects.at(id), st.values)
          let (hx, hy) = _handle(r)
          let path = a.params.path
          let points = if type(path) == function {
            range(a.params.samples + 1).map(i => path(i / a.params.samples))
          } else { path }
          assert(
            type(points) == array and points.len() >= 2,
            message: "touying-scene.move-along: the path needs at least two points.",
          )
          let pts = points.map(p => {
            let (x, y) = _pos(geo, p)
            (x - hx, y - hy)
          })
          // One "path" track drives tx and ty; register both for overlap checks.
          for prop in ("tx", "ty") {
            let key = id + "/" + prop
            if last-end.at(key, default: -1.0) > t0 + _eps {
              panic(
                "touying-scene: overlapping animations on `"
                  + id
                  + "` ("
                  + prop
                  + ").",
              )
            }
            last-end.insert(key, t1)
          }
          let tracks = seg.tracks.at(id, default: ())
          tracks.push((
            prop: "path",
            t0: t0,
            t1: t1,
            v0: 0.0,
            v1: 1.0,
            ease: ease,
            ev: ev,
            points: pts,
          ))
          seg.tracks.insert(id, tracks)
          let (ex, ey) = pts.at(-1)
          // A path track is evaluated by arc length at eased progress; its end
          // is the point at ease(1).
          let p-end = _ease-eval(table, 1)
          state.at(id).tx = if p-end >= 1 - _eps { ex } else {
            pts.first().at(0)
          }
          state.at(id).ty = if p-end >= 1 - _eps { ey } else {
            pts.first().at(1)
          }
        } else if ty == "transform" {
          let target = a.targets.at(1)
          assert(
            target != id,
            message: "touying-scene.transform: source and target must differ.",
          )
          if a.params.at("mode", default: auto) != "fade" {
            shape-morphs.push((
              source: id,
              target: target,
              t0: t0,
              t1: t1,
              ease: ease,
              ev: ev,
              seg: segments.len(),
              mode: a.params.at("mode", default: auto),
            ))
          }
          let su = state.at(target)
          let ra = _resolve-at(spec, geo, id, objects.at(id), st.values)
          let rb = _resolve-at(spec, geo, target, objects.at(target), su.values)
          let ba = (ra.bbox)()
          let bb = (rb.bbox)()
          let (cax, cay) = (ba.x + ba.w / 2 + st.tx, ba.y + ba.h / 2 + st.ty)
          let (cbx, cby) = (bb.x + bb.w / 2 + su.tx, bb.y + bb.h / 2 + su.ty)
          let ratio = if ba.h > 0 and bb.h > 0 { bb.h / ba.h } else { 1.0 }
          (seg, state, last-end) = push(
            seg,
            state,
            last-end,
            id,
            "opacity",
            st.opacity,
            0,
          )
          (seg, state, last-end) = push(
            seg,
            state,
            last-end,
            id,
            "tx",
            st.tx,
            st.tx + cbx - cax,
          )
          (seg, state, last-end) = push(
            seg,
            state,
            last-end,
            id,
            "ty",
            st.ty,
            st.ty + cby - cay,
          )
          (seg, state, last-end) = push(
            seg,
            state,
            last-end,
            id,
            "scale",
            st.scale,
            st.scale * ratio,
          )
          (seg, state, last-end) = push(
            seg,
            state,
            last-end,
            target,
            "opacity",
            0,
            1,
          )
          (seg, state, last-end) = push(
            seg,
            state,
            last-end,
            target,
            "tx",
            su.tx + cax - cbx,
            su.tx,
          )
          (seg, state, last-end) = push(
            seg,
            state,
            last-end,
            target,
            "ty",
            su.ty + cay - cby,
            su.ty,
          )
          (seg, state, last-end) = push(
            seg,
            state,
            last-end,
            target,
            "scale",
            su.scale / ratio,
            su.scale,
          )
          // The source is gone afterwards; restore its geometry.
          for (prop, v) in (("tx", st.tx), ("ty", st.ty), ("scale", st.scale)) {
            (seg, state, last-end) = instant(
              seg,
              state,
              last-end,
              id,
              prop,
              v,
              t1,
            )
          }
        } else if ty == "transform-matching" {
          let target = a.targets.at(1)
          assert(
            target != id,
            message: "touying-scene.transform-matching: source and target must differ.",
          )
          assert(
            calc.abs(table.first()) <= 1e-6
              and calc.abs(table.last() - 1) <= 1e-6,
            message: "touying-scene.transform-matching: the rate must start at 0 and end at 1 (got `"
              + ease
              + "`).",
          )
          // Reserve every property of both objects for the morph.
          for obj in (id, target) {
            let names = (
              _props + state.at(obj).values.keys().map(v => "val:" + v)
            )
            for prop in names {
              let k = obj + "/" + prop
              if last-end.at(k, default: -1.0) > t0 + _eps {
                panic(
                  "touying-scene.transform-matching: `"
                    + obj
                    + "` is already animated ("
                    + prop
                    + ") at "
                    + str(calc.round(t0, digits: 3))
                    + "s. A morph needs both objects to itself.",
                )
              }
              last-end.insert(k, t1)
            }
          }
          seg.morphs.push((
            kind: "matching",
            source: id,
            target: target,
            t0: t0,
            t1: t1,
            ease: ease,
          ))
          (seg, state, last-end) = instant(
            seg,
            state,
            last-end,
            id,
            "opacity",
            0,
            t1,
          )
          (seg, state, last-end) = instant(
            seg,
            state,
            last-end,
            target,
            "opacity",
            1,
            t1,
          )
        } else if ty == "set-value" {
          let o = objects.at(id)
          assert(
            o.type == "tracked",
            message: "touying-scene.set-value: `"
              + id
              + "` is not a tracked object.",
          )
          for (name, v) in a.params.values {
            assert(
              name in o.values,
              message: "touying-scene.set-value: `"
                + id
                + "` has no value `"
                + name
                + "`. Declare it in `tracked(..)`.",
            )
            (seg, state, last-end) = push(
              seg,
              state,
              last-end,
              id,
              "val:" + name,
              st.values.at(name),
              v,
            )
          }
        } else if ty in ("move-camera", "rotate-camera") {
          let cv = st.values
          let targets = (:)
          if ty == "rotate-camera" {
            targets.insert("theta", cv.theta + s3._deg(a.params.by))
          } else {
            let p = a.params
            if p.phi != auto { targets.insert("phi", s3._deg(p.phi)) }
            if p.theta != auto { targets.insert("theta", s3._deg(p.theta)) }
            if p.zoom != auto { targets.insert("zoom", float(p.zoom)) }
            if p.focal != auto {
              targets.insert("ifocal", if p.focal == none { 0.0 } else {
                1 / float(p.focal)
              })
            }
            if p.center != auto {
              targets.insert("cx", float(p.center.at(0)))
              targets.insert("cy", float(p.center.at(1)))
              targets.insert("cz", float(p.center.at(2)))
            }
          }
          let (lo, hi) = (calc.min(..table), calc.max(..table))
          for (name, v) in targets {
            let v0 = cv.at(name)
            for e in (lo, hi) {
              let x = v0 + (v - v0) * e
              if name == "zoom" {
                assert(
                  x > 0,
                  message: "touying-scene.move-camera: the zoom must stay positive (also with the rate's overshoot).",
                )
              }
              if name == "ifocal" {
                assert(
                  x >= 0,
                  message: "touying-scene.move-camera: the focal distance must stay positive (also with the rate's overshoot).",
                )
              }
            }
            (seg, state, last-end) = push(
              seg,
              state,
              last-end,
              "@camera",
              "val:" + name,
              v0,
              v,
            )
          }
        } else if ty in ("rotate-3d", "shift-3d") {
          let key = id + "/transform3d"
          if last-end.at(key, default: -1.0) > t0 + _eps {
            panic(
              "touying-scene: overlapping 3D transforms on `"
                + id
                + "` at "
                + str(calc.round(t0, digits: 3))
                + "s. Run them one after another.",
            )
          }
          last-end.insert(key, t1)
          let list = steps.at(id, default: ())
          let step = if ty == "rotate-3d" {
            (
              kind: "rot",
              axis: _axis3d(a.params.axis),
              angle: s3._deg(a.params.angle),
              vec: (0.0, 0.0, 0.0),
              about: a.params.about,
            )
          } else {
            (
              kind: "move",
              axis: (0.0, 0.0, 1.0),
              angle: 0.0,
              vec: s3._vec3(a.params.by),
              about: none,
            )
          }
          list.push(step + (seg: segments.len(), t0: t0, ev: ev))
          steps.insert(id, list)
          (seg, state, last-end) = push(
            seg,
            state,
            last-end,
            id,
            "step:" + str(list.len() - 1),
            0,
            1,
          )
        } else if ty == "add" {
          (seg, state, last-end) = instant(
            seg,
            state,
            last-end,
            id,
            "opacity",
            1,
            t0,
          )
        } else if ty == "remove" {
          (seg, state, last-end) = instant(
            seg,
            state,
            last-end,
            id,
            "opacity",
            0,
            t0,
          )
        } else {
          panic("touying-scene: unknown animation `" + ty + "`")
        }
      }
      cursor = play-end
    }
  }
  seg.duration = cursor
  seg.insert("end", state)
  segments.push(seg)

  // Pivots of 3D rotations: the centre of the object as it is when the step
  // starts (values and earlier steps at that moment, excluding events that
  // come later in the timeline at the same time).
  let partial = (segments: segments, rates: rates)
  for (id, list) in steps {
    for (k, step) in list.enumerate() {
      let pivot = if step.kind != "rot" { (0.0, 0.0, 0.0) } else if (
        step.about != auto
      ) { s3._vec3(step.about) } else {
        let sg = segments.at(step.seg)
        let st = _state-at(partial, sg, id, step.t0, before-ev: step.ev)
        let g = _geom3d(objects.at(id), st.values)
        let m = s3.steps-matrix(
          list
            .slice(0, k)
            .map(x => x + (pivot: x.at("pivot", default: (0.0, 0.0, 0.0)))),
          _step-progress(st, k),
        )
        s3.bbox-center(s3.points(g).map(p => s3.mat-apply(m, p)))
      }
      list.at(k).insert("pivot", pivot)
    }
    steps.insert(id, list)
  }
  // Shape morphs: a `transform` is drawn as a point-by-point morph in HTML
  // only if nothing else changes either object meanwhile (the crossfade
  // tracks stay authoritative; the morph is another rendering of them).
  for c in shape-morphs {
    let sg = segments.at(c.seg)
    let table = rates.at(c.ease)
    let fail(reason) = if c.mode == "shape" {
      panic(
        "touying-scene.transform(\""
          + c.source
          + "\", \""
          + c.target
          + "\", mode: \"shape\"): "
          + reason
          + ". Use mode: auto or \"fade\" to crossfade instead.",
      )
    } else { reason }
    let reason = none
    if (
      calc.abs(table.first()) > 1e-6 or calc.abs(table.last() - 1) > 1e-6
    ) {
      reason = fail("the rate must start at 0 and end at 1")
    }
    for obj in (c.source, c.target) {
      if reason != none { break }
      if is3d.at(obj) {
        reason = fail("`" + obj + "` is a 3D object")
        break
      }
      for tr in sg.tracks.at(obj, default: ()) {
        if tr.at("ev", default: -1) == c.ev { continue }
        let inside = tr.t1 > c.t0 + _eps and tr.t0 < c.t1 - _eps
        let instant-inside = (
          tr.t1 - tr.t0 <= _eps and tr.t0 > c.t0 + _eps and tr.t0 < c.t1 - _eps
        )
        let after-at-start = (
          calc.abs(tr.t0 - c.t0) <= _eps and tr.at("ev", default: -1) > c.ev
        )
        if inside or instant-inside or after-at-start {
          reason = fail(
            "`" + obj + "` is animated (" + tr.prop + ") while it morphs",
          )
          break
        }
      }
    }
    let partial = (segments: segments, rates: rates)
    let s0 = _state-at(partial, sg, c.source, c.t0, before-ev: c.ev)
    let d1 = _state-at(partial, sg, c.target, c.t1, before-ev: c.ev + 1)
    if reason == none {
      for (name, st) in (("source", s0), ("target", d1)) {
        if (
          calc.abs(st.opacity - 1) > 1e-6
            or calc.abs(st.draw - 1) > 1e-6
            or calc.abs(st.reveal - 1) > 1e-6
            or st.at("pass", default: -1.0) >= 0
        ) {
          reason = fail(
            "the "
              + name
              + " is not fully visible and drawn at its end of the morph",
          )
          break
        }
      }
    }
    if (
      reason == none
        and objects.at(c.source).at("behind", default: false)
          != objects.at(c.target).at("behind", default: false)
    ) {
      reason = fail("source and target are on different layers (`behind`)")
    }
    if reason != none { continue }
    let seg = segments.at(c.seg)
    seg.morphs.push((
      kind: "shape",
      source: c.source,
      target: c.target,
      t0: c.t0,
      t1: c.t1,
      ease: c.ease,
      src: s0,
      dst: d1,
      strict: c.mode == "shape",
    ))
    segments.at(c.seg) = seg
  }
  // Auxiliary objects: geometry from the target as it is when the animation
  // starts (values and transform at that event), mapped to scene coordinates.
  let aux = (:)
  let partial = (segments: segments, rates: rates)
  let to-scene((x, y)) = (geo.xmin + x / geo.u, geo.ymax - y / geo.u)
  for (aid, e) in aux-entries {
    let q = e.params
    let (centre, half, scale, corners) = if e.target != none {
      let sg = segments.at(e.seg)
      let st = _state-at(partial, sg, e.target, e.t0, before-ev: e.ev)
      let r = _resolve-at(spec, geo, e.target, objects.at(e.target), st.values)
      let b = (r.bbox)()
      let (px, py) = (r.pivot)()
      let ang = -st.rot * 1deg
      let k = st.scale
      let mp((x, y)) = {
        let (qx, qy) = ((x - px) * k, (y - py) * k)
        to-scene((
          px + st.tx + qx * calc.cos(ang) - qy * calc.sin(ang),
          py + st.ty + qx * calc.sin(ang) + qy * calc.cos(ang),
        ))
      }
      let pad = if e.kind == "circumscribe" and k > 1e-9 {
        q.buff * geo.u / k
      } else { 0 }
      (
        mp((b.x + b.w / 2, b.y + b.h / 2)),
        calc.max(b.w, b.h) / 2 * k / geo.u,
        k,
        (
          (b.x - pad, b.y - pad),
          (b.x + b.w + pad, b.y - pad),
          (b.x + b.w + pad, b.y + b.h + pad),
          (b.x - pad, b.y + b.h + pad),
        ).map(mp)
          + if e.kind == "circumscribe" and q.shape == "circle" {
            (
              (
                calc.sqrt(b.w * b.w + b.h * b.h) / 2 * k / geo.u + q.buff,
              ),
            )
          } else { () },
      )
    } else {
      (to-scene(_pos(geo, e.point)), 0.0, 1.0, ())
    }
    let o = if e.kind == "circumscribe" {
      let segs = if q.shape == "circle" {
        s2._circle-segs(centre, corners.last().first())
      } else {
        s2._polyline(corners + (corners.first(),))
      }
      shape(paths: (path(segs: segs, closed: true, stroke: q.stroke),))
    } else if e.kind == "flash" {
      let r0 = if q.radius != auto { float(q.radius) } else {
        half + 0.1
      }
      shape(
        paths: range(q.lines).map(i => {
          let a = 360deg * i / q.lines
          let (dx, dy) = (calc.cos(a), calc.sin(a))
          path(
            pts: (
              (centre.at(0) + dx * r0, centre.at(1) + dy * r0),
              (
                centre.at(0) + dx * (r0 + q.line-length),
                centre.at(1) + dy * (r0 + q.line-length),
              ),
            ),
            stroke: q.stroke,
          )
        }),
      )
    } else {
      let r = if q.radius != auto { float(q.radius) } else {
        calc.sqrt(geo.w * geo.w + geo.h * geo.h) / geo.u
      }
      shape(paths: (
        (
          segs: s2._circle-segs(centre, r),
          closed: true,
          fill: q.color,
          stroke: none,
        ),
      ))
    }
    aux.insert(aid, o + (visible: false))
  }

  // Morphs in timeline order (the player applies them in record order).
  segments = segments.map(sg => {
    sg.morphs = sg.morphs.sorted(key: m => m.t0)
    sg
  })
  (
    segments: segments,
    rates: rates,
    steps: steps,
    cam: cam,
    is3d: is3d,
    aux: aux,
  )
}

// User objects in declaration order, then auxiliary (emphasis) objects.
#let _all-objects(spec, model) = spec.objects + model.at("aux", default: (:))

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------

#let _is-identity(st) = (
  calc.abs(st.tx) < 1e-6
    and calc.abs(st.ty) < 1e-6
    and calc.abs(st.rot) < 1e-6
    and calc.abs(st.scale - 1) < 1e-6
)

// Apply M = T(t) · T(p) · R(θ) · S(s) · T(-p) to a scene-sized layer.
#let _transform-layer(layer, st, pivot) = {
  if _is-identity(st) { return layer }
  let (px, py) = pivot()
  move(
    dx: (st.tx + px) * 1pt,
    dy: (st.ty + py) * 1pt,
    rotate(
      -st.rot * 1deg,
      origin: top + left,
      reflow: false,
      scale(
        st.scale * 100%,
        origin: top + left,
        reflow: false,
        move(dx: -px * 1pt, dy: -py * 1pt, layer),
      ),
    ),
  )
}

// The 3D objects of a scene in a given state: (view, items, geometries).
#let _world-items(spec, model, states) = {
  let view = s3.make-view(
    states.at("@camera").values,
    model.cam.unit,
    model.cam.at,
  )
  let items = ()
  let geoms = ()
  for (id, o) in spec.objects {
    if not model.is3d.at(id) { continue }
    let st = states.at(id)
    let g = _geom3d(o, st.values)
    let list = model.steps.at(id, default: ())
    let m = s3.steps-matrix(list, _step-progress(st, list.len()))
    items.push((g, m, st.opacity, st.draw))
    geoms.push(g)
  }
  (view, items, geoms)
}

// The 3D layer for PDF: projected, sorted and drawn like the HTML player.
#let _render-world(self, spec, model, states) = {
  let (view, items, geoms) = _world-items(spec, model, states)
  let list = s3.drawables(view, items)
  let place-label(d) = {
    let body = geoms.at(d.obj).labels.at(d.label).body
    let size = measure(body)
    let content = place(
      dx: d.at.at(0) * 1pt - size.width / 2,
      dy: d.at.at(1) * 1pt - size.height / 2,
      body,
    )
    if d.alpha < 1 - 1e-6 {
      utils.alpha-changing-cover(self: self, alpha: d.alpha * 100%, content)
    } else { content }
  }
  for d in list {
    if d.kind == "label" and not d.depth { continue }
    s3.draw-one(d, place-label)
  }
  // Overlay labels: above all geometry.
  for d in list {
    if d.kind == "label" and not d.depth { place-label(d) }
  }
}

// Static rendering (PDF, handout, article): the state `st` of every object.
// Layers: 2D objects with `behind: true`, the 3D world, other 2D objects.
#let _render-static(self, spec, geo, model, states) = {
  let draw-2d(behind) = {
    for (id, o) in _all-objects(spec, model) {
      if model.is3d.at(id) or o.at("behind", default: false) != behind {
        continue
      }
      let st = states.at(id)
      if st.opacity <= 1e-6 { continue }
      let r = _resolve-at(spec, geo, id, o, st.values)
      let layer = _transform-layer(r.layer, st, r.pivot)
      if st.opacity < 1 - 1e-6 {
        layer = utils.alpha-changing-cover(
          self: self,
          alpha: st.opacity * 100%,
          layer,
        )
      }
      place(top + left, layer)
    }
  }
  box(
    width: geo.w * 1pt,
    height: geo.h * 1pt,
    clip: spec.clip,
    {
      draw-2d(true)
      if model.cam != none { _render-world(self, spec, model, states) }
      draw-2d(false)
    },
  )
}

#let _round(x) = calc.round(x, digits: 6)

#let _state-json(st, rnd: _round) = {
  let out = (
    opacity: rnd(st.opacity),
    tx: rnd(st.tx),
    ty: rnd(st.ty),
    rot: rnd(st.rot),
    scale: rnd(st.scale),
    draw: rnd(st.draw),
    reveal: rnd(st.reveal),
  )
  for (k, v) in st {
    if k.starts-with("step:") { out.insert(k, rnd(v)) }
  }
  if st.at("pass", default: -1.0) >= 0 { out.insert("pass", rnd(st.pass)) }
  out
}

// Sample times of a tracked object within a segment.
// Sampling plan of a tracked object in one segment. [0, duration] is split
// at the start and end of every value track into half-open spans [a, b):
//
// - "hold": no value changes; one knot.
// - "progress": the span is exactly the interval of every value track active
//   in it, and they share one rate. Knots are placed uniformly in eased
//   progress u (plus the rate table's extreme values and its end points); the
//   player maps time to u through the same table, so the easing is exact.
// - "time": anything else; knots uniform in time.
//
// The last knot of a span is the limit from the left at b; instant updates at
// b belong to the next span. `end` is the state after all events at the end
// of the segment. Knots are never dropped for having the values of their
// neighbours: interpolating across a plateau needs both of its ends.
// Samples per second of a tracked object: its own, or the scene config's.
#let _fps-of(o, fps) = {
  let own = o.at("samples-per-second", default: auto)
  if own == auto { fps } else { float(own) }
}

#let _spans(model, seg, id, fps) = {
  let tracks = seg
    .tracks
    .at(id, default: ())
    .filter(tr => tr.prop.starts-with(
      "val:",
    ))
  let duration = seg.duration
  let cuts = (0.0, duration)
  for tr in tracks { cuts += (tr.t0, tr.t1) }
  cuts = cuts.map(c => calc.round(c, digits: 9)).sorted().dedup()
  let spans = ()
  for (a, b) in cuts.zip(cuts.slice(1)) {
    if b - a <= _eps { continue }
    let live = tracks.filter(tr => tr.t0 < b - _eps and tr.t1 > a + _eps)
    let n = calc.max(1, int(calc.ceil((b - a) * fps - _eps)))
    let left = _state-at(model, seg, id, a)
    if live.len() == 0 {
      spans.push((
        a: a,
        b: b,
        kind: "hold",
        ease: none,
        knots: (
          (0.0, left.values),
        ),
      ))
    } else if live.all(tr => (
      calc.abs(tr.t0 - a) <= 1e-6
        and calc.abs(tr.t1 - b) <= 1e-6
        and tr.ease == live.first().ease
    )) {
      let table = model.rates.at(live.first().ease)
      let (lo, hi) = (calc.min(..table), calc.max(..table))
      let us = (table.first(), table.last())
      us += range(n + 1).map(i => lo + (hi - lo) * i / n)
      for i in range(1, table.len() - 1) {
        if (
          (table.at(i) - table.at(i - 1)) * (table.at(i + 1) - table.at(i)) < 0
        ) {
          us.push(table.at(i))
        }
      }
      us = us.map(u => calc.round(u, digits: 9)).sorted().dedup()
      let knots = us.map(u => {
        let values = left.values
        for tr in live {
          values.insert(tr.prop.slice(4), tr.v0 + (tr.v1 - tr.v0) * u)
        }
        (u, values)
      })
      spans.push((
        a: a,
        b: b,
        kind: "progress",
        ease: live.first().ease,
        knots: knots,
      ))
    } else {
      let knots = range(n + 1).map(i => {
        let t = a + (b - a) * i / n
        (t, _state-at(model, seg, id, t, left: i == n).values)
      })
      spans.push((a: a, b: b, kind: "time", ease: none, knots: knots))
    }
  }
  (spans: spans, end: seg.end.at(id).values)
}

// HTML rendering: every object that is visible at some point of the segment,
// at base geometry, wrapped in labelled boxes; plus the metadata record.
#let _render-html(self, spec, geo, model, k, lifecycle, key, dom) = {
  let seg = model.segments.at(k)
  let config = self.at("scene", default: (:))
  let fps = float(config.at("samples-per-second", default: 30))
  let max-samples = config.at("max-samples", default: 241)
  let active = lifecycle == "active"
  let start = if lifecycle == "held" { seg.end } else { seg.start }
  // 3D scenes keep full precision: projections amplify rounding errors.
  let has3d = model.cam != none
  let _round = if has3d { x => x } else { _round }
  let records = ()
  let layers = ()
  let back-layers = ()
  let world-layers = ()
  let used-rates = ()
  let max-geometry = config.at("max-geometry", default: 300000)
  let v3 = false
  for (order, (id, o)) in _all-objects(spec, model).pairs().enumerate() {
    let st = start.at(id)
    let tracks = if active { seg.tracks.at(id, default: ()) } else { () }
    if st.opacity <= 1e-6 and tracks.len() == 0 { continue }
    let label-name = dom + "-" + id
    if model.is3d.at(id) {
      let g = _geom3d(o, st.values)
      let knots = none
      if o.type == "tracked" and tracks.any(tr => tr.prop.starts-with("val:")) {
        let plan = _spans(model, seg, id, _fps-of(o, fps))
        let renders = ()
        let spans = ()
        for sp in plan.spans {
          let points = ()
          for (p, values) in sp.knots {
            let i = renders.position(v => v == values)
            if i == none {
              renders.push(values)
              i = renders.len() - 1
            }
            points.push((p, i))
          }
          spans.push((
            a: sp.a,
            b: sp.b,
            kind: sp.kind,
            ease: sp.ease,
            knots: points,
          ))
        }
        let end = renders.position(v => v == plan.end)
        if end == none {
          renders.push(plan.end)
          end = renders.len() - 1
        }
        let topo = s3.topology(g)
        let positions = renders.map(values => {
          let gk = _geom3d(o, values)
          assert(
            s3.topology(gk) == topo,
            message: "touying-scene: the tracked 3D object `"
              + id
              + "` changes its structure (number of points, primitives or colours) with its values; only positions may change.",
          )
          gk.pos
        })
        if positions.len() * g.pos.len() > max-geometry {
          panic(
            "touying-scene: tracked 3D object `"
              + id
              + "` needs "
              + str(positions.len() * g.pos.len())
              + " coordinates in one segment (limit "
              + str(max-geometry)
              + "). Use fewer samples (`config-scene(samples-per-second: ..)`, `surface(samples: ..)`) or raise `config-scene(max-geometry: ..)`.",
          )
        }
        knots = (
          kind: "geom",
          interpolate: o.interpolate,
          spans: spans,
          end: end,
          positions: positions,
        )
      }
      let list = model.steps.at(id, default: ())
      let label-records = ()
      for (i, l) in g.labels.enumerate() {
        let name = label-name + "-L" + str(i)
        let size = measure(l.body)
        label-records.push((
          label: name,
          w: size.width / 1pt,
          h: size.height / 1pt,
          depth: l.depth,
        ))
        world-layers.push(place(top + left, [#box(l.body)#label(name)]))
      }
      for tr in tracks { used-rates.push(tr.ease) }
      records.push((
        id: id,
        label: label-name,
        order: order,
        pivot: (0, 0),
        initial: _state-json(st, rnd: _round),
        tracks: tracks
          .filter(tr => not tr.prop.starts-with("val:"))
          .map(tr => (
            prop: tr.prop,
            t0: tr.t0,
            t1: tr.t1,
            v0: tr.v0,
            v1: tr.v1,
            ease: tr.ease,
          )),
        knots: knots,
        geom: (
          pos: g.pos,
          prims: g.prims,
          mats: g.mats,
          labels: label-records,
          steps: list.map(x => (
            kind: x.kind,
            axis: x.axis,
            angle: x.angle,
            vec: x.vec,
            pivot: x.pivot,
          )),
        ),
      ))
      continue
    }
    let knots = none
    let body = if (
      o.type == "tracked" and tracks.any(tr => tr.prop.starts-with("val:"))
    ) {
      let plan = _spans(model, seg, id, _fps-of(o, fps))
      // Render every distinct value set once; knots refer to renders by index.
      let renders = ()
      let spans = ()
      for sp in plan.spans {
        let points = ()
        for (p, values) in sp.knots {
          let i = renders.position(v => v == values)
          if i == none {
            renders.push(values)
            i = renders.len() - 1
          }
          points.push((_round(p), i))
        }
        spans.push((
          a: _round(sp.a),
          b: _round(sp.b),
          kind: sp.kind,
          ease: sp.ease,
          knots: points,
        ))
      }
      let end = renders.position(v => v == plan.end)
      if end == none {
        renders.push(plan.end)
        end = renders.len() - 1
      }
      if renders.len() > max-samples {
        panic(
          "touying-scene: tracked object `"
            + id
            + "` needs "
            + str(renders.len())
            + " samples in one segment (limit "
            + str(max-samples)
            + "). Lower `config-scene(samples-per-second: ..)` or raise `max-samples`.",
        )
      }
      knots = (
        interpolate: o.interpolate,
        labels: range(renders.len()).map(i => label-name + "-k" + str(i)),
        spans: spans,
        end: end,
      )
      box(
        width: geo.w * 1pt,
        height: geo.h * 1pt,
        {
          for (i, values) in renders.enumerate() {
            let r = _resolve-at(spec, geo, id, o, values)
            place(top + left, [#r.layer#label(label-name + "-k" + str(i))])
          }
        },
      )
    } else {
      _resolve-at(spec, geo, id, o, st.values).layer
    }
    let needs-pivot = (
      tracks.any(tr => tr.prop in ("rot", "scale"))
        or calc.abs(st.rot) > 1e-6
        or calc.abs(st.scale - 1) > 1e-6
    )
    let pivot = if needs-pivot {
      let r = _resolve-at(spec, geo, id, o, st.values)
      (r.pivot)().map(_round)
    } else { (0, 0) }
    for tr in tracks { used-rates.push(tr.ease) }
    if id.starts-with("@") or tracks.any(tr => tr.prop == "pass") {
      v3 = true
    }
    records.push((
      id: id,
      label: label-name,
      order: order,
      pivot: pivot,
      initial: _state-json(st),
      tracks: tracks
        .filter(tr => not tr.prop.starts-with("val:"))
        .map(tr => {
          let rec = (
            prop: tr.prop,
            t0: _round(tr.t0),
            t1: _round(tr.t1),
            v0: _round(tr.v0),
            v1: _round(tr.v1),
            ease: tr.ease,
          )
          if tr.prop == "path" {
            rec.insert("points", tr.points.map(p => p.map(_round)))
          }
          if "w" in tr { rec.insert("w", tr.w) }
          rec
        }),
      knots: knots,
    ))
    let layer = place(top + left, [#body#label(label-name)])
    if o.at("behind", default: false) { back-layers.push(layer) } else {
      layers.push(layer)
    }
  }
  let camera = none
  if has3d {
    let tracks = if active { seg.tracks.at("@camera", default: ()) } else {
      ()
    }
    for tr in tracks { used-rates.push(tr.ease) }
    camera = (
      initial: start.at("@camera").values,
      tracks: tracks.map(tr => (
        prop: tr.prop.slice(4),
        t0: tr.t0,
        t1: tr.t1,
        v0: tr.v0,
        v1: tr.v1,
        ease: tr.ease,
      )),
      unit: model.cam.unit,
      at: model.cam.at,
    )
  }
  let morphs = if active { seg.morphs } else { () }
  for m in morphs { used-rates.push(m.ease) }
  let rates = (:)
  for name in used-rates.dedup() {
    rates.insert(name, model.rates.at(name).map(_round))
  }
  let record = (
    // Schema 3: morph kinds and snapshots, passing flashes, emphasis objects.
    schema: if (
      morphs.len() > 0 or v3
    ) { 3 } else if has3d { 2 } else { _schema-version },
    camera: camera,
    world: if has3d { (label: dom + "-world") } else { none },
    scene: (
      key: key,
      dom: dom,
      alt: spec.alt,
      size: (_round(geo.w), _round(geo.h)),
    ),
    page: (subslide: self.subslide),
    lifecycle: lifecycle,
    segment: k + 1,
    segments: model.segments.len(),
    duration: if active { _round(seg.duration) } else { 0 },
    rates: rates,
    objects: records,
    morphs: morphs.map(m => {
      let out = (
        kind: m.kind,
        source: m.source,
        target: m.target,
        t0: _round(m.t0),
        t1: _round(m.t1),
        ease: m.ease,
      )
      if m.kind == "shape" {
        out.insert("src", _state-json(m.src))
        out.insert("dst", _state-json(m.dst))
        out.insert("strict", m.strict)
      }
      out
    }),
  )
  // The record travels inside the page's SVG as the label of an empty group,
  // so the exporter needs no separate query and a hidden scene carries no
  // record. Typst escapes `"` in the attribute but not `<`, `>` or `&`, so
  // those are written as JSON unicode escapes.
  let data = (
    json
      .encode(record, pretty: false)
      .replace("&", "\\u0026")
      .replace("<", "\\u003c")
      .replace(">", "\\u003e")
  )
  [#box(
      width: geo.w * 1pt,
      height: geo.h * 1pt,
      clip: spec.clip,
      {
        place(
          top + left,
          [#box(width: 0pt, height: 0pt)#label("tys-data:" + data)],
        )
        back-layers.join()
        if has3d {
          place(top + left, [#box(width: 0pt, height: 0pt)#label(
              dom + "-world",
            )])
          world-layers.join()
        }
        layers.join()
      },
    )#label(dom)]
  // Also queryable, e.g. `typst eval 'query(<touying-scene>)' --input touying-scene=html`.
  [#metadata(record)<touying-scene>]
}

#let _is-html(self) = {
  let config = self.at("scene", default: (:))
  let target = config.at("target", default: auto)
  if target == auto {
    // Read the raw string: `utils.get-input` would evaluate "html" to the
    // `html` module when Typst's html feature is enabled (as in typst-py).
    sys.inputs.at("touying-scene", default: none) == "html"
  } else { target == "html" }
}

#let _scene-fn(self: none, start: 1, spec: none) = context {
  let geo = _make-geometry(spec)
  let model = _compile(spec, geo, self.at("scene", default: (:)))
  let n = model.segments.len()
  let last = start + n - 1
  let sub = self.subslide
  let summary = (
    self.at("article-mode", default: false)
      or (
        self.at("handout", default: false)
          and self.at("handout-subslides", default: none) == none
      )
  )

  if summary {
    // Handout/article: one representative state.
    let h = spec.handout
    let states = if h == auto { model.segments.last().end } else if (
      h == "start"
    ) {
      model.segments.first().start
    } else {
      assert(
        type(h) == int and h >= 1 and h <= n,
        message: "touying-scene: `handout` must be auto, \"start\" or a segment number from 1 to "
          + str(n),
      )
      model.segments.at(h - 1).end
    }
    _render-static(self, spec, geo, model, states)
  } else {
    let (lifecycle, k) = if sub < start { ("before", 0) } else if sub <= last {
      ("active", sub - start)
    } else { ("held", n - 1) }

    let out = if _is-html(self) {
      // Logical identity: slide number plus the scene id (or its ordinal on
      // the page).
      let slide = utils.slide-counter.get().first()
      let id = if spec.id == auto {
        let earlier = query(
          selector(<touying-scene>).before(here()),
        ).filter(e => e.location().page() == here().page())
        str(earlier.len() + 1)
      } else { spec.id }
      let key = "s" + str(slide) + "-" + id
      _render-html(self, spec, geo, model, k, lifecycle, key, "tys-" + key)
    } else {
      let states = if lifecycle == "before" {
        model.segments.first().start
      } else { model.segments.at(k).end }
      _render-static(self, spec, geo, model, states)
    }
    if lifecycle == "before" { (self.methods.cover)(self: self, out) } else {
      out
    }
  }
}

/// A manim-style animated scene. Each `click` in the timeline adds a subslide;
/// a following `#pause` continues after the scene's last segment.
///
/// ```typst
/// #let sc = touying-scene
/// #sc.scene(width: 12cm, height: 6cm,
///   objects: (eq: sc.obj(at: (6, 3), visible: false, $E = m c^2$)),
///   timeline: (sc.write("eq"), sc.click, sc.indicate("eq")),
/// )
/// ```
///
/// - id (auto, str): Identifier, unique per slide (`auto`: position on the slide).
/// - width (length): Width of the scene box.
/// - height (length): Height of the scene box.
/// - objects (dictionary): Named objects (`obj`, `cetz-obj`, `tracked`), drawn
///   in declaration order.
/// - timeline (array): `play(..)`, animations, `wait(..)` and `click` entries.
/// - cetz (module, none): The cetz module, required for `cetz-obj`.
/// - bounds (auto, array): `((xmin, ymin), (xmax, ymax))` in scene coordinates;
///   they are centred and widened to fill the box. `auto`: `(0, 0)` to the box
///   size in `unit`s.
/// - unit (auto, length): Length of one scene unit; `auto` fits `bounds`.
/// - alt (none, str): Text alternative for screen readers in the HTML export.
/// - handout (auto, int, str): State shown in handout and article mode:
///   `auto` (end), a segment number, or `"start"`.
/// - clip (bool): Clip the scene to its box.
/// - camera (none, dictionary): A 3D camera (`camera(..)`); needed for 3D
///   objects. 3D objects are drawn in one layer (sorted by depth) above 2D
///   objects with `behind: true` and below all other 2D objects.
/// -> content
#let scene(
  id: auto,
  width: none,
  height: none,
  objects: (:),
  timeline: (),
  cetz: none,
  bounds: auto,
  unit: auto,
  alt: none,
  handout: auto,
  clip: false,
  camera: none,
) = {
  assert(
    width != none and height != none,
    message: "touying-scene.scene: `width` and `height` are required.",
  )
  assert(
    id == auto
      or (type(id) == str and id.match(regex("^[A-Za-z0-9_-]+$")) != none),
    message: "touying-scene.scene: `id` may only contain letters, digits, `-` and `_`.",
  )
  for k in objects.keys() {
    assert(
      k.match(regex("^[A-Za-z0-9_-]+$")) != none,
      message: "touying-scene.scene: object name `"
        + k
        + "` may only contain letters, digits, `-` and `_`.",
    )
  }
  let spec = (
    id: id,
    width: width,
    height: height,
    objects: objects,
    timeline: timeline,
    cetz: cetz,
    bounds: bounds,
    unit: unit,
    alt: alt,
    handout: handout,
    clip: clip,
    camera: camera,
  )
  let n = _count-segments(timeline)
  touying-fn-wrapper(
    _scene-fn,
    advances-flow: true,
    last-subslide: repetitions => (repetitions + n - 1, (start: repetitions)),
    spec: spec,
  )
}
