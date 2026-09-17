A three-box stack that draws the engine's froxel order-independent transparency and checks it against sorted blending.

The engine is `4-entities/godot-oit` (`V-Sekai-fire/entities-godot` at
`feat/oit-avboit`), whose `modules/oit` implements adaptive volumetric
boundary OIT. This project is its picture and its gate: three half-alpha
boxes overlapping in depth, captured with the technique on and off.

## Run and check

```sh
<godot> --path .                            # the stack, OIT on
checks/run.sh <godot>                       # the order check and its planted control
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
