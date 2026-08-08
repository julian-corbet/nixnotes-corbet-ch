# The workload with nothing to lose is the one to be careful with

**Finding.** This repository is about things you expect to be able to find again later, and one of
the four kinds it catalogues **keeps nothing at all**: a renderer takes a description, returns a
picture, and stores not one byte between two requests. No corpus, no backup, no restore, nothing
lost when the node it was running on disappears.

The instinct is to treat that as the easy case. It is the opposite in the one dimension that is not
about storage:

| | what is at risk | what protects it |
|---|---|---|
| capture surface | everything you wrote | its own accounts |
| notebook | everything you wrote | accounts, **if you switched them on** |
| archive | everything you kept | its own accounts |
| renderer | **nothing** | **nothing at all** |

The renderer authenticates nobody, ever — it is a bare API — and it **executes what it is sent**:
chart descriptions may contain JavaScript, which is a feature (axis formatters and label callbacks
are functions), and its own documentation states plainly that the server assumes everything it
receives is friendly and must not be exposed to untrusted parties.

So the workload with nothing to lose is the workload where a request from anybody runs code inside
the cluster. Having it in the same repository as three corpora is what made that visible: side by
side, the storage column and the trust column point in opposite directions.

## What it decided

**The stateless group's `exposure` enum has no `public` in it.**

```
nixnotes.renderers.charts.exposure = "public";
→ value is not one of the accepted values ("internal", "nb")
```

Not a guard that fires — a value that does not exist. Widening it means editing this repository and
writing down why, which is the correct amount of friction for putting an unauthenticated evaluator
of submitted code on the internet.

It is a **group-level** restriction rather than an entry-level assertion, and that is deliberate:
the group is *defined* as software that keeps nothing and is called by your own tools. An entry that
authenticated its callers would still be a renderer and would still fit; the check asserts the
converse — that the group whose enum lacks `public` is exactly the group whose entries authenticate
nobody — so if either half drifts, the missing value would be protecting the wrong software and the
check fails.

**And its neighbour got the other half of the same problem.** The notebook's authentication is
*opt-in*: with no credential supplied it asks nobody for anything, and whoever reaches it can read,
write and — because it is a runtime — execute inside somebody's notes. That one is an assertion
rather than a missing value, because the safe configuration exists and is one line away:

> a workload whose software has optional authentication, declared with any exposure class past
> `internal`, must supply the credential role that switches authentication on.

The two together are the repository's answer to the same question asked twice: *who can reach this,
and does it ask them anything?*

## The two other consequences of keeping nothing

Both are in the option surface rather than in prose, because both are exactly as structural:

- **It is the only group with a `replicas` option.** Everything with a corpus here is the single
  writer of it, and a second copy sharing one directory with no coordination is corruption rather
  than capacity — so asking for one is an unknown option, not a warning. A pure function has no such
  problem.
- **It is the only group with no `state` option.** There is nothing to back, so there is no key to
  name and no backing to supply. `checks/cluster-render.nix` reads that back off the bytes: no
  volumes, no volume mounts, and the only `RollingUpdate` in the whole render — every other
  Deployment is `Recreate`, because a single writer must be gone before its replacement starts.

## What this is honestly not

**A claim that the renderer belongs here.** It does not depend on the corpora and they do not depend
on it; it is filed in this repository because the artefact it produces is embedded in the pages the
notes side holds, and because it needed a home. That is a resting place rather than a fit, and it is
cheap to undo: no state, no derived namespace, one catalogue group.

What it earns in the meantime is this study. A repository about keeping things, containing one thing
that deliberately keeps nothing, has to state the axis its other three members sit on — and that
statement is more useful than the renderer is.
