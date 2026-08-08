# experiments

Throwaway trials: spikes, one-off scripts, things tried and abandoned or not yet worth writing up.
Nothing here is guaranteed to work, be maintained, or survive the next cleanup pass — except the
file below.

- `verify-upstream-coordinates.sh` — every image coordinate in
  [`../lib/engines.nix`](../lib/engines.nix) checked against the registry that serves it, through
  the registry API. `--tags N` additionally lists what upstream is shipping right now, which is the
  question this repository deliberately cannot answer from its own data — it pins no versions
  anywhere. Reads the coordinates out of the catalogue rather than a second hand-kept list.

  **It has already earned its place, three times.** One project publishes a parallel line of tags
  for a whole-runtime rewrite, under names that are not versions at all — a language name, a
  major-version word, an `-edge` suffix — sitting in the same repository as ordinary semantic
  versions. One publishes under two coordinates in two registries at once, with the same version
  line in both; the catalogue records the one its own documentation uses. And a registry's tag list
  comes back in the registry's own order, which is neither chronological nor sorted: reading the
  last few tags of one of these repositories suggests a project four hundred releases behind where
  it actually is. All three would have been invisible to a check that only asked whether the
  coordinate resolves.

## Why this lives here and not in `checks/`

`checks/` is `nix flake check`-wired and evaluates offline. It can prove how a declaration
RESOLVES — and it does, exhaustively, including the store restatement, the side separation and the
manifests that actually come out. What it cannot prove is that a registry still serves a repository
today. That is a fact about the world: it changes without this repository changing, and asserting
it at eval time would need either network access from a pure evaluation or a snapshot that silently
goes stale.

So the split is deliberate and matches what every sibling repository does with its own coordinate
verification: eval-time checks for anything internal and deterministic, a hand-run script for
anything that depends on what upstream is shipping this week.

## What is deliberately NOT verified here

**Nothing about the client catalogue.** [`../lib/clients.nix`](../lib/clients.nix) is empty on
purpose — this repository claims no host package — so there is no name to check against Arch, the
AUR or nixpkgs. The day an entry lands, the sibling repositories already carry the verification
contract to copy: four independent sources per name, a forced nixpkgs attribute rather than an
existence check, and a cross-check of the command surface.

**Nothing about versions.** The catalogue names repositories and no versions at all, because which
version a workload runs is a value supplied by whoever declares it — and because two of the four
kinds here have shipped a whole-runtime rewrite under the same name. Checking that a repository
exists proves nothing about the tag somebody actually deploys, which is exactly why `--tags` prints
them instead of asserting one.

**Whether a mount path is still where the software writes.** That is the field this catalogue is
most likely to be wrong about eventually, and there is no honest way to check it from outside the
running software: the answer lives in an image's own defaults, not in a registry's metadata. It is
verified by reading upstream's own documented deployment and by running it, and it is what the
`note` on each entry exists to record.

If something in here turns out to matter in a different way, distil the actual finding into
[`../studies/`](../studies/README.md) and let the experiment stay disposable (or delete it).

See the main [README](../README.md) for the project itself.
