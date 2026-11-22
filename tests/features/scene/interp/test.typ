// Interpolated trackers: hold, progress (with a plateau rate) and time spans,
// a final instant update, and a non-monotone rate in the second segment.
#import "/lib.typ": *
#import themes.simple: *
#import "defs.typ": *

#show: simple-theme.with(aspect-ratio: "16-9")

== Interpolation

#interp-scene(
  (
    dot: sc.tracked(x: 1, y: 1, interpolate: true, dot-fn),
    wave: sc.tracked(k: 1, interpolate: true, wave-fn),
  ),
  (
    sc.wait(0.5),
    sc.play(
      sc.set-value("dot", x: 5, run-time: 2, rate: plateau),
      sc.set-value("wave", k: 3, run-time: 2),
    ),
    sc.set-value("dot", y: 3, run-time: 1, rate: "linear"),
    sc.play(
      sc.set-value("dot", x: 8, run-time: 1, rate: "linear"),
      sc.set-value("dot", y: 1, run-time: 0.5, rate: "smooth"),
    ),
    sc.set-value("dot", x: 9, run-time: 0),
    sc.click,
    sc.set-value("wave", k: 1, rate: "there-and-back", run-time: 1.5),
  ),
)
