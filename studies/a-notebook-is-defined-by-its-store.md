# A notebook is defined by its store, not by its interface

**Finding.** The house rule this repository exists to serve is that a personal wiki must be
developer- and AI-facing: its pages must be **plain files on disk** that other tools can read, and a
database-only store is rejected. Stated like that it is a policy — something a reviewer applies,
which is another way of saying something that eventually is not applied.

It became structural once the rule was read as a **definition** instead of a preference:

> A notebook is not "wiki software". A notebook is a corpus of files with a runtime over it. What
> makes it developer- and AI-facing is not a feature it has; it is what it *is*.

Software that keeps its pages in a database can be excellent note-taking software. It is not a
notebook in this repository, and the honest thing to do with it is catalogue it as the thing it
actually is — a capture surface — rather than refuse it.

## How the rule binds

Three levels, each enough on its own, and the point of having three is that widening the surface
requires *editing this repository* rather than writing a declaration.

### 1. The option's enum is built from the notebook table

`lib/engines.nix` has a `notebooks` group whose defining property is `store = "files"`.
`modules/cluster.nix` builds the `notebook` option's type from `lib.attrNames catalogue.notebooks`.

```
nixnotes.notebooks.wiki.notebook = "<a database-store engine>";
→ value is not one of the accepted values
```

That is not a guard firing. There is nothing there to fire — the value does not exist. And the error
lists the engines that do, which is the same list a reader would have gone looking for.

`checks/clients-eval.nix` then asserts the property the enum's meaning depends on, over the whole
group rather than over the entries that happen to exist today: every notebook entry has
`store = "files"` and names the format, and **no entry outside that group claims a file store**. If
the table's integrity broke, the enum would still be an enum and would silently stop meaning
anything.

### 2. Every declaration restates the store

`store` is a required, defaultless option on every workload in this repository, and evaluation fails
if it disagrees with the catalogue.

```nix
nixnotes.streams.jot     = { stream = "memos";        store = "database"; … };
nixnotes.notebooks.wiki  = { notebook = "silverbullet"; store = "files";  … };
nixnotes.renderers.charts = { renderer = "quickchart"; store = "none";    … };
```

It is one line per workload and it buys the thing the house rule is actually about: **a declaration
answers, on its own, whether anything other than this software can read what it holds.** Somebody
reading a private values file — or an agent grepping one — gets the answer without opening a
catalogue, and adopting software that locks the corpus away becomes a sentence you had to write
rather than a property you inherited.

The catalogue is the measured half; the restatement is the acknowledgement. That is why a mismatch
names both values and tells you to fix the declaration.

### 3. The report is data

`nixnotes.onDisk` maps workload → on-disk format for everything readable without its software;
`nixnotes.opaque` lists everything that is not; `nixnotes.stateless` lists what keeps nothing. The
three partition every declared workload, so a consumer can assert on them — that the notebook is in
the first list, and in which format — instead of trusting that nothing changed.

## What it cost

**It cost the ability to declare a database-backed engine as "the wiki", and that is a real
restriction rather than a theoretical one.** Some very good software would be excluded from the
group by exactly one property, and someone who wants it anyway has to either declare it as the
capture surface it is (which is available, and honest) or add a group here and write down why.

It also costs a line per declaration for the restatement, which is the kind of thing that looks like
ceremony right up until the first time somebody has to answer "can I read these notes without this
container running" for a corpus that has been accumulating for two years.
