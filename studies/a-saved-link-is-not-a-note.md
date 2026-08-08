# A saved link is not a note, and the difference is worth two namespaces

**Finding.** Note-taking software and a bookmark archive look like one subject and are one subject —
but the thing that unites them is not "text you keep". It is that both are *things you expect to be
able to find again later*. That is a retrieval promise, and it is the only property both halves
actually share.

Everything else about them differs, and it differs along one axis: **where the bytes came from, and
what it means to lose them.**

| | you wrote it | somebody else wrote it, and you kept it |
|---|---|---|
| provenance | your keyboard | the public internet, fetched on your behalf |
| losing it means | it is **gone** — nothing else has a copy | a re-fetch that **may fail** |
| the store grows at | typing speed | page weight |
| it dials out | never | to hosts nobody enumerated in advance |

The second column's "may fail" is not a footnote. It is the entire reason the archive exists: if
re-fetching always worked, saving the address would be enough and nobody would keep a copy. So an
archive is precisely the software you run because you do not believe the first column's guarantee
applies to somebody else's server.

## Why that became two namespaces rather than a paragraph

Every one of those four rows is an operational decision somewhere, and three of them are decisions a
**namespace** is the handle for:

- **Egress.** A network policy selects on a namespace. "Which of these may reach the internet" has
  an expressible answer only if the thing that fetches is not in the same namespace as the things
  that never do. Sharing one would not make the archive stop dialling out; it would make the
  question unanswerable without per-pod labels nobody maintains.
- **Backup.** The two halves want different promises. The notes side is irreplaceable and small.
  The links side is irreplaceable *in practice* and grows from outside input — which is a different
  sizing conversation and a different restore conversation.
- **Blast radius.** The archive fetches pages chosen by whoever pasted a URL and renders them in a
  headless browser. That is the one component here exposed to content it did not choose. The notes
  side holds everything its owner ever wrote.

The third one is what turned the split from a preference into an invariant: **a Secret name may not
appear on both sides**, and eval fails naming the Secret and both workloads. A shared credential
would make a compromise of the thing that eats the internet into a compromise of the thing that
holds your writing.

## What it decided

- `side` is a **catalogue field**, not a declaration one: where a piece of software's content comes
  from is a property of the software.
- There is **no `namespace` option anywhere** in `modules/cluster.nix`. A workload's namespace is
  its side's namespace, so the archive cannot be moved next to the notebook by editing one line.
- `nixnotes.platform.notesNamespace` and `.linksNamespace` are defaultless and must differ.
- `nixnotes.egress` is a read-only list, so the set of workloads that fetch remote content is
  countable rather than remembered — and `checks/clients-eval.nix` asserts at the catalogue level
  that every fetching entry is on the links side.
- The **client catalogue is cut along the same line**: `notes` and `links`, because the distinction
  does not stop being true on a laptop.

## What it cost

**One more defaultless option, and a second namespace to unseal Secrets into.** Both are real
overhead for a person running two applications, and the alternative — one namespace, one Secret,
one policy — is genuinely simpler until the day something in it is compromised or somebody asks
which of these workloads is allowed to talk to the internet. At that point the simpler version has
no answer that is not a rewrite.

## What it deliberately does *not* claim

That a note and a saved link are different *kinds of thing to a person*. They are not: both are
searched together, tagged together and read together, and the best possible outcome for this
repository would be a surface that presents them as one corpus. The split here is about where the
bytes come from and what may reach them — an operational line, drawn under a single subject, not a
claim that the subject is really two.
