# entities-order-independent-transparency

An engine project that checks froxel order-independent transparency on overlapping boxes and hair strands against sorted blending.

## What it is for

It is the test stack for the engine patch that lets transparent parts of a computer-aided design assembly composite correctly in any draw order. RFD 2254 in `manuals-weftspun` owns the patch and the reason for it.

## Build and run

Both commands take the path to an engine build that carries the patch. The first opens the stack; the second runs the order check with its planted controls.

```sh
<engine> --path .
checks/run.sh <engine>
```

The Lean specification builds with `lake build Oit` in `lean`.

## Licence

Apache-2.0 OR MIT; see LICENSE-APACHE and LICENSE-MIT.
