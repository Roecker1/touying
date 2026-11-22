// Renders the tracked drawings of test.typ at exact values given as inputs
// (`--input x=.. --input y=.. --input k=..`), without animation.
#import "/lib.typ": *
#import themes.simple: *
#import "defs.typ": *

#show: simple-theme.with(aspect-ratio: "16-9")

#let input(name) = float(sys.inputs.at(name, default: "1"))

== Interpolation

#interp-scene(
  (
    dot: sc.tracked(x: input("x"), y: input("y"), dot-fn),
    wave: sc.tracked(k: input("k"), wave-fn),
  ),
  (),
)
