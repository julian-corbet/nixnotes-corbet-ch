# An archive with files on disk is still a database store

**Finding.** The link archive writes real files: a PDF, a screenshot, a readable text extraction, a
single-file HTML capture, in a directory you can mount and copy. On the surface that is a `files`
store — the same category as a notebook's Markdown pages, and by the rule this repository is built
on, the good category to be in.

It is not, and the reason is what the field actually means.

> The files are named by the record that points at them. The record is a row in a database this
> repository does not run. Neither half is usable alone.

A directory of files named after identifiers is not an archive. Nothing in it says what the page
was, what it was called, when you saved it, which collection it was in, or which of five files
belong to the same link. Those live in the database — and the database without the files is an index
of things you no longer have.

So `store` in this repository does not mean *"are there files"*. It means:

> **Can anything other than this software read what it holds?**

By that question, the archive answers no, and it answers no *despite* having a filesystem full of
content. That is the finding, and it is the one that made the field worth defining carefully rather
than intuitively.

## What it decided

- **`store = "database"` on the archive entry**, with the reasoning in the entry's own note rather
  than left to be re-derived by whoever reads the mount path and assumes.
- **`store` is documented as a question about readability**, not about storage media. The three
  values are `files` (readable without this software), `database` (only through it) and `none`
  (there is nothing to read).
- **The corpus is `corpus`, and it may span more than one mount.** The catalogue names which
  directories hold content rather than derived data, so an entry whose content is split can say so.
  The module refuses a declaration that leaves any of them unbacked.
- **Both halves must be backed up in one consistent moment**, and that is stated in the entry
  because it is not something a backup script infers: a filesystem snapshot taken at a different
  instant from the database dump produces an archive with files that no row points at and rows that
  point at files that are not there yet.

## The near miss on the other side

A notebook has a database too — an index — and it is emphatically not the same situation. Deleting
that index costs a reindex; deleting the pages costs the notebook. The distinction the catalogue
draws is therefore not "does it have a database" but **which half is the source of truth**:

| | source of truth | the other half |
|---|---|---|
| notebook | the Markdown files | a derived index, rebuildable |
| archive | the database *and* the files together | — |
| capture surface | the database | — |

`corpus` is the field that records the first column. Everything a state directory holds that is not
in `corpus` is, by construction, something whose loss costs a rebuild rather than content — which is
a useful thing for a person planning a restore to be able to read off a declaration.

## What it cost

**It cost the archive its place in the `onDisk` report**, which is the report the house rule is
about — and that is the correct outcome rather than an unfortunate one. A person reading that report
should not see the archive in it, because they cannot read the archive without its software, and
believing otherwise is the mistake this study exists to prevent.
