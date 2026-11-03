/-!
# Hillis-Steele inclusive prefix sum along Z

`oit_integrate.glsl` runs one workgroup per (x, y) column, 128 threads
along local_x (Metal caps local_z below 128 on Apple Silicon), and
each thread runs an inclusive prefix sum over `shared_extinction[0..127]`.

At iteration `stride = 1, 2, 4, ..., 64`, thread `z` reads the value
`shared_extinction[z - stride]` (if `z >= stride`) and adds it to
`shared_extinction[z]`. After `log2(sliceCount)` iterations the array
holds the inclusive prefix sum.

This module proves the algorithmic shape at the `Nat` level so
`native_decide` on decidable equality can pin correctness. The float
version at runtime shares the same control flow, and the SliceCurve
byte-comparison ladder covers float-side agreement separately.
-/

namespace Oit.PrefixSum

/-- Inclusive prefix sum reference. -/
def prefixSum (xs : Array Nat) : Array Nat := Id.run do
  let mut out : Array Nat := Array.mkEmpty xs.size
  let mut running : Nat := 0
  for x in xs do
    running := running + x
    out := out.push running
  return out

/-- Hillis-Steele one-step: `out[z] = xs[z] + (xs[z - stride] if z >= stride else 0)`. -/
def hillisStep (xs : Array Nat) (stride : Nat) : Array Nat := Id.run do
  let mut out : Array Nat := Array.mkEmpty xs.size
  for _hi : i in [0 : xs.size] do
    let self := xs[i]!
    let partner : Nat := if i ≥ stride then xs[i - stride]! else 0
    out := out.push (self + partner)
  return out

/-- Full Hillis-Steele scan, `stride := 1, 2, 4, ..., < size`. -/
def hillisScan (xs : Array Nat) : Array Nat := Id.run do
  let mut cur := xs
  let mut stride := 1
  while stride < xs.size do
    cur := hillisStep cur stride
    stride := stride * 2
  return cur

/-- Sample: length-8 unit array has prefix sum 1..8. -/
example : prefixSum #[1, 1, 1, 1, 1, 1, 1, 1]
        = #[1, 2, 3, 4, 5, 6, 7, 8] := by native_decide

/-- Sample: Hillis-Steele agrees with the reference on the unit array. -/
example : hillisScan #[1, 1, 1, 1, 1, 1, 1, 1]
        = #[1, 2, 3, 4, 5, 6, 7, 8] := by native_decide

/-- Sample: on a length-8 array with two spikes. -/
example :
    let xs := #[0, 0, 5, 0, 0, 3, 0, 0]
    hillisScan xs = prefixSum xs := by native_decide

/-- Sample: on a length-8 increasing array. -/
example :
    let xs := #[1, 2, 3, 4, 5, 6, 7, 8]
    hillisScan xs = prefixSum xs := by native_decide

/-- Sample: length-16 randomish. -/
example :
    let xs := #[3, 1, 4, 1, 5, 9, 2, 6, 5, 3, 5, 8, 9, 7, 9, 3]
    hillisScan xs = prefixSum xs := by native_decide

/-! ## Workgroup-sized arrays

64 and 128 are the two `slice_count` values the integrate shader
runs with, and the shapes below are the ones a froxel column
takes: empty, saturated, one surface at the near end, one at the
far end, and noise. -/

def zeros (n : Nat) : Array Nat := Array.replicate n 0
def saturated (n : Nat) : Array Nat := Array.replicate n 65535
def spikeAt (n i : Nat) : Array Nat := (zeros n).set! i 45426

/-- Numerical Recipes LCG, `mod 2^32`, masked to 16 bits. -/
def lcg (n : Nat) : Array Nat := Id.run do
  let mut out : Array Nat := Array.mkEmpty n
  let mut s : Nat := 12345
  for _ in [0 : n] do
    s := (s * 1664525 + 1013904223) % 4294967296
    out := out.push (s % 65536)
  return out

def agreesAt (n : Nat) : Bool :=
  [zeros n, saturated n, spikeAt n 0, spikeAt n (n - 1), lcg n].all
    fun xs => hillisScan xs == prefixSum xs

example : agreesAt 64 ∧ agreesAt 128 := by native_decide

/-- The saturated column's last entry is the whole sum. -/
example : (hillisScan (saturated 128))[127]! = 128 * 65535 := by native_decide

/-- A spike at the far end only reaches the last slice. -/
example : hillisScan (spikeAt 128 127) = (zeros 128).set! 127 45426 := by
  native_decide

/-- Control: a scan that skips the final stride disagrees. -/
def hillisScanSkipLast (xs : Array Nat) : Array Nat := Id.run do
  let mut cur := xs
  let mut stride := 1
  while stride * 2 < xs.size do
    cur := hillisStep cur stride
    stride := stride * 2
  return cur

example : hillisScanSkipLast (lcg 128) ≠ prefixSum (lcg 128) := by native_decide
example : hillisScanSkipLast (saturated 64) ≠ prefixSum (saturated 64) := by
  native_decide

/-! ## Chunked scan: up to 512 slices on 128 threads

`oit_integrate.glsl` gives each of the 128 threads `perThread = ceil(sliceCount / 128)` consecutive slices (1 to 4; one for 64 and 128 slices, the
case above). Thread `t` sums its chunk, the 128 chunk sums go through the Hillis-Steele scan above, and the thread then walks its own slices from the
sum of the threads before it (`incl[t] - sums[t]`). Slices past `sliceCount` read as 0 and are not written. -/

def chunkOf (xs : Array Nat) (per t : Nat) : Array Nat :=
  (Array.range per).map fun i => if t * per + i < xs.size then xs[t * per + i]! else 0

/-- The shader's two-level scan, in slice order. -/
def chunkedScan (xs : Array Nat) : Array Nat := Id.run do
  let per := (xs.size + 127) / 128
  let sums := (Array.range 128).map fun t => (chunkOf xs per t).foldl (· + ·) 0
  let incl := hillisScan sums
  let mut out : Array Nat := Array.mkEmpty xs.size
  for t in [0 : 128] do
    let mut running := incl[t]! - sums[t]!
    for i in [0 : per] do
      if t * per + i < xs.size then
        running := running + xs[t * per + i]!
        out := out.push running
  return out

def chunkedAgreesAt (n : Nat) : Bool :=
  [zeros n, saturated n, spikeAt n 0, spikeAt n (n - 1), spikeAt n (n / 2), lcg n].all
    fun xs => chunkedScan xs == prefixSum xs

/-- The four chunk sizes (1, 2, 3 and 4 slices a thread), and a size that is not a multiple of 128 so the last threads read padding. -/
example : chunkedAgreesAt 64 ∧ chunkedAgreesAt 128 ∧ chunkedAgreesAt 256 := by native_decide
example : chunkedAgreesAt 384 ∧ chunkedAgreesAt 512 ∧ chunkedAgreesAt 200 ∧ chunkedAgreesAt 500 := by native_decide

/-- The saturated 512-slice column's last entry is the whole sum. -/
example : (chunkedScan (saturated 512))[511]! = 512 * 65535 := by native_decide

/-- Controls. The old kernel (one slice a thread, so 128 slices at most) drops every slice past 127 on a 256-slice column;
    a chunked scan that forgets the threads before it, or that gives each thread one slice too few, disagrees with the reference. -/
def oldKernel (xs : Array Nat) : Array Nat :=
  hillisScan (xs.extract 0 128) ++ Array.replicate (xs.size - 128) 0

def chunkedNoOffset (xs : Array Nat) : Array Nat := Id.run do
  let per := (xs.size + 127) / 128
  let mut out : Array Nat := Array.mkEmpty xs.size
  for t in [0 : 128] do
    let mut running := 0
    for i in [0 : per] do
      if t * per + i < xs.size then
        running := running + xs[t * per + i]!
        out := out.push running
  return out

def chunkedShortChunk (xs : Array Nat) : Array Nat := Id.run do
  let per := xs.size / 128
  let sums := (Array.range 128).map fun t => (chunkOf xs per t).foldl (· + ·) 0
  let incl := hillisScan sums
  let mut out : Array Nat := Array.mkEmpty xs.size
  for t in [0 : 128] do
    let mut running := incl[t]! - sums[t]!
    for i in [0 : per] do
      if t * per + i < xs.size then
        running := running + xs[t * per + i]!
        out := out.push running
  return out

example : oldKernel (lcg 256) ≠ prefixSum (lcg 256) := by native_decide
example : oldKernel (saturated 512) ≠ prefixSum (saturated 512) := by native_decide
example : oldKernel (lcg 128) = prefixSum (lcg 128) := by native_decide
example : chunkedNoOffset (lcg 512) ≠ prefixSum (lcg 512) := by native_decide
example : chunkedShortChunk (lcg 200) ≠ prefixSum (lcg 200) := by native_decide

end Oit.PrefixSum
