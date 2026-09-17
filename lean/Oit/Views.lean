/-!
# AVBOIT under stereo multiview

Vulkan has no 3D texture arrays, so the two eyes share one froxel grid
and one transmittance texture, packed side by side along X: view `v`
owns columns `v * dimsX .. v * dimsX + dimsX - 1`. The splat writes
`froxel_x + v * dimsX`; the lookup maps the eye's own screen `u` into
its slab of the packed texture.

The lookup clamps `u` to the half-texel band before packing. Without
the clamp, `u = 1` in view 0 lands on the boundary between the slabs
and the sampler reads view 1's first column: the right edge of the left
eye would be modulated by the left edge of the right eye.
-/

namespace Oit.Views

/-- The packed column a fragment at froxel `x` of view `view` splats into. -/
def packedColumn (dimsX view x : Nat) : Nat := view * dimsX + x

/-- The lookup `u` in the packed texture for screen `u` of `view`. -/
def packedU (dimsX viewCount view : Nat) (u : Float32) : Float32 :=
  let half := 0.5 / dimsX.toFloat32
  let c := if u < half then half else if u > 1.0 - half then 1.0 - half else u
  (c + view.toFloat32) / viewCount.toFloat32

/-- Control: the same map without the clamp. -/
def packedUUnclamped (viewCount view : Nat) (u : Float32) : Float32 :=
  (u + view.toFloat32) / viewCount.toFloat32

/-- The column a packed `u` samples with nearest filtering. -/
def sampledColumn (dimsX viewCount : Nat) (packed : Float32) : Nat :=
  (packed * (dimsX * viewCount).toFloat32).floor.toUInt32.toNat

/-- Packed columns are distinct across the two views of a 4-wide grid. -/
example :
    (List.range 2).all fun v => (List.range 4).all fun x =>
      (List.range 2).all fun v' => (List.range 4).all fun x' =>
        (packedColumn 4 v x == packedColumn 4 v' x') == (v == v' && x == x') := by
  native_decide

/-- A pixel centre looks up the column it splatted into, both eyes, at
    the froxel width the module ships with. -/
example :
    (List.range 2).all fun v => (List.range 320).all fun x =>
      sampledColumn 320 2 (packedU 320 2 v ((x.toFloat32 + 0.5) / 320.0)) == packedColumn 320 v x := by
  native_decide

/-- The right edge of view 0 stays in view 0's last column. -/
example : sampledColumn 4 2 (packedU 4 2 0 1.0) == 3 := by native_decide

/-- The left edge of view 1 reads view 1's first column. -/
example : sampledColumn 4 2 (packedU 4 2 1 0.0) == 4 := by native_decide

/-- Control: unclamped, the right edge of view 0 reads view 1's first column. -/
example : sampledColumn 4 2 (packedUUnclamped 2 0 1.0) == 4 := by native_decide

/-- One view is the identity map, so the mono path is unchanged. -/
example :
    (List.range 320).all fun x =>
      sampledColumn 320 1 (packedU 320 1 0 ((x.toFloat32 + 0.5) / 320.0)) == x := by
  native_decide

end Oit.Views
