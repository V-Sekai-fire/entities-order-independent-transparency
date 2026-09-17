import Oit.SliceCurve
import Oit.Extinction
import Oit.Views

/-!
# The Lean-vs-C++ hash ladder

`hashTables 4096` folds an FNV-1a hash over the quantised outputs of
`depthToSlice`, `packExtinction` and `packedU` on 4096 LCG-generated
inputs, and pins the result by `native_decide`. `test_oit.cpp` in the
engine computes the same hash from `oit_math.h` on the same generator
and asserts the same literal, so a hand-edit of either side fails one
command.

Only quantised outputs are folded. `sliceUV` and `packExtinction` both
pass through `log`, and a libm that differs by an ulp between the two
sides would move a raw `Float32` but not a slice index or a packed
extinction, except at a bin edge. `packedU` is division and addition
only, so its bits are exact and go in whole.
-/

namespace Oit.Tables

open Oit.SliceCurve Oit.Extinction Oit.Views

/-- One step of the Numerical Recipes LCG, wrapping in `UInt32`. -/
@[inline] def lcg (x : UInt32) : UInt32 := x * 1664525 + 1013904223

/-- The top 24 bits of `x` as a float in `[0, 1)`, exact on both sides. -/
@[inline] def unit (x : UInt32) : Float32 := (x >>> 8).toFloat32 / 16777216.0

/-- Folds one word into an FNV-1a hash, low byte first. -/
def fnv1a (h w : UInt32) : UInt32 :=
  let step := fun (h : UInt32) (b : UInt32) => (h ^^^ (b &&& 0xFF)) * 16777619
  step (step (step (step h w) (w >>> 8)) (w >>> 16)) (w >>> 24)

/-- The three quantised outputs of one step, from four LCG words. -/
def row (w1 w2 w3 w4 : UInt32) : UInt32 × UInt32 × UInt32 :=
  let k := unit w1 * 200.0 + 0.05
  let z := unit w2 * 600.0
  let view := (w4 % 2).toNat
  (depthToSlice 0.1 500.0 k 128 z,
   packExtinction (unit w3),
   (packedU 320 2 view (unit w4)).toBits)

/-- The ladder: `n` rows from seed `0x9E3779B9`, `perturb` adds one to the
    packed extinction of row 7 so a control can pin a different literal. -/
def hashTablesWith (n : Nat) (perturb : Bool) : UInt32 :=
  let rec go (i : Nat) (x h : UInt32) : UInt32 :=
    match i with
    | 0 => h
    | i + 1 =>
      let w1 := lcg x
      let w2 := lcg w1
      let w3 := lcg w2
      let w4 := lcg w3
      let (s, e, u) := row w1 w2 w3 w4
      let e := if perturb && n - (i + 1) == 7 then e + 1 else e
      go i w4 (fnv1a (fnv1a (fnv1a h s) e) u)
  go n 0x9E3779B9 2166136261

def hashTables (n : Nat) : UInt32 := hashTablesWith n false

def hashTablesPerturbed (n : Nat) : UInt32 := hashTablesWith n true

/-- The literal `test_oit.cpp` carries; read off `#eval` once and never edited by hand. -/
example : hashTables 4096 = 0x9371EF76 := by native_decide

/-- Control: one fewer row moves the hash. -/
example : hashTables 4095 ≠ hashTables 4096 := by native_decide

/-- Control: one perturbed row moves the hash, to a literal the C++ control carries too. -/
example : hashTablesPerturbed 4096 = 0x2AFAE94D := by native_decide

example : hashTablesPerturbed 4096 ≠ hashTables 4096 := by native_decide

end Oit.Tables
