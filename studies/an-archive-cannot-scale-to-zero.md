# An archive cannot scale to zero, and that had to be a refusal

**Finding.** A link archive is the ideal-looking candidate for scale-to-zero. It is idle almost all
of the time, it is reached by one person, and it is the most expensive workload here — it runs a
headless browser. Every heuristic a person applies says "sleep it".

It is also the one workload here where scaling to zero **silently loses data**, and the reason is
structural rather than a bug anybody could fix:

> A request-driven wake front counts **requests**. An archive's work outlives the request that
> started it.

You paste a URL. The request that saves it returns immediately — the link is in the collection, the
UI says so, and everything looks correct. The *fetch* has not happened yet: the browser is starting,
the page is loading, the PDF and the screenshot and the text extraction are being written. The wake
front sees an idle connection count, waits out its grace period, and scales the pod to zero in the
middle of that. The link stays. The copy never arrives.

Nothing reports it. The item exists; only its content is missing, and the failure selects
preferentially for the links you saved in a hurry and did not look at again — which is most of them,
because that is what an archive is *for*.

## Why a warning was not enough

The first version of this was a warning, and warnings are the right instrument for a decision that
is merely expensive. This one fails these three tests:

- **It is silent.** Nothing is Degraded, nothing restarts, no probe fails. The delivery tool reports
  the whole surface healthy.
- **It is partial.** It corrupts a subset of the corpus rather than breaking the workload, so it
  gets discovered months later by somebody clicking a saved link and finding an empty archive.
- **It is not recoverable from inside.** The source may be gone by then. That is the exact scenario
  the archive was installed to prevent, arriving through the archive itself.

A refusal is right for a failure that is silent, partial and unrecoverable. So
`modules/cluster.nix` refuses `scaling = "scale-to-zero"` on any workload whose catalogue entry has
`backgroundWork = true`, and the message explains the mechanism rather than restating the rule —
`checks/cluster-eval.nix` asserts the *text* of that, because a refusal that does not explain a
failure nobody would guess is only half a refusal.

## The calibration, which is the actual point

The same file **warns** about the same option on a capture surface, and the difference between the
two is the whole design:

| | verdict | why |
|---|---|---|
| archive (background work outlives the request) | **refused** | data is lost, silently and partially |
| capture surface (a cold start costs seconds) | **warned** | nothing breaks; the product does |
| renderer (nothing kept, nothing outstanding) | **encouraged** | it is a pure function |

The capture-surface warning is worth its line because the cost is real and invisible in a manifest:
the entire promise of quick capture is that writing something down costs less than the thought is
worth, and a cold start is the one cost that defeats it. But nothing is lost, and whether three
seconds matters is a judgement about a person, not about correctness. Judgements get warnings;
correctness gets refusals.

## What it decided

- `backgroundWork` is a catalogue field, because whether work outlives its request is a property of
  the software.
- The refusal is an assertion rather than a missing enum value, because `scaling` is a real choice
  for the other three kinds — the group is not what makes it wrong, the entry is.
- The renderer's entry says out loud that it is the only one where scaling to zero is right without
  a caveat, and the module warns when that one is left always-on. The point of the warning is not
  the pod it saves; it is that the axis becomes visible in the output.
