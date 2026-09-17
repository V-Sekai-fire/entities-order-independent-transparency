A box stack and a hair cap that draw the engine's froxel order-independent transparency and check it against sorted blending.

The engine is `4-entities/godot-oit` (`V-Sekai-fire/entities-godot` at
`feat/oit-avboit`), which patches adaptive volumetric boundary OIT
(Drobot, [SIGGRAPH 2025](https://advances.realtimerendering.com/s2025/content/AVBOIT_SIG2025_MDROBOT-final.pdf))
into the Mobile and Forward+ renderers. The patch exists so a CAD view can
turn parts transparent and stay correct from every angle (RFD 2254); the hair
cap is a stress fixture, not a deliverable. This project is its design, its picture and its
gate: the Lean 4 specification the engine's C++ is held to, and two
scenes captured with the technique on and off. `scenes/stack.tscn` is
three half-alpha boxes overlapping in depth; `scenes/hair.tscn` is a cap
of 600 half-alpha strands, 12 segments each, built by
`scenes/hair_strands.gd` and sorted against the camera every frame.

## Run and check

```sh
<godot> --path .                            # the hair, OIT on
checks/run.sh <godot>                       # the check matrix and its controls
videos/run.sh <godot>                       # the recordings and their playback check
cd lean && lake build Oit                   # the specification and its controls
```

`checks/check_order.gd` captures four frames, sorted and scrambled with
OIT on and off, and compares whole images:

- parity: OIT on matches sorted blending except in a silhouette band no
  wider than a froxel tile, counted against a bound;
- scramble: giving the front box a lower render priority, or reversing
  the strand segments to front-to-back, visibly breaks sorted blending;
- order: the same scramble leaves the OIT image unchanged.

`checks/run.sh` runs each scene mono, under 4x MSAA, and in stereo
through the built-in mobile VR interface (`--stereo`, both eyes compared),
with the mono run as the baseline for the others, on the Mobile renderer
and again on Forward+ (`--rendering-method`, rows prefixed
`forward_plus_`). `--plant` skips the
scramble while claiming it, and `--occlude` stops the render loop as an
occluded macOS window does; both controls must fail. The check draws to a
window, so it does not run headless.

`videos/record.gd` records 480 frames at 1280x720 through the engine's
Movie Maker into CineForm Matroska, four phases of 120 frames (OIT on
sorted, sorted blending sorted, sorted blending scrambled, OIT on
scrambled) while the scene turns with a period of two phases.
`videos/check_video.gd` plays the file back through the engine's decoder
and pairs frames by pose: sorted blending against OIT scrambled must
agree within the silhouette band, and OIT sorted against scrambled
blending must differ by more than the planted recording does.
`videos/CITATION.cff` names the recordings.

`addons/vsekai_godot_mcp` is a runtime bridge for driving a running
instance from outside; it is an autoload and takes no part in the checks.

## The engine patch

Enable `rendering/oit/enabled`; the other keys under `rendering/oit/`
are documented in the engine's `ProjectSettings` reference. The technique
hooks the Mobile and Forward+ transparent passes directly, with no
per-camera opt-in and no compositor effect; the Compatibility renderer
ignores the setting. Under MSAA, Mobile resolves depth in the opaque pass
and transparents accumulate at one sample against it, so their silhouettes
lose MSAA while opaque edges keep it. Forward+ resolves depth by compute
into a storage texture nothing can attach, so there the accumulation keeps
the sample count and the resolve averages the per-sample results
(`lean/Oit/Resolve.lean`, `resolveSamples`). `checks/run.sh` measures
both bands against the mono one, and the stack's MSAA band reads 1701
pixels on Mobile against 844 on Forward+. Stereo needs
`xr/shaders/enabled`.

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
carries the same tables against `oit_math.h`, and `Oit/Tables.lean`
folds an FNV-1a hash over 4096 generated rows of the slice curve, the
extinction packing and the stereo lookup that both sides pin to one
literal, so a drift between the two fails one command on either side.
`.github/workflows/lean.yml` builds the library on every push.
