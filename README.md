A box stack and a hair cap that draw the engine's froxel order-independent transparency and check it against sorted blending.

```sh
<godot> --path .                            # the hair, OIT on
checks/run.sh <godot>                       # the check matrix and its controls
videos/run.sh <godot>                       # the recordings and their playback check
cd lean && lake build Oit                   # the specification and its controls
checks/check_order.gd # captures four frames, sorted and scrambled with
OIT on and off, and compares whole images:
```
