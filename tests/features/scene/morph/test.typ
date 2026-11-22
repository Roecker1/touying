// transform-matching: symbol-by-symbol equation morphs and their fallbacks.
#import "/lib.typ": *
#import themes.simple: *

#show: simple-theme.with(aspect-ratio: "16-9")

#let sc = touying-scene
#let morph(id, objects, timeline: auto, width: 20cm, height: 4cm) = sc.scene(
  id: id,
  width: width,
  height: height,
  objects: objects,
  timeline: if timeline == auto {
    (sc.transform-matching("src", "dst", run-time: 1),)
  } else { timeline },
)

== Fidelity

#let same = $#sc.key("k")[$a$] + #text(fill: red)[$b$] = (c + d) / 2$
#morph("fid", (
  src: sc.obj(at: (10, 2), same),
  dst: sc.obj(at: (10, 2), same),
))

== Occluder

#morph("occ", (
  src: sc.obj(at: (4, 2), $x + y$),
  wall: sc.obj(at: (10, 2), rect(width: 3cm, height: 2cm, fill: gray)),
  dst: sc.obj(at: (16, 2), $y + x$),
))

== Factor

#morph("factor", (
  src: sc.obj(at: (10, 3), $x^2 + 2 x + 1$),
  dst: sc.obj(at: (10, 1.2), $(x + 1)^2$),
))

== Repeated glyphs

#morph("rep", (
  src: sc.obj(at: (6, 2), $a + a$),
  dst: sc.obj(at: (14, 2), $2 a$),
))

== Keys

#morph("keys", (
  src: sc.obj(at: (10, 2), $#sc.key("n")[$n$] dot x$),
  dst: sc.obj(at: (10, 2), $x^#sc.key("n")[$n$]$),
))

== Colour

#morph("colour", (
  src: sc.obj(at: (10, 2), $a + b$),
  dst: sc.obj(at: (10, 2), $a + #text(fill: red)[$b$]$),
))

== Rotated

#morph(
  "rot",
  (
    src: sc.obj(at: (6, 2), $p + q$),
    dst: sc.obj(at: (14, 2), $q + p$),
  ),
  timeline: (
    sc.rotate-by("src", 30deg),
    sc.transform-matching("src", "dst"),
  ),
)

== Chained and simultaneous

#morph(
  "chain",
  (
    src: sc.obj(at: (5, 3), $a b$),
    mid: sc.obj(at: (5, 3), $b a$),
    end: sc.obj(at: (5, 3), $b a c$),
    p: sc.obj(at: (15, 3), $u + v$),
    q: sc.obj(at: (15, 1), $v + u$),
  ),
  timeline: (
    sc.play(sc.transform-matching("src", "mid"), sc.transform-matching(
      "p",
      "q",
    )),
    sc.transform-matching("mid", "end"),
    sc.transform-matching("q", "p", run-time: 0),
  ),
)
