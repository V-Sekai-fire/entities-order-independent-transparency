A three-box stack that draws the engine's froxel order-independent transparency and checks it against sorted blending.

The engine is `4-entities/godot-oit` (`V-Sekai-fire/entities-godot` at
`feat/oit-avboit`), which patches adaptive volumetric boundary OIT
(Drobot, [SIGGRAPH 2025](https://advances.realtimerendering.com/s2025/content/AVBOIT_SIG2025_MDROBOT-final.pdf))
into the Mobile renderer. This project is its design, its picture and its
gate: the Lean 4 specification the engine's C++ is held to, and three
half-alpha boxes overlapping in depth, captured with the technique on and off.

## Run and check

```sh
<godot> --path .                            # the stack, OIT on
checks/run.sh <godot>                       # the order check and its planted control
cd lean && lake build Oit                   # the specification and its controls
```

`checks/check_order.gd` captures four frames, sorted and scrambled with
OIT on and off, and compares whole images:

- parity: OIT on matches sorted blending except in a silhouette band no
  wider than a froxel tile, counted against a bound;
- scramble: giving the front box a lower render priority visibly breaks
  sorted blending;
- order: the same scramble leaves the OIT image unchanged.

`--plant` skips the scramble while claiming it, and the check must fail.
The check draws to a window, so it does not run headless.

## The engine patch

Enable `rendering/oit/enabled`; the other keys under `rendering/oit/`
are documented in the engine's `ProjectSettings` reference. The technique
hooks the Mobile transparent pass directly, with no per-camera opt-in and
no compositor effect. Forward+ and the Compatibility renderer ignore the
setting; with MSAA the Mobile renderer warns once and draws transparents
sorted.

Following slide 47 of the paper, each frame: clear the extinction grid,
rasterise the Mix-blended transparents into it at tile resolution
(`MODE_OIT_SPLAT`, `atomicAdd` of packed `-log(1 - a)` into a `uint`
SSBO, one froxel per covered column), prefix-sum along Z into an RGBA8 3D
transmittance texture (`oit_integrate.glsl`, one workgroup per column),
draw opaques, accumulate every transparent in any order into
`colour += c * a * T`, `alpha += a * T` and `extinction += -log(1 - a)`
with `T` the transmittance in front of the fragment
(`MODE_OIT_ACCUMULATE`), and composite
`colour * (1 - exp(-extinction)) / alpha` over the opaque framebuffer
(`oit_resolve.glsl`). Stereo packs the two eyes side by side along X in
the one grid, and the lookup clamps to the eye's own slab.

The engine files are `servers/rendering/renderer_rd/effects/oit.{h,cpp}`
and `oit_math.h`, `shaders/effects/oit_{voxelize,integrate,resolve}.glsl`,
the `oit_*` functions in `scene_forward_mobile_inc.glsl`, and
`tests/servers/rendering/test_oit.cpp`, run through
`misc/scripts/oit_tests.sh`.

Quest 3 (Adreno 740, Vulkan 1.1) is the load-bearing target: the splat
adds into a plain SSBO because atomic-image support there is limited, the
prefix sum stays inside one workgroup so no cross-workgroup barrier is
needed, and 128 slices of one `uint` at 320x180 is about 28 MiB.

## The specification

`lean/Oit/` pins the slice curve, the extinction packing, the froxel
layout, the splat, the lookup, the prefix sum, the weighted resolve and
the stereo packing as Lean 4 definitions with `native_decide` examples,
each paired with the control that a wrong version fails. `test_oit.cpp`
carries the same tables against `oit_math.h`, so a drift between the two
fails one command on either side.
