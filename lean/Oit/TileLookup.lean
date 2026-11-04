import Oit.SliceCurve

/-!
# Tile-centre lookup and the front weight

The splat pass writes one sample per tile, at the tile centre. A fragment reads the transmittance at that same tile centre, and gives it the depth its own surface has there: its depth carried along the surface from the pixel to the tile centre.

Depth is not linear across the screen. For a flat triangle `1 / z` is: `dFdx (1 / z)` and `dFdy (1 / z)` are constant, so carrying the *inverse* depth to the tile centre is exact, and `z` carried the same way is only first order. At a tilt the first-order error grows with the square of the distance from the tile centre, enough to land the lookup one slice behind the surface's own splat. The surface then shades itself.

`scene_forward_clustered.glsl`: `oit_inv_c = 1 / z + dFdx (1 / z) * dx + dFdy (1 / z) * dy`, `oit_lookup_z = 1 / oit_inv_c * (1 - 4e-5)`.

The accumulation target holds half floats. `front` is the transmittance in front of the surface (`oit_front`); the stored weights are `rgb * alpha * front` and `alpha * front`. Behind three opaque-alpha layers `front` is about `1e-9`, below the smallest half float, the sum reads 0 and the resolve writes black. `oit_front = max (oit_front, 1e-3)` keeps the weights representable.
-/

namespace Oit.TileLookup

open Oit.SliceCurve (depthToSlice)

/-- A flat surface seen at a tilt: inverse depth is linear in the pixel column `x`. -/
def invZ (a b x : Float32) : Float32 := a + b * x
def trueZ (a b x : Float32) : Float32 := 1.0 / invZ a b x

/-- Carry the depth at pixel `x0` to the tile centre `xc`: first order in `z` (the first version). -/
def carryLinearZ (a b x0 xc : Float32) : Float32 :=
  let z := trueZ a b x0
  let dz := trueZ a b (x0 + 1.0) - z   -- dFdx (z) over one pixel
  z + dz * (xc - x0)

/-- Carry the inverse depth, then invert (the fix). Exact for a plane. -/
def carryInvZ (a b x0 xc : Float32) : Float32 :=
  let inv := invZ a b x0
  let dinv := invZ a b (x0 + 1.0) - inv   -- dFdx (1 / z) over one pixel
  1.0 / (inv + dinv * (xc - x0))

@[inline] def absF (x : Float32) : Float32 := if x < 0.0 then -x else x

/-- A surface at 2 m tilted so `1 / z` falls by 0.02 per pixel: at the pixel `z = 2`, three pixels along `z = 1.7857`. -/
example : absF (carryInvZ 0.5 0.02 0.0 3.0 - trueZ 0.5 0.02 3.0) < 1.0e-5 := by native_decide
example : absF (carryLinearZ 0.5 0.02 0.0 3.0 - trueZ 0.5 0.02 3.0) > 1.0e-2 := by native_decide

/-- Backwards along the surface too (a pixel right of the tile centre). -/
example : absF (carryInvZ 0.5 0.02 5.0 3.0 - trueZ 0.5 0.02 3.0) < 1.0e-5 := by native_decide

/-- At a grazing tilt the first-order error is far larger than a slice: 512 slices over a 0.6 m range are 1.2 mm each; the linear carry is off by more than 15 mm (over twelve slices), the inverse carry by less than 0.01 mm. -/
example : absF (carryLinearZ 0.5 0.02 0.0 3.0 - trueZ 0.5 0.02 3.0) > 0.015 := by native_decide
example : absF (carryInvZ 0.5 0.02 0.0 3.0 - trueZ 0.5 0.02 3.0) < 1.0e-5 := by native_decide

/-- Lands in the surface's own slice: the inverse carry gives the slice the splat used at the tile centre, the linear carry gives a different one. The range is 1.5 to 3 m, 512 slices, `k = (far - near) / near`. -/
def ownSlice (z : Float32) : UInt32 := depthToSlice 1.5 3.0 1.0 512 z
example : ownSlice (carryInvZ 0.5 0.02 0.0 3.0) = ownSlice (trueZ 0.5 0.02 3.0) := by native_decide
example : ownSlice (carryLinearZ 0.5 0.02 0.0 3.0) != ownSlice (trueZ 0.5 0.02 3.0) := by native_decide

/-- Stepping `4e-5` of the depth toward the camera never moves the lookup behind the surface: the lookup slice is at most the surface's own. It can step one slice in front, which reads a slice with nothing of this surface in it. -/
def bias (z : Float32) : Float32 := z * (1.0 - 4.0e-5)
example : ((List.range 200).all fun i =>
    let z : Float32 := 1.6 + i.toUInt32.toFloat32 * 0.007
    ownSlice (bias z) <= ownSlice z) = true := by native_decide

/-- The bias is small: at 2 m it is 0.08 mm, a fraction of the 1.2 mm slice. -/
example : absF (bias 2.0 - 2.0) < 1.0e-3 := by native_decide

/-! ## The front weight in half floats

The smallest positive half float is `2^-24`, about `5.96e-8`, and the smallest normal one `2^-14`, about `6.1e-5`. -/

def halfMinSubnormal : Float32 := 5.960464477539063e-8
def representable (x : Float32) : Bool := x >= halfMinSubnormal

/-- The extinction of one alpha-1.0 layer, `-ln (1 - 0.999)`, and the transmittance after `n` of them. -/
def layerT (n : Nat) : Float32 := Float32.exp (-(6.9077554 * n.toUInt32.toFloat32))

/-- Behind zero, one and two layers the weight `alpha * front` is representable; behind three it is not. -/
example : representable (layerT 0) && representable (layerT 1) && representable (layerT 2) = true := by native_decide
example : representable (layerT 3) = false := by native_decide
example : representable (layerT 5) = false := by native_decide

/-- The floor. -/
def floorFront (t : Float32) : Float32 := if t > 1.0e-3 then t else 1.0e-3

/-- With the floor every stacked depth keeps a representable weight, a normal half float. -/
example : ((List.range 12).all fun n => floorFront (layerT n) >= 6.1e-5) = true := by native_decide

/-- The floor does not touch a transmittance at or above it: a layer behind one opaque-alpha layer or less is unchanged. -/
example : (floorFront (layerT 0)).toBits = (layerT 0).toBits := by native_decide
example : (floorFront 0.5).toBits = (0.5 : Float32).toBits := by native_decide

/-- The resolve divides the weights back out: `colour = sum (c * a * w) / sum (a * w)`. A floor shared by all the layers of a pixel cancels. Two layers, red in front of blue, weights `w` and `w * 1e-9` (true) against the floored `w` and `1e-3 * w` -- the front layer dominates in both, within 0.1%. -/
def resolveRed (wFront wBack : Float32) : Float32 :=
  (1.0 * 1.0 * wFront + 0.0 * 1.0 * wBack) / (1.0 * wFront + 1.0 * wBack)
example : absF (resolveRed 1.0 1.0e-9 - 1.0) < 1.0e-6 := by native_decide
example : absF (resolveRed 1.0 1.0e-3 - 1.0) < 1.1e-3 := by native_decide

/-- A pixel whose own layers are all deep (the tile-centre sample saw nearer layers) still resolves to its own colour with the floor, instead of 0 / 0. Without it the weights are zero in half floats. -/
example : absF (resolveRed 1.0e-3 1.0e-3 - 0.5) < 1.0e-6 := by native_decide
example : (0.0 : Float32) / 0.0 != (0.0 : Float32) / 0.0 := by native_decide  -- NaN: the black pixel

end Oit.TileLookup
