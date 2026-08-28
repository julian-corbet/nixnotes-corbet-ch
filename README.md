# nixnotes

**The personal knowledge surface, declared: the things you write down, the things somebody else
wrote that you decided to keep, and what it takes to be able to find any of it again.**

It renders no Kubernetes object of its own. Everything expressible as an app is expressed in
[nixk3s](https://github.com/julian-corbet/nixk3s-corbet-ch)'s app grammar; what this repository adds
is the one thing that grammar cannot know — what a note, a saved page and a rendered picture each
*are*, and what it costs to lose one.

## What unites a note and a saved link

Not "text you keep". A note is something **you wrote**; a saved link is something **somebody else
wrote** that you decided to keep. They differ in provenance, and they differ in what losing them
means. What they share is the only property that matters to the person holding them:

> They are the things you expect to be able to **find again later**.

That is a retrieval promise, and it is one subject. The line between them is not a change of
subject — it is an axis, and the whole repository is organised along it:

| | you wrote it | somebody else wrote it | nobody wrote it |
|---|---|---|---|
| **losing it means** | it is **gone** | a re-fetch that **may fail** | nothing |
| **the store grows at** | typing speed | page weight | it does not |
| **it dials out** | never | to hosts nobody enumerated | never |
| **side** | `notes` | `links` | `charts` |

The middle column's "may fail" is not a footnote — it is the entire reason an archive exists. If
re-fetching always worked, saving the address would be enough. Full reasoning:
[`studies/a-saved-link-is-not-a-note.md`](studies/a-saved-link-is-not-a-note.md).

The third column is the odd one and is included on purpose; see
[below](#the-fourth-kind-keeps-nothing-and-that-is-the-point).

## The store is the thing this repository encodes

**A house rule stands behind the whole design: a notebook must be developer- and AI-facing, which
means its pages must be plain files on disk that other tools can read.** A database-only store is
rejected. That is a rule right up until somebody applies it inconsistently, so here it is not a rule
at all — it is a **definition**, in three places:

**1. The option's enum is built from the catalogue.** A notebook *is* a corpus of files with a
runtime over it, so the `notebook` option's type comes from
[`lib/engines.nix`](lib/engines.nix)'s notebook table, whose defining property is `store = "files"`.
Declaring a database-store engine as your notebook is not a refused value — it is not a value.

**2. Every declaration restates its store, and eval fails if it disagrees with the catalogue.**

```nix
nixnotes.streams.jot      = { stream = "…";   store = "database"; … };  # only its own software reads this
nixnotes.notebooks.wiki   = { notebook = "…"; store = "files";    … };  # anything reads this
nixnotes.renderers.charts = { renderer = "…"; store = "none";     … };  # there is nothing to read
```

One line per workload, and it buys the question the rule is actually about: **a declaration answers,
on its own, whether anything other than that software can read what it holds.**

**3. The answer is published as data.** `nixnotes.onDisk` (workload → on-disk format),
`nixnotes.opaque` and `nixnotes.stateless` partition every declared workload, so a consumer can
assert on them rather than trust that nothing changed.
[`studies/a-notebook-is-defined-by-its-store.md`](studies/a-notebook-is-defined-by-its-store.md).

**And "are there files" is not the question.** The archive writes real files — a PDF, a screenshot,
a text extraction — and is still a `database` store, because those files are named by records in a
database and neither half is usable alone.
[`studies/an-archive-with-files-on-disk-is-still-opaque.md`](studies/an-archive-with-files-on-disk-is-still-opaque.md).

## The sides are three namespaces, structurally

Every row of the table above is an operational decision somewhere, and three of them are decisions a
**namespace** is the handle for: a network policy selects on one, a backup policy selects on one, and
a Secret set unseals into one. So:

1. **A workload's side is not declarable.** It is read from the catalogue, because where a piece of
   software's content comes from is a property of the software.
2. **There is no `namespace` option anywhere.** A workload's namespace is its side's namespace, and
   the three are defaultless platform options that must differ. The thing that dials the internet
   cannot be moved next to the thing holding everything you ever wrote, because there is no line to
   edit.
3. **A Secret name may not appear on two sides.** Eval fails, naming the Secret and both workloads.
   The archive fetches pages chosen by whoever pasted a URL and renders them in a headless browser;
   it must not hold the credential that opens the notebook.
4. **No namespace may be named after an application in the catalogue.** A namespace named after one
   of its own tenants cannot hold the second one honestly, and the only fix later is a migration.

`checks/cluster-eval.nix` asserts the ones that are *unknown options* rather than refusals in a set
called `structurallyImpossible`, so re-adding any of those options would fail the check.
`checks/cluster-render.nix` then reads it back off the bytes: nothing belonging to one side is
rendered into another side's namespace, and neither side's manifests name the other's Secret.

## What this is

A catalogue and one option namespace, `nixnotes`, like every repository in this family.

**[`lib/engines.nix`](lib/engines.nix)** — four groups, because the subject genuinely contains four
kinds of thing: `streams` (a capture surface — the unit is a short dated note and the promise is
that writing it down costs seconds), `notebooks` (pages on disk with a runtime over them),
`archives` (a copy of somebody else's page, kept because the original may not last) and `renderers`
(a pure function with a URL). Each entry carries its own knowledge: which port it listens on, which
directories it writes and *which of those are the corpus*, how long a cold start takes before a
probe means anything, which variable each credential arrives in, whether it authenticates its
callers at all, and whether it keeps working after a request has been answered.

**[`lib/clients.nix`](lib/clients.nix)** — what a person installs on a **host**, cut along the same
line: `notes` and `links`. **It is empty, and the emptiness is a state rather than a gap.** The
policy module, both host backends and the checks all exist and resolve; what this repository does
not do is decide *which* packages, because assigning a package to a repository belongs to whoever
owns the package set. Adding the first one is one attribute in one file.

```nix
# Composed into a nixidy environment ALONGSIDE nixk3s's app grammar.
# Every value below is a fleet fact the consumer supplies; this repository ships none of them.
nixnotes.platform = {
  notesNamespace  = "…";   # what you wrote: irreplaceable, and it never dials out
  linksNamespace  = "…";   # what somebody else wrote: the only side with egress
  chartsNamespace = "…";   # what keeps nothing
  project = "…";
  origin  = "nixnotes";
};

nixnotes.streams.jot = {
  stream = "…"; version = "…"; store = "database"; slot = N; exposure = "nb";
  state.data.hostPath = "…";
};

nixnotes.notebooks.wiki = {
  notebook = "…"; version = "…"; store = "files"; slot = N + 1; exposure = "nb";
  state.space.hostPath = "…";
  # Its authentication is OPT-IN; anything past `internal` is refused without this.
  credentials.login = { secret = "…"; key = "…"; };     # by name, never by value
};

nixnotes.archives.keep = {
  archive = "…"; version = "…"; store = "database"; slot = N + 2; exposure = "nb";
  publicUrl = "https://…";                  # ORIGIN only: the path is the catalogue's
  state.archives.hostPath = "…";
  credentials = { database = { … }; session = { … }; };
};

nixnotes.renderers.charts = {
  renderer = "…"; version = "…"; store = "none"; slot = N + 3;
  scaling = "scale-to-zero";                # the only workload here where this is right
};
```

## It consumes the app grammar; it does not reimplement Kubernetes

`modules/cluster.nix` is constructed by nixk3s's consumer factory, **defines into `nixk3s.apps`**,
and renders nothing itself. Import the grammar alongside this module — it is a hard requirement,
and a version of this module that quietly rendered its own Deployments when the grammar was absent
would be the second implementation this repository exists to not have.

`nixk3s` is therefore the cluster module's one construction-time input. `nixidy` remains a check
input, used so `nix flake check` can render the result through the real module system and assert the
manifests that come out. Host and client modules still take their package set from their consumer.

**Nothing here is rendered below the grammar**, and that is worth stating because the siblings all
have an escape hatch and this one does not. Every workload in this catalogue is an image with ports
and directories, so there is no `manifests` option and no `raw` passthrough anywhere in this module:
the untyped surface of this repository is empty, structurally rather than by discipline. The render
check asserts it on the output — only Deployments, Services, Namespaces and Applications exist.

## The interlocks

Guards over *relationships*, all of which fail eval rather than warning, because each has a failure
mode where every object applies cleanly and the delivery tool reports everything healthy:

- **an archive declared `scale-to-zero`** — its work outlives the request that started it, so a
  request-driven wake front sleeps the pod mid-fetch: the link is saved, the copy never arrives, and
  nothing reports it. Refused rather than warned about, because the loss is silent, partial and
  unrecoverable — the source may be gone, which is why you were archiving it.
  [`studies/an-archive-cannot-scale-to-zero.md`](studies/an-archive-cannot-scale-to-zero.md);
- **opt-in authentication, reachable, with no credential** — software that only asks for credentials
  when it is given some works perfectly for everybody who finds it. The declaration is refused past
  `internal` until the credential role that switches it on is supplied;
- **a corpus directory left unbacked** — the workload starts, uses the container's own filesystem,
  reports itself healthy, and is a brand new empty notebook after every restart;
- **a public URL that is not a bare origin** — the software's own required path is knowledge and is
  appended by this module, so the classic "every credential is correct and nobody can log in"
  failure is not writable here;
- **a credential role the software does not read**, and **a required role that is missing**;
- **two workloads on one slot**, and **two workloads creating one namespace**.

And the calibration matters as much as the guards: the same `scale-to-zero` option gets a **warning**
on a capture surface, where nothing is lost and only the product promise is — a cold start defeats
the entire point of writing something down in three seconds. Judgements get warnings; correctness
gets refusals.

Which **range** the slot numbers may come from is a different question, answered by nixk3s's band
model. `nixnotes.platform.origin` is the one switch that hands this surface's slots to it.

## The fourth kind keeps nothing, and that is the point

The `renderers` group is a stateless HTTP renderer: a description goes in, a picture comes out, and
nothing is kept between two requests. **It is honestly a resting place rather than a perfect fit** —
nothing in this repository depends on it and it depends on nothing here. It is filed here because
the artefact it produces is embedded in the pages the notes side holds, and because it needed a
home; moving it later costs one catalogue group and one namespace option.

What it earns in the meantime is that it makes the axis visible by sitting at the end of it. It is
the **control case**: a repository about things you expect to find again, containing one thing that
deliberately keeps nothing, has to say what the other three are *for*. And it inverts in the one
dimension that is not about storage — it has nothing to lose and no accounts at all, and it executes
what it is sent, so:

- its `exposure` enum **has no `public` in it**, which is a missing value rather than a guard;
- it is the **only group with a `replicas` option** — everything with a corpus here is the single
  writer of it, so a second copy is corruption rather than capacity;
- it is the **only group with no `state` option** — there is nothing to back.

[`studies/the-stateless-workload-is-the-dangerous-one.md`](studies/the-stateless-workload-is-the-dangerous-one.md).

## Public mechanism, private layout

**No address, no slot number, no band, no namespace value, no node path, no hostname and no domain
appears anywhere in this repository.** Every one of those is a fleet fact and is a parameter the
consumer supplies. The three namespace options have *no default* and evaluation fails naming them
the moment a workload on that side is declared: what a cluster calls these namespaces is a value,
and a default here would be this repository deciding it.

Nor does it say **which** of these anybody runs. The catalogue describes kinds of software, with
named products as worked examples; a declaration is what says one is deployed, and declarations live
where fleet facts live.

What is public is the mechanism: the catalogue, the knowledge in it, the render, the sides and the
guards.

## Repository layout

| Path | Purpose |
|---|---|
| `flake.nix` | `nixidyModules` (cluster), `nixosModules`/`systemManagerModules` (clients), `lib.*`, `checks`. |
| `lib/engines.nix` | The cluster catalogue: streams, notebooks, archives, renderers — and the knowledge that makes each run, including what it keeps and who it answers to. |
| `lib/clients.nix` | The client catalogue: two groups, declared and empty. This repository claims no host package. |
| `modules/cluster.nix` | The four-root consumer-factory translation: derives each namespace from a side and keeps the store restatement, narrow state vocabulary, credentials, reports and side separation domain-owned. |
| `modules/clients.nix` | Client policy and the published package lists. Also *is* the Arch backend. |
| `modules/nixos.nix` | The NixOS backend: force-evaluates every attribute and installs it. |
| `checks/` | Four checks that really evaluate — see below. |
| `examples/all/values.nix` | Placeholder values that make the render check real. Nothing in it is a real fleet fact. |
| `experiments/verify-upstream-coordinates.sh` | Every image coordinate, checked against the registry that serves it. |
| `studies/` | Written-up findings that changed a decision here. |

## Checks

`nix flake check` runs four, and none of them is syntax-only.

**`clients-eval`** evaluates the client policy module through `lib.evalModules` — an empty selection
resolves to empty lists on every plane a backend reads, both groups refuse a name, and a **tripwire**
fails the moment a package is assigned, so the invariants that are vacuous today cannot stay vacuous
unnoticed. Then the cluster catalogue's own integrity, which is where all the content is: that every
notebook keeps its pages as files and names the format (**the property the notebook option's enum
means**), and that no entry outside that group claims a file store; that a format is recorded exactly
where there is one; that the three stores partition the catalogue; that a corpus is named exactly
where there is content and every name is a state directory; that the sides follow from the kinds;
that only the links side fetches remote content; that the group which cannot be public is exactly the
group that authenticates nobody; that everything with a corpus is a single writer; that every entry
is addressable, names an image repository and carries no version anywhere.

**`cluster-eval`** renders the module through the real grammar and the real renderer, in both
directions. The floor (an empty surface defines no app at all), the control (one workload of every
kind, on all three sides), and then nineteen declarations that must each be **refused** — a store
restated as something it is not, a database-backed engine declared as a notebook, opt-in
authentication reachable with no credential, an archive scaled to zero, one Secret named from two
sides, two sides in one namespace, a namespace named after an application, an unbacked corpus, a
credential role the software does not read, a public URL carrying a path of its own, the renderer
declared `public`, two workloads on one slot — against a control that must render. Plus six that are
not refusals at all but **unknown options**, which is the whole claim of the design. Three refusals
have their *message* asserted by content, because `tryEval` can only say *that* something was
refused.

**`cluster-render`** parses the manifests this surface actually produced and asserts them field by
field: that each corpus is mounted where the software writes it with the backing the declaration
supplied and a type that refuses to invent an empty one; that the stateless workload has no volumes
at all and is the only `RollingUpdate` in the render while every single writer is `Recreate`; that a
side decided every namespace and each one is anchored once with the annotation that stops it being
cascade-deleted; that no object landed in another side's namespace and neither side's manifests name
the other's Secret; that the public URL is the joined value; that credentials are `secretKeyRef`s
and no Secret object is ever rendered; that an optional credential nobody named renders nothing;
that two workloads listen on the same port number in two different Services, because a port is not
an identity; that the sleeping workload renders no replica count and its Application ignores the
field; and that no Service carries a pinned address, an external IP or a node port.

**`cluster-single-writer-render`** replaces the notebook's node path with a claim and proves its
catalogued `singleWriter` fact still renders `Recreate`. The old translator dropped that fact and
the main fixture passed only because a node path independently forced the same strategy.

## Status

**Pre-alpha.** The catalogue's knowledge comes from upstream's own documented deployments and from
running them — the ports, the mount paths, the probe endpoints and the correctness environment are
each recorded because getting one of them wrong produces something that looks healthy and is not.
This repository has not yet replaced any existing declaration of these workloads.

The **client plane is deliberately empty**: the surface exists, both backends exist, and no package
is claimed.

## Related projects

Part of the same independently-usable module family:
[nixk3s](https://github.com/julian-corbet/nixk3s-corbet-ch) (the app grammar this consumes, and the
band model its slots answer to),
[nixdb](https://github.com/julian-corbet/nixdb-corbet-ch) (the database tier — the SQL engine the
archive here names as a dependency and this repository does not run), and
[nixapps](https://github.com/julian-corbet/nixapps-corbet-ch) (ordinary self-hosted applications,
which is what everything here would be if this repository had no subject of its own).

## License

MIT License &copy; 2026 Julian Corbet
