---
sidebar_position: 8
---

# Scenes (manim-style animations)

`touying-scene` animates objects over time, in the spirit of [manim](https://www.manim.community/): you declare named objects (equations, text, CeTZ drawings, value-dependent drawings) and a timeline of `play`, `wait` and `click` steps. The same source gives you:

- **PDF / handout / article**: one page per click with the state at the end of each step (like ordinary subslides);
- **HTML**: a single self-contained file in which fades, drawing, writing, moves, rotations and value trackers actually play, exported with [touying-exporter](../../external/touying-exporter.md).

```typst
#import "@preview/touying:0.8.1": *
#import themes.simple: *
#import "@preview/cetz:0.5.2"

#show: simple-theme.with(aspect-ratio: "16-9")

#let sc = touying-scene
#import cetz.draw: circle, line

== Gradient descent

#sc.scene(
  width: 22cm,
  height: 7.5cm,
  cetz: cetz,
  bounds: ((-3, -1), (3, 5)),
  alt: "A parabola with a dot rolling to its minimum",
  objects: (
    axes: sc.cetz-obj({
      line((-3, 0), (3, 0), mark: (end: ">"))
      line((0, -1), (0, 5), mark: (end: ">"))
    }),
    curve: sc.cetz-obj({
      line(..range(-22, 23).map(i => (i / 10, calc.pow(i / 10, 2))), stroke: blue + 2pt)
    }),
    eq: sc.obj(at: (-6, 4), anchor: left + horizon, $f(x) = x^2$),
    eq2: sc.obj(at: (-6, 4), anchor: left + horizon, $f'(x) = 2x$),
    dot: sc.tracked(x: -2, v => sc.cetz-obj({
      circle((v.x, v.x * v.x), radius: .12, fill: red, stroke: none)
    })),
  ),
  timeline: (
    sc.play(sc.create("axes"), sc.write("eq"), run-time: 1.5),
    sc.play(sc.create("curve")),
    sc.click,
    sc.play(sc.fade-in("dot", shift: (0, 1))),
    sc.play(sc.set-value("dot", x: 0), run-time: 2),
    sc.wait(.5),
    sc.click,
    sc.play(sc.transform("eq", "eq2")),
  ),
)

#pause

Converges to the minimum.
```

The scene above has three segments (two `click`s), so it occupies subslides 1–3; the `#pause` after it continues on subslide 4. Entering a segment in the HTML player plays it; a click during playback finishes it, the next click advances.

## Coordinates and units

- Times are numbers in **seconds** (Typst has no duration literals).
- Numbers in positions and vectors are **scene coordinates**: y points up, one unit is `unit` long. `bounds: ((xmin, ymin), (xmax, ymax))` fixes the coordinate range; it is centred in the scene box and widened to fill it, and `unit: auto` fits it.
- Lengths (`1cm`) are layout distances from the scene's top-left corner, y down. Ratios (`50%`) are relative to the scene size.
- Angles are counter-clockwise, as in manim and CeTZ.

## Objects

| Function | Description |
| --- | --- |
| `obj(body, at: (0, 0), anchor: center + horizon)` | Any content; `anchor` is the point of the object placed at `at`. |
| `cetz-obj(body)` | CeTZ draw commands in the scene's shared coordinate system (pass `cetz: cetz` to the scene). Every CeTZ object is drawn on a canvas spanning exactly the scene bounds, so all of them align; drawing outside the bounds is an error. |
| `tracked(fn, ..values, interpolate: false)` | Like manim's `ValueTracker` + `always_redraw`: `fn` receives the current values and returns an object. |
| `shape(paths: (..), labels: (..))` | Paths (`path(pts: ..)` or `path(segs: ..)`) and labels in scene coordinates, drawn natively. The graph helpers below return shapes. |
| `group(..objs)` | Several objects drawn as one, for example a tangent and its dot returned by a `tracked` function. |
| `surround(of: id)`, `brace(of: id, label: ..)` | A rectangle or circle around another object, or a curly brace along one of its sides; see "Emphasis". |

Every object accepts `visible` and `pivot`:

- `visible: auto` (default) hides an object at the start if its first animation introduces it (`fade-in`, `create`, `write`, `add`, or the target of `transform`); use `true`/`false` to override.
- `pivot` is the centre of rotations and scaling, `auto` being the centre of the object's box (content) or of its drawing (CeTZ).

## Smooth value trackers

In the HTML export a `tracked` object is rendered by Typst at sampled values (`config-scene(samples-per-second: ..)`, default 30) and the player shows the latest sample. With `interpolate: true` the player instead blends neighbouring samples number by number, wherever their SVG structure matches. That gives smooth motion from far fewer samples, so about 10 per second is usually enough:

```typst
#show: simple-theme.with(config-scene(samples-per-second: 10))

dot: sc.tracked(x: -2, interpolate: true, v => sc.cetz-obj({
  circle((v.x, v.x * v.x), radius: .1)
})),
```

Use it only when the drawing changes **continuously** with its values. A drawing that rounds (`calc.floor(v.n)`), branches or switches at thresholds would show invented in-between shapes, so leave those at the default. Waits, plateaus of a rate function and instant updates (`run-time: 0`) are kept exact in both modes.

## Timeline

| Entry | Description |
| --- | --- |
| `play(..anims, run-time: auto, rate: auto, lag-ratio: 0)` | Play animations together; `lag-ratio: 1` plays them one after another. A bare animation in the timeline is a one-animation `play`. |
| `wait(seconds)` | Pause the timeline. |
| `click` | Wait for a click: starts a new segment (subslide). Start the timeline with `click` to show the initial state first. |

Animations (each accepts `run-time` and `rate`):

| Animation | Effect |
| --- | --- |
| `fade-in(id, shift: none)`, `fade-out(id, shift: none)` | Fade, optionally moving by a vector. |
| `create(id)`, `uncreate(id)` | Draw strokes progressively; fills, glyphs and images fade. |
| `write(id)`, `unwrite(id)` | Reveal from left to right. |
| `shift(id, (dx, dy))`, `move-to(id, (x, y))` | Move by a vector / move the anchor (pivot for CeTZ objects) to a point. |
| `rotate-by(id, angle)`, `scale-by(id, factor)` | Rotate / scale around the pivot. |
| `move-along(id, path)` | Follow an array of points or a function `t => (x, y)`. |
| `indicate(id, scale: 1.2)` | Briefly enlarge. |
| `wiggle(id, scale: 1.1, angle: 3.6deg, n: 6)` | Rotate back and forth while briefly growing. |
| `circumscribe(id)`, `flash(id)`, `focus-on(id)`, `show-passing-flash(id)` | Emphasis effects; see "Emphasis". |
| `transform(source, target, mode: auto)` | Morph one outline into the other (HTML); see "Shape morphing". |
| `transform-matching(source, target)` | Morph symbol by symbol (HTML): glyphs and identical shapes that occur in both move to their new places, parts marked with the same `key` move as groups, everything else fades. |
| `set-value(id, name: value)` | Animate the values of a `tracked` object. |
| `add(id)`, `remove(id)` | Show / hide instantly. |

### Morphing equations

`transform-matching` is manim's `TransformMatchingShapes` for Typst equations:

```typst
objects: (
  lhs: sc.obj(at: (0, 1), $x^2 + 2 x + 1$),
  rhs: sc.obj(at: (0, -1), $(x + 1)^2$),
),
timeline: (sc.transform-matching("lhs", "rhs"),),
```

The same glyph at the same size matches automatically. If a glyph occurs several times, the pairing that moves the least wins. A symbol that changes size, for example when it moves into an exponent, is drawn from a different font variant and cannot be matched automatically. Mark such corresponding parts with the same `key` in both equations:

```typst
#let n = sc.key.with("n")
src: sc.obj($#n[$n$] dot x$),
dst: sc.obj($x^#n[$n$]$),
```

Both objects belong to the morph while it runs, so other animations of either of them at the same time are an error. The rate must start at 0 and end at 1. The player falls back to a crossfade where the overlay could not look right: if a part is rotated or clipped, or if another object drawn between the two (in declaration order) overlaps them. In PDF the target simply replaces the source.

### Shape morphing

`transform` morphs outlines point by point in the HTML export, like manim's `ReplacementTransform`: a circle bends into a square, a graph into another graph, `$x^2$` into `$sin x$`. Paths and glyphs are paired by their place within each object, their outlines are aligned, and fill, stroke and stroke width blend. Parts without a partner grow from or shrink to a point. The source is gone afterwards.

```typst
objects: (
  a: sc.obj(at: (3, 2), circle(radius: 1cm, fill: blue)),
  b: sc.obj(at: (9, 2), rect(width: 2cm, height: 2cm, fill: red)),
),
timeline: (sc.transform("a", "b"),),
```

Which one to use:

- `transform` changes shapes. It pairs parts by position, so for equations it gives a free-form morph.
- `transform-matching` keeps symbols: equal glyphs move to their new places, which suits rearranging an equation.
- `transform(.., mode: "fade")` crossfades the two objects while moving and scaling between their boxes.

`transform` falls back to that crossfade, exactly as with `mode: "fade"`, when a morph could not look right:

- either object is animated in another way while it morphs;
- either object is not fully visible or fully drawn at its end of the morph;
- the rate does not start at 0 and end at 1, such as `"there-and-back"`;
- either object contains an image, a gradient or a dashed stroke;
- another object drawn between the two overlaps them;
- overlapping parts swap their stacking order.

Single parts that cannot morph crossfade on their own, for example an open curve meeting a closed outline, or a stroke under non-uniform scaling. `mode: "shape"` makes the timeline rules above a compile error, so you learn when a morph would not happen. In PDF the target simply replaces the source.

Two animations may not change the same property of the same object at the same time (for example two `shift`s): run them one after another.

Rate functions are named as in manim: `"smooth"` (default), `"linear"`, `"rush-into"`, `"rush-from"`, `"there-and-back"`, `"ease-in-quad"`, `"ease-out-quad"`, `"ease-in-cubic"`, `"ease-out-cubic"`, `"ease-in-out-cubic"`, `"ease-in-out-sine"`; any function on `[0, 1]` works too.

## Graphs

Axes, plots and their companions are drawn natively, so no CeTZ is needed, and they work with every animation, including `create` and `transform`.

```typst
#let ax = sc.axes(x: (-3, 3, 1), y: (-2, 4, 1), at: (1, 0.5), size: (10, 6), labels: ($x$, $y$))
#let f(x) = x * x / 2
#sc.scene(
  width: 12cm,
  height: 7cm,
  objects: (
    ax: ax,
    graph: sc.plot(ax, f),
    area: sc.area(ax, f, domain: (0, 2)),
    t: sc.tracked(x: -2, interpolate: true, v => sc.group(
      sc.tangent(ax, f, v.x, df: x => x),
      sc.dot(ax, (v.x, f(v.x))),
    )),
  ),
  timeline: (
    sc.play(sc.create("ax"), sc.create("graph")),
    sc.fade-in("area"),
    sc.click,
    sc.fade-in("t"),
    sc.set-value("t", x: 2, run-time: 3),
  ),
)
```

**Coordinates.** `axes(x: (min, max, step), y: (..), at:, size:)` places the plot rectangle with its bottom-left corner at `at`, in scene coordinates, and `size` scene units wide and tall. Each axis line lies at the other axis' 0 if it is in range, else at its edge. `c2p(ax, (x, y))` converts axis coordinates to scene coordinates, for `at:`, `move-to` and `move-along`. The mapping is fixed when the axes are made; it does not follow later animations of the axes object.

| Helper | Description |
| --- | --- |
| `axes(.., ticks:, numbers:, grid:, tips:, labels:)` | `numbers: auto` labels every tick. It also takes an array of values or `(value, content)` pairs, or `(x: .., y: ..)`. |
| `plot(ax, f, domain:, samples: 128, discontinuities: ())` | The graph of `f`, clipped to the plot rectangle. |
| `dot(ax, (x, y), radius: 2.5pt)` | A dot. |
| `tangent(ax, f, x, length: 2, df: none)` | The tangent at `x`, `length` scene units long on screen. `df` is the derivative; otherwise a central difference is used. |
| `secant(ax, f, x1, x2, guides: false)` | The secant; `guides: true` adds the Δx and Δy legs and labels. |
| `area(ax, f, domain: (a, b), g: none, neg-fill:)` | The region between `f` and `g` (default: the x axis). Parts where `f < g` use `neg-fill`. |
| `riemann(ax, f, domain:, n:, mode: "left")` | `n` Riemann rectangles (`"left"`, `"right"` or `"mid"`). Rectangles below the axis use `neg-fill`. |
| `v-line(ax, (x, y))`, `h-line(ax, (x, y))` | Dashed lines from the axes to a point. |
| `graph-path(ax, f)` | A path along the graph, for `move-along`. |

**Gaps.** `f` may return `none` where it is undefined, for example `x => if x < 0 { none } else { calc.sqrt(x) }`. The graph or area is split there. Typst errors such as a square root of a negative number cannot be caught, so guard them that way. `discontinuities: (0,)` splits a graph at those x values and never evaluates `f` there, for example for `x => 1 / x`.

**Smooth trackers.** Every part of a graph is drawn with the same kind of segments, so its SVG structure stays the same while its numbers change. A `tracked` graph object with `interpolate: true` is then interpolated by the player across the whole animation; a tangent sweeping through slope 0 is no exception. The structure changes, and the player falls back to discrete samples, only when the number of parts changes:

- a different `samples` or `n`;
- ticks or numbers appearing;
- a graph leaving the plot rectangle or crossing a gap;
- a label whose text changes.

## Emphasis

**Annotations** are objects that stay. They show in PDF and handouts too, and `create` draws them in:

- `surround(of: "eq", buff: 0.15, shape: "rect" | "circle", radius: 0pt)` draws a rectangle, optionally with rounded corners, or a circle around the object `eq`.
- `brace(of: "eq", side: bottom, label: [..], gap: 0.15)` draws a curly brace along one side, with an optional label outside it.

Both measure their target where it is laid out, with its initial values. They do not follow later animations of it. To emphasise part of an equation, make that part an object of its own and annotate it.

**Effects** exist only while they play, in the HTML export:

| Animation | Effect |
| --- | --- |
| `circumscribe(id, shape: "rect", time-width: 0.3, fade: false)` | An outline runs around the object once. `fade: true` draws it in, holds it and fades it out. |
| `flash(id or (x, y), lines: 12, radius: auto)` | Lines flash outwards. |
| `focus-on(id or (x, y))` | A spotlight shrinks onto the object or point. |
| `show-passing-flash(id, time-width: 0.3)` | Only a window of the object's strokes runs along them; the object is invisible afterwards. Use it on a highlighted copy of a curve. |
| `wiggle(id, scale: 1.1, angle: 3.6deg, n: 6)` | The object rotates back and forth while it briefly grows. |

`circumscribe`, `flash` and `focus-on` measure their target when they start. An outline does not follow an object that moves during the effect, but a `circumscribe` played after a `shift` surrounds the shifted object. `create` and `show-passing-flash` both change how strokes are drawn, so they cannot overlap on the same object.

## 3D scenes

Give a scene a `camera` to add 3D objects, in the spirit of manim's `ThreeDScene`. Typst computes the geometry. In the HTML export the player projects and depth-sorts it on every frame, so camera moves are smooth and the audience can look around by dragging. The PDF shows the same projection at the end of each step.

```typst
#sc.scene(
  width: 24cm,
  height: 10cm,
  camera: sc.camera(phi: 70deg, theta: -60deg, zoom: 1.3),
  objects: (
    axes: sc.axes3d(x: (-3, 3), y: (-3, 3), z: (-1.5, 2)),
    surf: sc.surface(
      f: (x, y) => calc.sin(x) * calc.cos(y),
      x: (-3, 3), y: (-3, 3),
      fill: gradient.linear(..color.map.viridis),
      shade: true,
    ),
    top: sc.label3d((1.57, 0, 1.35), [max]),
    formula: sc.obj(at: (0.4cm, 0.3cm), anchor: left + top, $z = sin x cos y$),
  ),
  timeline: (
    sc.play(sc.create("axes"), sc.fade-in("surf")),
    sc.click,
    sc.rotate-camera(by: 120deg, run-time: 4),
    sc.move-camera(phi: 10deg, zoom: 1.1),
  ),
)
```

**Camera.** `camera(phi:, theta:, zoom:, focal:, center:, at:, unit:)`:
- `phi` is the polar angle from the $z$ axis (0° looks straight down) and `theta` the azimuth, as in manim.
- `focal: none` is orthographic; a number is the focal distance for perspective.
- `move-camera(phi:, theta:, zoom:, focal:, center:)` animates any of these.
- `rotate-camera(by:)` orbits around the vertical axis.
- Angles are taken literally: from 350° to 10° the camera turns back by 340°; ask for 370° to go the short way.

**3D objects:**

| Object | Description |
| --- | --- |
| `surface(f: (x, y) => z, x:, y:)` or `surface(fn: (u, v) => (x, y, z), u:, v:)` | A mesh with `samples: (24, 24)` cells. `fill` is a colour, a gradient (by height) or `(x, y, z) => color`; `shade: true` adds simple lighting. |
| `curve3d(t => (x, y, z), t: (a, b))`, `line3d(..points)` | Curves and polylines. |
| `vector3d(from, to)` | An arrow. |
| `point3d(p)`, `polygon3d(..points)` | A point; a flat convex polygon. |
| `axes3d(x:, y:, z:, labels:)` | Axes with tips, tick marks and labels. |
| `label3d(p, body, depth: false)` | Typst content at a 3D point, always facing the viewer. It is drawn above the geometry; with `depth: true` it is sorted with it. |
| `group3d(..objects)` | Several 3D objects animated as one. |

A `tracked` object may return a 3D object, for example a surface whose shape depends on a value. With `interpolate: true` its points are blended smoothly. The number and order of points must not depend on the values.

**Animations of 3D objects:**
- `rotate-3d(id, angle, axis: "z", about: auto)` rotates about a world axis, through the object's centre by default.
- `shift-3d(id, (dx, dy, dz))` moves it.
- `fade-in`, `fade-out`, `add`, `remove`, `create` (draws lines progressively) and `set-value` also apply.
- Rotations are applied in timeline order, so rotating about $y$ and then about $x$ differs from the reverse, as it should.

**Layers.** All 3D objects of a scene share one layer, sorted by depth. 2D objects (`obj`, `cetz-obj`) are drawn in front of it, or behind it with `behind: true`.

**In the HTML export:**
- drag a 3D scene to look around and use the mouse wheel to zoom;
- <kbd>0</kbd> eases back to the scripted view;
- on the next (or previous) click of the same scene, the view turns back to the script smoothly over about a second while the animation plays; grab the scene again to stop it;
- dragging never advances the slide;
- the presenter window shows the same view.

**Limits:**
- Depth sorting is per triangle and line segment (painter's algorithm), so intersecting surfaces or long faces can be ordered imperfectly.
- Transparent surfaces are not sorted correctly.
- Sizes of points, arrowheads, strokes and labels are in screen space.
- Large tracked meshes make big files: `config-scene(max-geometry: ..)` limits them, and about 10–12 samples per second with `interpolate: true` are plenty.

## Configuration

```typst
#show: simple-theme.with(
  config-scene(
    run-time: 1,             // default duration in seconds
    rate: "smooth",          // default rate function
    samples-per-second: 30,  // tracked objects in the HTML export
    max-samples: 241,        // per tracked object and segment; exceeding it is an error
  ),
)
```

## Handouts and articles

Handout and article mode show one state per scene, chosen with `scene(handout: ..)`: `auto` (the end), a segment number, or `"start"`. Use it when the last segment fades things out.

## HTML export

```sh
pip install touying            # touying-exporter
touying compile slides.typ     # writes slides.html
```

The exporter compiles with `--input touying-scene=html`. In that mode every scene object is wrapped in a labelled group and each page carries a description of its animation, which the player in the HTML file evaluates. Glyphs are stored once for the whole deck and the file is compressed, so it stays small and works offline. Keys: <kbd>→</kbd>/<kbd>Space</kbd>/click next, <kbd>←</kbd> back, <kbd>R</kbd> replay, <kbd>N</kbd> notes, <kbd>F</kbd> fullscreen, <kbd>P</kbd> presenter window.

The presenter window (<kbd>P</kbd> or <kbd>S</kbd>) shows the current page live, the next page, your speaker notes (<kbd>A−</kbd>/<kbd>A+</kbd> change their size) and a timer that starts with your first click. <kbd>T</kbd> pauses it and *Reset* resets it. Navigate from either window. To present, move the audience window to the projector, click it and press <kbd>F</kbd>, since fullscreen applies to the window that receives the key. If the browser blocks the pop-up, allow pop-ups for the file and press <kbd>P</kbd> again; reloading the deck and pressing <kbd>P</kbd> rebuilds the presenter window.

To inspect what the player receives:

```sh
typst eval 'query(<touying-scene>).map(e => e.value)' --in slides.typ --input touying-scene=html
```

## Limitations

- A scene must sit at the top level of a slide body, not inside `uncover`, `only` or `alternatives`; use `#pause` before it to reveal it later.
- PDF shows partial opacity only approximately (paints are recoloured), and intermediate animation states only exist in the HTML export. PDF slides show the state at the end of each step; a step that ends part-drawn (a custom rate of `create` that does not end at 1) is shown fully drawn.
- `create` draws solid, unfilled strokes; everything else fades in. Shape morphs crossfade parts they cannot morph; see "Shape morphing".
- Tracked objects are re-rendered by Typst `samples-per-second` times per second, which costs compile time for long animations; `interpolate: true` needs far fewer samples.
