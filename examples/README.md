# examples

Placeholder values that make this repository's checks real, and the shortest readable answer to
"what does a declaration actually look like".

- [`all/values.nix`](all/values.nix) — one complete surface, on all three sides: a capture surface
  whose corpus is rows, a notebook whose corpus is Markdown files and whose opt-in authentication is
  switched on, an archive with its own namespace, its own Secret and a public URL joined from an
  origin it supplies and a path it does not, and a renderer that mounts nothing and scales to zero.
  `nix flake check` renders it through the real app grammar and the real renderer and then asserts
  the manifests field by field, so a module that stops evaluating — or that grows a required value
  nobody supplies — fails in CI rather than in somebody's cluster.

**Nothing in here is real.** Every namespace, node path, Secret name, image reference, URL, band and
slot number is invented for the check. That is not a disclaimer, it is the design: every one of
those is a fleet fact, and this repository supplies none of them — see the main
[README](../README.md).
