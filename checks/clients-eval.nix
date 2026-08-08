# Evaluates modules/clients.nix for real against `lib.evalModules` and asserts what it resolves,
# plus the integrity of both catalogues and the direction of the reference between them.
#
# Here for the reason every sibling states for its own version of this file: `nix flake check` does
# not evaluate `nixosModules`/`systemManagerModules` on its own, so a green check on this repository
# without it would prove nothing but flake syntax.
#
# ── WHAT IT PROVES TODAY, GIVEN AN EMPTY CLIENT CATALOGUE ──────────────────────────────────────
#
# Two of the sections below are real and one quantifies over an empty set, and the file says which
# is which rather than reading as though all of it were exercised:
#
#   - REAL: the resolution path terminates -- every plane a backend reads is published and empty;
#     both groups are declared and refuse a name; and the CLUSTER catalogue's integrity, which is
#     where all the content in this repository actually is.
#   - EMPTY-SET: the pacman/AUR invariant and the nixpkgs-null handling. They hold vacuously and
#     they are kept, because the day an entry lands they become the checks that matter and
#     rediscovering them then is how a converge gets broken.
#
# THE TRIPWIRE is the point of the file in the meantime: `the client catalogue claims no package`
# fails the moment somebody adds one, so the empty-set assertions above cannot stay vacuous without
# anybody noticing, and this header cannot stay true without being edited.
#
# ── AND THE HOUSE RULE, ASSERTED AT THE CATALOGUE ──────────────────────────────────────────────
#
# The one about a notebook keeping its pages as FILES is enforced by the module through an enum
# built from the notebook table -- so the rule is only as good as that table's integrity. It is
# checked here, over the whole group rather than over the entries that happen to exist today.
#
# Deliberately pkgs-FREE beyond `pkgs.emptyFile` for the derivation shell. Every question here is a
# question about NAMES, LISTS and SHAPES. Whether an image repository still exists, and whether a
# nixpkgs attribute still forces, are facts about the world that change without this repository
# changing -- see ../experiments/verify-upstream-coordinates.sh.
{ pkgs, lib ? pkgs.lib }:
let
  clients = import ../lib/clients.nix { };
  engines = import ../lib/engines.nix { };

  evalWith = selection: (lib.evalModules {
    modules = [ ../modules/clients.nix { nixnotes.clients = selection; } ];
  }).config.nixnotes.clients;

  empty = evalWith { };

  clientGroups = lib.attrNames clients;
  clientEntries = lib.concatMap (g: lib.attrValues clients.${g}) clientGroups;

  # `evalModules` is lazy: `tryEval` alone forces only WHNF (the attrset exists), never the
  # type-checked value inside. `deepSeq` forces through, which is what actually runs the
  # listOf-enum merge that rejects a name.
  refuses = selection: group:
    (builtins.tryEval (builtins.deepSeq (evalWith selection).${group} true)).success == false;

  ## ---------------------------------------------------------------------
  ## The cluster catalogue's own integrity
  ##
  ## Structural facts the cluster module RELIES ON rather than checks per declaration: a shape that
  ## broke here would produce a module that type-checks and renders the wrong thing -- or, in the
  ## case of the notebook table, an option whose enum quietly stopped meaning what it says.
  ## ---------------------------------------------------------------------

  engineGroups = lib.attrNames engines;
  allEntries = lib.concatMap (g: lib.attrValues engines.${g}) engineGroups;
  entriesOfSide = side: lib.filter (e: e.side == side) allEntries;
  stored = s: lib.filter (e: e.store == s) allEntries;

  notNotebooks = lib.concatMap (g: lib.attrValues engines.${g}) [ "streams" "archives" "renderers" ];

  # The two halves of the option surface: the groups that carry a corpus (and therefore a `state`
  # option and no `replicas`), and the group that carries neither.
  withCorpus = lib.concatMap (g: lib.attrValues engines.${g}) [ "streams" "notebooks" "archives" ];
  stateless = lib.attrValues engines.renderers;

  results = {
    # ── The client plane: the floor, which is real ────────────────────────────────────────────
    "an empty selection resolves to nothing selected" =
      empty.selected == [ ];

    "an empty selection produces empty lists on EVERY plane, not one populated by default" =
      empty.archPackages == [ ] && empty.aurPackages == [ ]
      && empty.nixosPackages == [ ] && empty.unavailableOnNixos == [ ]
      && empty.binaries == { };

    "every plane a backend reads is actually published" =
      lib.all (o: empty ? ${o})
        [ "selected" "archPackages" "aurPackages" "nixosPackages" "unavailableOnNixos" "binaries" ];

    "every catalogue group has a matching selection option on the module" =
      lib.all (g: empty ? ${g}) clientGroups;

    # The client groups are cut along the SAME line as the cluster sides that have a corpus: what
    # you wrote, and what somebody else wrote and you kept. There is deliberately no third group
    # for the renderer -- see lib/clients.nix.
    "the client catalogue is cut along the provenance line, in two groups" =
      lib.sort (a: b: a < b) clientGroups == [ "links" "notes" ];

    # THE TRIPWIRE. Both groups are empty as a STATE: assigning a package to a repository is not
    # this repository's decision, so it claims none. The day one is assigned, this fails -- and the
    # assertions below it stop being vacuous, which is exactly when somebody has to read them.
    "the client catalogue claims no package, and every group refuses a name" =
      clientEntries == [ ]
      && refuses { notes = [ "anything" ]; } "notes"
      && refuses { links = [ "anything" ]; } "links";

    # ── The client plane: invariants that hold vacuously today ────────────────────────────────
    # One AUR name in a pacman list fails `pacman -S` ATOMICALLY and takes every unrelated package
    # in the same converge with it. Vacuous while the catalogue is empty; load-bearing the moment
    # it is not.
    "archPackages and aurPackages can never intersect" =
      lib.intersectLists empty.archPackages empty.aurPackages == [ ];

    "every entry names a pacman package, a command, and either a nixpkgs attribute or an explicit null" =
      lib.all
        (t: lib.isString (t.arch or null) && t.arch != ""
          && lib.isString (t.binary or null) && t.binary != ""
          && t ? nixpkgs && (t.nixpkgs == null || (lib.isString t.nixpkgs && t.nixpkgs != "")))
        clientEntries;

    # ── THE DIRECTION OF THE REFERENCE ────────────────────────────────────────────────────────
    # The cluster catalogue names software, ports, directories and roles; it must never name a
    # PACKAGE. If it did, every reassignment of a package to another repository would break this
    # surface -- and packages get reassigned by somebody who is not reading that file.
    "no cluster catalogue entry names a client package, in any group" =
      lib.all (e: !(e ? arch) && !(e ? nixpkgs) && !(e ? binary)) allEntries;

    # ── The cluster catalogue: the four kinds ─────────────────────────────────────────────────
    "the cluster catalogue holds exactly the four groups the module wires" =
      lib.sort (a: b: a < b) engineGroups
      == [ "archives" "notebooks" "renderers" "streams" ];

    "every entry names a side and a store, and nothing else is either" =
      lib.all (e: lib.elem e.side [ "notes" "links" "charts" ]) allEntries
      && lib.all (e: lib.elem e.store [ "files" "database" "none" ]) allEntries;

    # A group is a KIND; a side is where its bytes come from. The mapping is fixed, and the module
    # reads a namespace from it -- so a stray side on one entry would put a workload in the wrong
    # namespace with nothing to notice.
    "the sides follow from the kinds: what you wrote, what somebody else wrote, and nothing" =
      lib.all (e: e.side == "notes") (lib.attrValues engines.streams ++ lib.attrValues engines.notebooks)
      && lib.all (e: e.side == "links") (lib.attrValues engines.archives)
      && lib.all (e: e.side == "charts") (lib.attrValues engines.renderers);

    # ── THE HOUSE RULE, at the table the option's enum is built from ──────────────────────────
    "every notebook keeps its pages as FILES, and names the format they are in" =
      lib.all
        (e: e.store == "files" && lib.isString e.format && e.format != "")
        (lib.attrValues engines.notebooks)
      && engines.notebooks != { };

    "and the notebook group is the ONLY place a file store is claimed from -- so the enum means what it says" =
      lib.all (e: e.store != "files") notNotebooks;

    "a format is recorded exactly where there is an on-disk format to record" =
      lib.all (e: (e.format != null) == (e.store == "files")) allEntries;

    # `store` is what a declaration restates. Its three values have to partition the catalogue or
    # the restatement is answering a question with a gap in it.
    "the three stores partition the catalogue" =
      lib.length (stored "files" ++ stored "database" ++ stored "none") == lib.length allEntries;

    "a corpus is named exactly where there is content, and every name is a state directory" =
      lib.all (e: (e.corpus == [ ]) == (e.store == "none")) allEntries
      && lib.all (e: lib.all (k: e.state ? ${k}) e.corpus) allEntries;

    # ── The stateless group, which is the reason two option sets exist ────────────────────────
    "the stateless group keeps nothing at all, and is the only group that is not a single writer" =
      stateless != [ ]
      && lib.all (e: e.store == "none" && e.state == { } && !e.singleWriter) stateless;

    "everything with a corpus is a single writer, which is why only one group has a replica count" =
      lib.all (e: e.singleWriter && e.state != { }) withCorpus;

    # ── Egress: the one difference that is a network fact ─────────────────────────────────────
    # The links side exists as a separate namespace BECAUSE of this property, so a fetching entry
    # on another side would quietly put outbound traffic in the namespace that has none.
    "only the links side fetches remote content, and it is where every fetching entry is" =
      lib.all (e: !e.fetchesRemoteContent) (entriesOfSide "notes" ++ entriesOfSide "charts")
      && lib.any (e: e.fetchesRemoteContent) (entriesOfSide "links");

    # ── Authentication, which is the other property an option surface is built on ─────────────
    "every entry says whether it authenticates its callers, and opt-in auth names the role that switches it on" =
      lib.all (e: lib.elem e.authentication [ "builtin" "optional" "none" ]) allEntries
      && lib.all
        (e: (e.authCredential != null) == (e.authentication == "optional"))
        allEntries
      && lib.all
        (e: e.authCredential == null || (e.credentials ? ${e.authCredential}))
        allEntries;

    # The group whose `exposure` enum has no `public` in it is exactly the group that authenticates
    # nobody. If an entry that asks nobody for anything landed in a group that CAN be public, the
    # missing enum value would be protecting the wrong software -- and if one that does authenticate
    # landed in the renderers, the missing value would be protecting software that did not need it.
    "the group that cannot be public is exactly the group that authenticates nobody" =
      lib.all (e: e.authentication == "none") stateless
      && lib.all (e: e.authentication != "none") withCorpus;

    # Both entries that run caller-supplied code are covered by something: one asks for credentials
    # (and is refused an exposure class past `internal` without them), the other cannot be public at
    # all. An entry that executes, authenticates nobody, AND could be public would be covered by
    # neither.
    "nothing executes what it is sent while both authenticating nobody and being allowed to be public" =
      lib.all (e: !e.executes || e.authentication != "none" || lib.elem e stateless) allEntries;

    # ── The shapes the module renders from ────────────────────────────────────────────────────
    "every entry is addressable and names a primary port it actually declares" =
      lib.all (e: e.ports != { } && e.primaryPort != null && (e.ports ? ${e.primaryPort})) allEntries;

    "a readiness probe only exists where there is a port to probe" =
      lib.all (e: e.readiness == null || e.ports != { }) allEntries;

    # A null repository would render `:<version>` with no repository in front of it, which is a
    # pull error at the far end of a sync rather than an eval error here.
    "every entry names an image repository, and no entry carries a version anywhere" =
      lib.all (e: lib.isString e.image && e.image != "" && !(lib.hasInfix ":" e.image)) allEntries
      && lib.all (e: !(e ? version)) allEntries;

    "every state directory names an absolute mount path and says whether it may be written" =
      lib.all
        (e: lib.all (s: lib.hasPrefix "/" s.mountPath && lib.isBool s.readOnly) (lib.attrValues e.state))
        allEntries;

    "every credential role names the variable it arrives in and whether it is required" =
      lib.all
        (e: lib.all
          (c: lib.isString c.env && c.env != "" && lib.isBool c.required)
          (lib.attrValues e.credentials))
        allEntries;

    # The module JOINS the declaration's origin and this path. A path that did not start with a
    # slash would produce a URL with the host and the path run together.
    "a public-URL entry names the variable and the path suffix, and the suffix is a path" =
      lib.all
        (e: e.publicUrl == null
          || (lib.isString e.publicUrl.env && e.publicUrl.env != ""
          && lib.hasPrefix "/" e.publicUrl.path))
        allEntries;

    "every declared dependency says whether the software runs without it" =
      lib.all
        (e: lib.all (d: lib.isBool d.required) (lib.attrValues e.dependsOn))
        allEntries;

    "every entry carries a note, and no note is empty" =
      lib.all (e: lib.isString (e.note or null) && lib.stringLength e.note > 200) allEntries;
  };

  failed = lib.attrNames (lib.filterAttrs (_: passed: !passed) results);
in
if failed == [ ]
then pkgs.emptyFile
else
  throw ''
    nixnotes: clients-eval check failed. Failing assertions:
    ${lib.concatMapStringsSep "\n" (f: "  - ${f}") failed}
  ''
