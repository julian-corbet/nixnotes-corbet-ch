# studies

Written-up findings: things that were checked in [`../experiments/`](../experiments/README.md) or
paid for in a running deployment, turned out to matter, and are worth recording properly — with the
reasoning, not just the result.

A study earns its place here once it changed a decision in the main project. See the main
[README](../README.md) for the project itself.

| File | Finding |
|---|---|
| `a-saved-link-is-not-a-note.md` | What unites a note and a saved link is a **retrieval promise**, not "text you keep". What separates them is one axis — where the bytes came from and what losing them means — and three rows of that axis are decisions a namespace is the handle for: egress, backup, blast radius. Decided the `side` catalogue field, the absence of any `namespace` option, the defaultless per-side namespaces, the cross-side Secret refusal, and the same two-way cut in the client catalogue. |
| `a-notebook-is-defined-by-its-store.md` | The house rule that a wiki must keep its pages as files stopped being a policy once it was read as a **definition**: a notebook is a corpus of files with a runtime over it. Decided that the `notebook` option's enum is built from the catalogue's notebook table (so a database-store engine is not a refused value, it is not a value), that every declaration restates `store` and is checked against the catalogue, and that `onDisk`/`opaque`/`stateless` are published as a partition a consumer can assert on. |
| `an-archive-cannot-scale-to-zero.md` | An archive's work outlives the request that started it, and a request-driven wake front counts requests — so the pod sleeps mid-fetch, the link is saved, the copy never arrives, and nothing reports it. Decided the `backgroundWork` field and a **refusal** rather than a warning, plus the calibration against the capture surface, where the same option costs a product promise rather than data and gets a warning. |
| `an-archive-with-files-on-disk-is-still-opaque.md` | The archive's files are named by the records that point at them, so neither half is usable alone. Decided that `store` means "can anything else read this" rather than "are there files", that `corpus` may name more than one mount, and that the entry says both halves must be backed up in one consistent moment. |
| `the-stateless-workload-is-the-dangerous-one.md` | The one workload here that keeps nothing is also the one that authenticates nobody and executes what it is sent. Decided that the stateless group's `exposure` enum has no `public` in it, that the group is exactly the set of entries that authenticate nobody (asserted both ways), that opt-in authentication plus any exposure past `internal` is refused without the credential that switches it on, and that this group alone has `replicas` and no `state`. |
