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
| `tracked(fn, ..values, interpolate: false)` | Like manim's `ValueTracker` + `always_redraw`: `fn` receives the current values and returns an `obj` or `cetz-obj`. |

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
| `transform(source, target)` | Crossfade while moving and scaling between both bounding boxes. |
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

Two animations may not change the same property of the same object at the same time (for example two `shift`s): run them one after another.

Rate functions are named as in manim: `"smooth"` (default), `"linear"`, `"rush-into"`, `"rush-from"`, `"there-and-back"`, `"ease-in-quad"`, `"ease-out-quad"`, `"ease-in-cubic"`, `"ease-out-cubic"`, `"ease-in-out-cubic"`, `"ease-in-out-sine"`; any function on `[0, 1]` works too.

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
- PDF shows partial opacity only approximately (paints are recoloured), and intermediate animation states only exist in the HTML export.
- `create` draws solid, unfilled strokes; everything else fades in. `transform` and `transform-matching` move and crossfade parts; they do not morph one outline into another.
- Tracked objects are re-rendered by Typst `samples-per-second` times per second, which costs compile time for long animations; `interpolate: true` needs far fewer samples.
