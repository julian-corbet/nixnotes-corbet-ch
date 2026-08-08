#
# The client catalogue: what a PERSON installs on a host in order to work with their own corpus.
#
# IT IS EMPTY, AND THE EMPTINESS IS A STATE RATHER THAN A GAP. The plane exists -- the policy
# module, both host backends, the checks and the option surface all resolve -- and it claims no
# package, because assigning a package to a repository belongs to whoever owns the package set. A
# catalogue that guessed would quietly take a command out of the repository that has it today,
# where it is already declared, verified and installed on real hosts. Adding the first entry is one
# attribute in one group here and nothing else.
#
# ── THE TWO GROUPS, AND WHY THEY ARE TWO ───────────────────────────────────────────────────────
#
# The same line the cluster catalogue is cut along, because it is the same distinction and it does
# not stop being true on a laptop:
#
#   `notes`  reads or writes THE THINGS YOU WROTE -- a client for a note service's API, a command
#            over a directory of Markdown pages, an exporter that gets your own corpus back out.
#   `links`  saves or reads THE THINGS SOMEBODY ELSE WROTE and you decided to keep -- a command
#            that files a URL into your archive, or that reads what you filed.
#
# THERE IS NO THIRD GROUP FOR THE RENDERER, and the absence is deliberate rather than an oversight
# to be corrected later. A chart renderer is called with a URL by whatever you are writing in;
# there is no command whose subject is "drive a chart API", and a group for terminal plotting tools
# would be this repository claiming a shelf that belongs to whoever owns the universal terminal
# tools. If a command ever exists whose entire purpose is one of these renderers, it gets a group
# then, and the reason will be written down.
#
# ── THE BOUNDARY, so the next candidate is decidable without asking ────────────────────────────
#
#   Does the tool exist in order to read, write or organise a PERSONAL CORPUS -- notes you wrote,
#   or pages you saved?
#     yes -> here
#     no  -> whichever repository owns the thing it actually is
#
# "IT EDITS MARKDOWN" IS NOT THE TEST, and the clause is load-bearing in both directions. A text
# editor writes Markdown and belongs to whoever owns editors: it has no corpus, it has a file
# argument. A static site generator reads a directory of Markdown and belongs to whoever owns site
# builders: its subject is the OUTPUT, not the collection. And on the other side, a downloader that
# fetches a page and writes an HTML file has done the fetching half of an archive and none of the
# keeping half -- no collection, no index, nothing that answers "what did I save about this". The
# test is whether the tool's subject is the corpus.
#
# ── FIELDS, for the day an entry lands ─────────────────────────────────────────────────────────
#
#   `arch`      pacman package name.
#   `aur`       true when it is only in the AUR. The two lists must never intersect: `pacman -S`
#               resolves a transaction ATOMICALLY, so one AUR name in a pacman list fails the whole
#               converge with "target not found" and takes every unrelated package with it.
#   `nixpkgs`   nixpkgs attribute path (dotted for a nested attribute), or an explicit `null` when
#               no derivation exists at all. Never an empty string, which would read as a name.
#   `binary`    the command actually installed. Recorded separately because it disagrees with the
#               package name often enough that assuming otherwise is how a wrapper gets written
#               against a command that does not exist.
#   `speaks`    which cluster-catalogue KIND the tool talks to -- a stream, a notebook's directory,
#               an archive. The reference runs THIS WAY ROUND on purpose: a client points at a kind
#               of software, and no entry in ../lib/engines.nix names a package. Packages get
#               reassigned between repositories by somebody who is not reading the cluster
#               catalogue, and an entry there that named one would break every time that happened.
#   `note`      what it is, and every non-obvious thing about installing it.
{ ... }:
{
  notes = { };
  links = { };
}
