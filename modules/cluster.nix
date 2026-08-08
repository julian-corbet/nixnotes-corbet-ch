#
# nixnotes' cluster surface: declare what the personal knowledge surface runs, and render it.
#
# ── THIS MODULE DOES NOT IMPLEMENT KUBERNETES, AND THAT IS THE WHOLE DESIGN ─────────────────────
#
# There is a sibling repository whose entire subject is the app grammar -- an app declares WHAT IT
# NEEDS (an image, ports, an exposure class, whether it scales to zero, which existing claims or
# node paths hold its state, which existing Secrets it consumes) and that grammar renders the Argo
# CD Application, the Namespace, the Deployment and the Service. Everything this module can express
# in those terms is expressed in them: it DEFINES INTO `nixk3s.apps` and renders no Kubernetes
# object of its own.
#
# So this module is a translator, not a renderer. What it adds is the one thing the grammar cannot
# know: what a note service, a notebook, an archive and a renderer each ARE. Which directory holds
# the corpus and whether anything else can read it; which of them fetches remote content; which of
# them is still working after the request was answered; which of them authenticates nobody.
#
# IMPORT THE GRAMMAR ALONGSIDE THIS MODULE. `nixk3s.apps` is declared there, not here, and a render
# that composes this module without it fails with "the option `nixk3s.apps' does not exist". That
# is a hard requirement rather than an optional integration, and it is deliberately not softened: a
# version of this module that quietly rendered its own Deployments when the grammar was absent
# would be the second implementation this repository exists to not have.
#
# NOTHING HERE RENDERS BELOW THE GRAMMAR, and that is a property worth stating rather than a
# coincidence. Every one of these is an image with ports and directories, so there is no
# `manifests` option and no `raw` passthrough anywhere in this module: the untyped surface of this
# repository is empty, and it is empty structurally rather than by discipline. The siblings that
# deliver charts and custom resources have that option because they have to; this one does not.
#
# ── THE AXIS THIS FILE IS BUILT ON ─────────────────────────────────────────────────────────────
#
# WHERE THE BYTES CAME FROM, AND WHAT LOSING THEM MEANS -- see ../lib/engines.nix for the long
# form. Three positions, three namespaces, and the separation is structural rather than advisory:
#
#   1. A WORKLOAD'S SIDE IS NOT DECLARABLE. It is read from the catalogue entry, because where a
#      piece of software's content comes from is a property of the software.
#   2. THERE IS NO `namespace` OPTION ANYWHERE. A workload's namespace is its SIDE's namespace, and
#      the three are defaultless platform options that must differ. So the thing that dials the
#      internet cannot be moved next to the thing that holds everything you ever wrote by editing
#      one line -- there is no line.
#   3. A SECRET NAME MAY NOT APPEAR ON TWO SIDES. Eval fails, naming the Secret and both sides. The
#      archive renders pages chosen by whoever pasted a URL, in a browser; it must not hold the
#      credential that opens the notebook.
#   4. THE STORE IS RESTATED IN EVERY DECLARATION and checked against the catalogue, so a
#      declaration answers "can anything else read this" without opening any other file.
#   5. A NOTEBOOK CANNOT BE DATABASE-BACKED, and that is not a guard: this group's `notebook` enum
#      is built from the catalogue's notebook table, whose defining property IS files on disk. A
#      database-store engine is not a value the option has.
#   6. ONLY THE STATELESS GROUP HAS `replicas`. Everything with a corpus here is a single writer,
#      so a second copy is corruption rather than capacity -- and asking for one is an unknown
#      option rather than a warning.
#   7. THE STATELESS GROUP'S `exposure` DOES NOT ACCEPT `public`. It authenticates nobody and runs
#      what it is sent; the class is missing from the enum rather than refused by an assertion.
#
# ONE NAMESPACE. Everything declared here lives under `nixnotes`, like every repo in this family.
{ config, lib, ... }:
let
  cfg = config.nixnotes;
  platform = cfg.platform;

  catalogue = import ../lib/engines.nix { };

  enabledOf = attrs: lib.filterAttrs (_: w: w.enable) attrs;

  streams = enabledOf cfg.streams;
  notebooks = enabledOf cfg.notebooks;
  archives = enabledOf cfg.archives;
  renderers = enabledOf cfg.renderers;

  # Every declared workload, tagged with its kind and its catalogue entry, in one list. Almost
  # every guard here is about the surface AS A WHOLE -- a Secret named from two sides, two
  # workloads on one slot, two workloads creating one namespace -- so they are written against this
  # rather than against four separate tables.
  allWorkloads =
    lib.mapAttrsToList (name: w: { inherit name w; kind = "stream"; entry = catalogue.streams.${w.stream}; }) streams
    ++ lib.mapAttrsToList (name: w: { inherit name w; kind = "notebook"; entry = catalogue.notebooks.${w.notebook}; }) notebooks
    ++ lib.mapAttrsToList (name: w: { inherit name w; kind = "archive"; entry = catalogue.archives.${w.archive}; }) archives
    ++ lib.mapAttrsToList (name: w: { inherit name w; kind = "renderer"; entry = catalogue.renderers.${w.renderer}; }) renderers;

  ## ---------------------------------------------------------------------
  ## The sides
  ## ---------------------------------------------------------------------

  sideOf = x: x.entry.side;
  onSide = side: lib.filter (x: sideOf x == side) allWorkloads;
  sideUsed = side: onSide side != [ ];

  sides = [ "notes" "links" "charts" ];
  sidesInUse = lib.filter sideUsed sides;

  # THE ONE PLACE A NAMESPACE COMES FROM. There is no per-workload option and there will not be
  # one. Written as an attrset so it stays LAZY: a render with only notes-side workloads never
  # forces the other two options, which is what lets all three be defaultless.
  namespaceOfSide = side:
    {
      notes = platform.notesNamespace;
      links = platform.linksNamespace;
      charts = platform.chartsNamespace;
    }.${side};

  namespaceOf = x: namespaceOfSide (sideOf x);

  ## ---------------------------------------------------------------------
  ## Translation into the app grammar
  ## ---------------------------------------------------------------------

  imageOf = x: if x.w.image != null then x.w.image else "${x.entry.image}:${x.w.version}";

  portsOf = x: lib.mapAttrs (_: number: { inherit number; }) x.entry.ports;

  # The knowledge/value split, in one function: WHERE inside the container each directory lands and
  # whether the software may write it come from the catalogue; WHAT BACKS IT comes from the
  # declaration, and neither side can supply the other's half.
  #
  # Filtered to the keys the catalogue actually holds, so a key that is not the catalogue's mounts
  # nothing instead of throwing out of a helper -- the assertion below is what reports it, and a
  # raw "attribute missing" from in here would arrive first and say less.
  knownState = x: lib.filterAttrs (k: _: x.entry.state ? ${k}) (x.w.state or { });

  stateOf = x:
    lib.mapAttrs
      (key: backing: {
        inherit (x.entry.state.${key}) mountPath readOnly;
        inherit (backing) claim hostPath hostPathType;
      })
      (knownState x);

  # The URL a browser reaches this workload at, for software that has to be told. The ORIGIN is a
  # fleet fact and comes from the declaration; the PATH the software insists on is knowledge and
  # comes from the catalogue, so the two are joined here and nobody writes the second half. It is
  # the one composed value in this module, and it exists because the failure it prevents -- a
  # sign-in that redirects into nothing, with every credential correct -- looks like anything but a
  # wrong URL.
  publicUrlOf = x:
    lib.optionalAttrs (x.entry.publicUrl != null && x.w.publicUrl != null) {
      ${x.entry.publicUrl.env} = x.w.publicUrl + x.entry.publicUrl.path;
    };

  # Two shapes of secret consumption, and no third: named roles the software reads from its
  # environment, and whole Secrets for a key set that changes without the declaration changing.
  # Nothing here can carry a secret's CONTENT, which is what makes a declaration written against
  # this module safe to publish.
  secretsOf = x:
    lib.mapAttrs
      (role: d: {
        secret = d.secret;
        env.${x.entry.credentials.${role}.env} = d.key;
      })
      (lib.filterAttrs (role: _: x.entry.credentials ? ${role}) x.w.credentials)
    // lib.listToAttrs
      (map (s: lib.nameValuePair s { secret = s; envFrom = true; }) x.w.envFromSecrets);

  secretNamesOf = x:
    lib.unique (lib.mapAttrsToList (_: d: d.secret) x.w.credentials ++ x.w.envFromSecrets);

  secretNamesOfSide = side: lib.unique (lib.concatMap secretNamesOf (onSide side));

  probesOf = x:
    lib.optionalAttrs (x.entry.readiness != null) {
      readiness = { port = x.entry.primaryPort; } // x.entry.readiness;
    };

  # Handed to the band model only when the consumer says it is part of the render: `origin` and
  # `slot` are ITS terms, and defining them into a render that does not declare them is an eval
  # error rather than a graceful no-op.
  addressingOf = x:
    lib.optionalAttrs (platform.origin != null) {
      origin = platform.origin;
      inherit (x.w) slot;
    };

  mkGrammarApp = x:
    {
      namespace = namespaceOf x;
      inherit (x.w) createNamespace project exposure scaling;
      image = imageOf x;
      ports = portsOf x;
      state = stateOf x;
      secrets = secretsOf x;
      env = x.entry.env // publicUrlOf x // x.w.env;
      args = x.entry.args ++ x.w.args;
      probes = probesOf x;
    }
    // lib.optionalAttrs (x.w ? replicas) { inherit (x.w) replicas; }
    // addressingOf x;

  ## ---------------------------------------------------------------------
  ## Derived facts the guards are written against
  ## ---------------------------------------------------------------------

  showSlot = x: if x.w.slot == null then "(none)" else toString x.w.slot;
  listNames = names: lib.concatMapStringsSep ", " (n: "`${n}`") names;

  slotClaims = lib.filter (x: x.w.slot != null) allWorkloads;
  claimantsOf = slot: map (x: x.name) (lib.filter (x: x.w.slot == slot) slotClaims);
  duplicatedSlots =
    lib.filter (slot: lib.length (claimantsOf slot) > 1)
      (lib.unique (map (x: x.w.slot) slotClaims));

  creatorsOf = ns:
    map (x: x.name) (lib.filter (x: x.w.createNamespace && namespaceOf x == ns) allWorkloads);
  createdNamespaces =
    lib.unique (map namespaceOf (lib.filter (x: x.w.createNamespace) allWorkloads));

  namersOf = side: secret:
    map (x: x.name) (lib.filter (x: sideOf x == side && lib.elem secret (secretNamesOf x)) (onSide side));

  sidesNaming = secret: lib.filter (side: namersOf side secret != [ ]) sidesInUse;
  crossSideSecrets =
    lib.filter (s: lib.length (sidesNaming s) > 1)
      (lib.unique (lib.concatMap secretNamesOf allWorkloads));

  # Every application this catalogue knows, by name. A namespace may not be called after one of
  # them -- see the assertion below.
  catalogueApps = lib.concatMap (g: lib.attrNames catalogue.${g})
    [ "streams" "notebooks" "archives" "renderers" ];

  sidePairs =
    let n = lib.length sidesInUse; in
    lib.concatMap
      (i: map (j: { a = lib.elemAt sidesInUse i; b = lib.elemAt sidesInUse j; })
        (lib.range (i + 1) (n - 1)))
      (lib.range 0 (n - 1));

  # An origin, as a URL, with nothing after the host. Written out rather than regex-matched because
  # the message has to be able to say WHICH half is wrong.
  isOrigin = u:
    (lib.hasPrefix "https://" u || lib.hasPrefix "http://" u)
    && !(lib.hasInfix "/" (lib.removePrefix "http://" (lib.removePrefix "https://" u)));

  ## ---------------------------------------------------------------------
  ## Assertions
  ##
  ## The module system filters the assertions down to the FAILING ones and only then formats their
  ## messages. A passing assertion's message is never evaluated at all, and two things follow.
  ##
  ## Every message here is a TOTAL function of the declaration, because a message that throws on a
  ## partial declaration throws at exactly the moment its own assertion has failed -- the one moment
  ## it was written for -- and takes the evaluation down instead of reporting anything.
  ##
  ## And a value mentioned ONLY in a message is never forced, so its type is never checked either.
  ## Whatever an assertion wants checked has to be in its `assertion` expression. See nixwatch's
  ## study `an-option-nothing-renders-is-never-checked`.
  ## ---------------------------------------------------------------------

  storeAssertions = map
    (x: {
      assertion = x.w.store == x.entry.store;
      message =
        "nixnotes: `${x.name}` declares `store = \"${x.w.store}\"` and this software keeps its content as "
        + "`${x.entry.store}`. The restatement is required on every declaration on purpose: it is what "
        + "makes a declaration answer, on its own, whether anything other than this software can read "
        + "what it holds -- `files` means a person, an editor, a backup and an agent can; `database` "
        + "means only this software can; `none` means there is nothing to read. Correct the declaration "
        + "rather than the catalogue: the catalogue is measured.";
    })
    allWorkloads;

  storageAssertions = lib.concatMap
    (x: [
      {
        assertion = lib.attrNames (x.w.state or { }) == lib.attrNames x.entry.state;
        message =
          "nixnotes: `${x.name}` must back every directory this software cannot lose, and backs "
          + (if (x.w.state or { }) == { } then "none" else listNames (lib.attrNames (x.w.state or { })))
          + ". It writes: "
          + (if x.entry.state == { } then "nothing at all"
          else
            lib.concatStringsSep ", "
              (lib.mapAttrsToList (k: s: "`${k}` at ${s.mountPath}") x.entry.state))
          + ". An unbacked one is not an error at runtime -- the workload starts, uses the container's "
          + "own filesystem, reports itself healthy, and loses it at the next restart"
          + lib.optionalString (x.entry.corpus != [ ])
            (", and " + listNames x.entry.corpus + " "
            + (if lib.length x.entry.corpus == 1 then "is" else "are") + " the corpus itself")
          + ".";
      }
      {
        assertion = lib.all
          (backing: (backing.claim == null) != (backing.hostPath == null))
          (lib.attrValues (x.w.state or { }));
        message =
          "nixnotes: `${x.name}` backs a directory with neither or both of `claim` and `hostPath`. "
          + "Storage needs exactly one backing: an existing claim by name, or a path on the node.";
      }
    ])
    allWorkloads;

  credentialAssertions = lib.concatMap
    (x:
      let
        known = lib.attrNames x.entry.credentials;
        unknown = lib.filter (r: !(x.entry.credentials ? ${r})) (lib.attrNames x.w.credentials);
        missing = lib.attrNames
          (lib.filterAttrs (r: c: c.required && !(x.w.credentials ? ${r})) x.entry.credentials);
      in
      [
        {
          assertion = unknown == [ ];
          message =
            "nixnotes: `${x.name}` names credential role(s) " + listNames unknown + " that this software "
            + "does not read. It reads "
            + (if known == [ ] then "none at all" else listNames known)
            + ". A role nothing reads renders a reference into a variable no process looks at, which is "
            + "worse than being refused because it looks provisioned.";
        }
        {
          assertion = missing == [ ];
          message =
            "nixnotes: `${x.name}` is missing required credential role(s) " + listNames missing + ". Name "
            + "the existing Secret and the key inside it -- never the value; everything this module "
            + "renders is committed to git.";
        }
      ])
    allWorkloads;

  # THE OPT-IN AUTHENTICATION GUARD. The failure it prevents is not an outage: the software starts,
  # works perfectly, and belongs to whoever finds it.
  authAssertions = map
    (x: {
      assertion =
        x.entry.authentication != "optional"
        || x.w.exposure == "internal"
        || (x.w.credentials ? ${toString x.entry.authCredential});
      message =
        "nixnotes: `${x.name}` declares exposure `${x.w.exposure}`, and this software only asks for "
        + "credentials when it is given some -- with none, everyone who can reach it can read and write "
        + "everything in it, and this one can execute inside it too. Supply the "
        + "`${toString x.entry.authCredential}` credential role, or leave the workload `internal`. "
        + "Nothing here will pick the safer class for you: which of the two you meant is a decision.";
    })
    allWorkloads;

  # THE BACKGROUND-WORK GUARD. A refusal rather than a warning, because the failure is silent and
  # partial: the request succeeds, the pod sleeps, and the work that was still running is simply
  # not there afterwards.
  scalingAssertions = map
    (x: {
      assertion = !x.entry.backgroundWork || x.w.scaling != "scale-to-zero";
      message =
        "nixnotes: `${x.name}` is declared `scale-to-zero`, and this software keeps working after the "
        + "request that started the work has been answered. A wake front counts REQUESTS: it brings the "
        + "pod up for the one that saved the item and puts it back to sleep while the fetch is still "
        + "running, so the item is saved and its content never arrives -- silently, and only for the "
        + "ones saved in a hurry. Leave it `always`.";
    })
    allWorkloads;

  publicUrlAssertions = lib.concatMap
    (x: [
      {
        assertion = x.entry.publicUrl == null || x.w.publicUrl != null;
        message =
          "nixnotes: `${x.name}` needs to be told the URL a browser reaches it at, and `publicUrl` is "
          + "unset. There is no default anybody could know -- it is a fleet fact -- and the failure "
          + "without it is a sign-in that redirects into nothing while every credential is correct. Give "
          + "the ORIGIN only (scheme and host); the path this software insists on is knowledge and this "
          + "module appends it.";
      }
      {
        assertion = x.entry.publicUrl != null || x.w.publicUrl == null;
        message =
          "nixnotes: `${x.name}` sets `publicUrl`, and this software reads no such variable -- so the "
          + "value would reach no object at all. Whatever fronts it knows its own address; this workload "
          + "does not need to.";
      }
      {
        assertion = x.w.publicUrl == null || isOrigin x.w.publicUrl;
        message =
          "nixnotes: `${x.name}` gives `publicUrl = \"${toString x.w.publicUrl}\"`, which is not a bare "
          + "origin. It must be a scheme and a host and nothing else (no trailing slash, no path): the "
          + "path this software requires comes from the catalogue and is appended here, so a path in "
          + "this value produces a URL with two of them.";
      }
    ])
    allWorkloads;

  # THE CROSS-SIDE SECRET GUARD. The load-bearing invariant of the split: the side that fetches
  # arbitrary pages and renders them in a browser must not be able to read the credential that
  # opens the side holding everything its owner ever wrote.
  sideAssertions =
    map
      (secret: {
        assertion = false;
        message =
          "nixnotes: Secret `${secret}` is named from more than one side -- "
          + lib.concatMapStringsSep "; "
            (side: "`${side}`: " + listNames (namersOf side secret))
            (sidesNaming secret)
          + ". The sides are separate because their contents have different origins and different "
          + "consequences: the links side fetches pages chosen by whoever pasted a URL and renders them "
          + "in a browser, and the notes side holds everything its owner ever wrote. One Secret object "
          + "reaching both makes a compromise of the first a compromise of the second. Unseal a second "
          + "Secret, in the other namespace, carrying only what that workload needs.";
      })
      crossSideSecrets
    ++ map
      (pair: {
        assertion = namespaceOfSide pair.a != namespaceOfSide pair.b;
        message =
          "nixnotes: the `${pair.a}` and `${pair.b}` sides are declared into the SAME namespace, and this "
          + "surface has workloads on both. The separation IS the namespaces: it is what a network policy "
          + "selects on when it decides which of these may dial the internet, what a backup policy selects "
          + "on when it decides what is irreplaceable, and what a Secret set unseals into. Give them one "
          + "each.";
      })
      sidePairs
    ++ map
      (side: {
        assertion = !(lib.elem (namespaceOfSide side) catalogueApps);
        message =
          "nixnotes: the `${side}` side's namespace is `${namespaceOfSide side}`, which is the name of an "
          + "application in this catalogue. A namespace named after one of its own tenants stops being "
          + "able to hold the second one honestly -- every other workload in it reads as a guest, and the "
          + "day you add one the only fix is renaming a namespace, which is a migration. Name it after "
          + "what the side IS.";
      })
      sidesInUse;

  tierAssertions =
    map
      (slot: {
        assertion = false;
        message =
          "nixnotes: slot ${toString slot} is claimed by more than one workload: " + listNames (claimantsOf slot)
          + ". A slot is one identity in every address space the fleet maps it into, so two claimants is a "
          + "collision in all of them at once.";
      })
      duplicatedSlots
    ++ map
      (ns: {
        assertion = lib.length (creatorsOf ns) == 1;
        message =
          "nixnotes: namespace `${ns}` is created by more than one workload: " + listNames (creatorsOf ns)
          + ". Two Applications owning one Namespace fight over it. Let exactly one anchor it, or anchor it "
          + "in the tenancy layer and set `createNamespace = false` on all of them.";
      })
      createdNamespaces;

  ## ---------------------------------------------------------------------
  ## Warnings
  ## ---------------------------------------------------------------------

  warnings =
    map
      (x: {
        # Calibrated deliberately against the refusal above: this one is a product decision rather
        # than a correctness bug, so it is said once and not enforced.
        when = x.w.scaling == "scale-to-zero";
        message =
          "nixnotes: `${x.name}` is a capture surface declared `scale-to-zero`. Nothing breaks -- it keeps "
          + "no outstanding work -- but the entire promise of this kind of software is that writing "
          + "something down costs seconds, and a cold start is the one cost that defeats it. The thought "
          + "you were capturing is gone by the time the pod is up.";
      })
      (lib.filter (x: x.kind == "stream") allWorkloads)
    ++ map
      (x: {
        when = x.w.scaling == "always";
        message =
          "nixnotes: `${x.name}` keeps nothing at all and is declared `always`, so it is a pod holding a "
          + "rendering toolchain between two requests that may be hours apart. This is the one workload "
          + "here that can idle at zero with nothing to reload and nothing outstanding -- which is worth "
          + "saying because it is the only one.";
      })
      (lib.filter (x: x.entry.store == "none") allWorkloads)
    ++ map
      (x: {
        when = x.w.slot != null && platform.origin == null;
        message =
          "nixnotes: `${x.name}` claims slot ${showSlot x}, and `nixnotes.platform.origin` is unset -- so "
          + "the number is checked for collisions inside this surface, and by nothing for which RANGE it "
          + "may come from. Set the origin when the band model is part of the same render.";
      })
      allWorkloads;

  ## ---------------------------------------------------------------------
  ## Option shapes
  ## ---------------------------------------------------------------------

  backingType = lib.types.submodule {
    options = {
      claim = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          NAME of an existing PersistentVolumeClaim backing this directory. A name, never a path.
          Nothing here creates the claim: it outlives every version of the software that mounts it,
          so its existence is not the workload's to declare.
        '';
      };

      hostPath = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Path on the NODE backing this directory instead of a claim, and in practice the common
          answer for a personal corpus: it is usually a directory somebody curates deliberately and
          backs up on their own terms.

          IT PINS THE WORKLOAD TO A NODE, because the path only exists on one. The VALUE is a fleet
          fact and belongs to the consumer that passes it in -- no path appears anywhere in this
          repository.
        '';
      };

      hostPathType = lib.mkOption {
        type = lib.types.enum [ "Directory" "DirectoryOrCreate" ];
        default = "Directory";
        description = ''
          Whether a missing node path is an error or is created empty. `Directory` (the default) is
          the right answer for everything in this repository: software that finds an empty corpus
          directory does not report a problem, it reports an EMPTY NOTEBOOK -- a first run, healthy,
          with nothing in it -- which is the failure mode that looks most like everything being
          fine. `DirectoryOrCreate` is defensible only on a genuinely first start, and it is worth
          remembering that the directory it creates is owned by whoever the runtime says, which one
          of these engines then adopts as its own user.
        '';
      };
    };
  };

  credentialType = lib.types.submodule {
    options = {
      secret = lib.mkOption {
        type = lib.types.str;
        description = "NAME of an existing Secret holding this credential.";
      };
      key = lib.mkOption {
        type = lib.types.str;
        description = "Which key inside that Secret carries it.";
      };
    };
  };

  # Shared by every workload on every side. What is NOT here matters as much as what is: no
  # `namespace` (a side decides that), no `manifests` and no `raw` (everything here is an image),
  # and no `readOnly` on a backing (whether the software may write a directory is the catalogue's).
  sharedOptions = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether to render this workload. Declaring the attribute is declaring the workload, so this
        defaults to true; set false to park a declaration without rendering it.
      '';
    };

    project = lib.mkOption {
      type = lib.types.str;
      default = platform.project;
      defaultText = lib.literalExpression "config.nixnotes.platform.project";
      description = "Delivery project this workload's Application belongs to.";
    };

    createNamespace = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether this workload anchors its side's namespace. Defaults to false: a namespace holding
        somebody's corpus outlives every workload in it, and exactly one thing may own it. Two
        workloads creating one namespace fails eval.
      '';
    };

    version = lib.mkOption {
      type = lib.types.str;
      example = "0.0.0";
      description = ''
        Which version THIS workload runs, used as the image tag. Required, with no default anywhere
        in this repository: no catalogue entry carries a version, because an entry is a KIND of
        software and a version is a value. Two of the four kinds here have shipped a whole-runtime
        rewrite under the same name, which is exactly the case a defaulted version gets wrong.
      '';
    };

    image = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Whole image reference, replacing the catalogue repository plus `version`. Set it to PIN BY
        DIGEST (`repository:tag@sha256:...`), which is the only way two syncs of an identical
        rendered tree cannot run different code -- the grammar warns while it is unpinned.
      '';
    };

    store = lib.mkOption {
      type = lib.types.enum [ "files" "database" "none" ];
      description = ''
        WHAT THIS WORKLOAD'S CONTENT IS AT REST, restated here from the catalogue and checked
        against it. Required, with no default, and that is the point of the option rather than an
        inconvenience: it is what lets a declaration answer, on its own, the only question that
        really matters about a personal corpus.

          `files`     the content is files on disk in a documented format. Anything can read it --
                      an editor, a grep, a backup, an agent -- and this software going away costs
                      you the interface, not the notes.
          `database`  the content is rows. Only this software can read it. Files that sit beside
                      the rows do not change that when their names come from the rows.
          `none`      there is no content. Nothing to back up, nothing to restore.

        Declaring a value the catalogue disagrees with fails eval, naming both. The catalogue is
        the measured side; this is the acknowledgement.
      '';
    };

    exposure = lib.mkOption {
      type = lib.types.enum [ "internal" "nb" "public" ];
      default = "internal";
      description = ''
        WHO can reach this workload, as a class and never an address. `internal` is the default.

        Personal knowledge software is usually reached by exactly one person, which makes the
        private-overlay class the interesting one here and `public` a decision worth being sure
        about: everything in this repository is either a corpus somebody cannot re-create or a
        process that runs what it is sent.
      '';
    };

    scaling = lib.mkOption {
      type = lib.types.enum [ "always" "scale-to-zero" ];
      default = "always";
      description = ''
        Whether this workload keeps a running replica or idles at zero until something wakes it.

        REFUSED for software that keeps working after a request is answered -- a wake front counts
        requests, so it sleeps the pod mid-fetch and the work is silently lost. WARNED about for a
        capture surface, where nothing breaks and a cold start defeats the entire product. Right,
        with no qualification, for the workload that keeps nothing.
      '';
    };

    slot = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.unsigned;
      default = null;
      description = ''
        THE POSITION this workload holds in the fleet's ordered identity space. Not an address --
        the layers underneath map it into however many address spaces the fleet keeps, which is
        exactly why nothing here moves one.

        The VALUE is a fleet fact and belongs to the consumer that passes it in. Every catalogue
        entry in this repository declares ports, so every workload here renders a Service and wants
        one; a workload that rendered none would not. Which RANGE the numbers may come from is a
        different question, answered by the band model -- see `nixnotes.platform.origin`.
      '';
    };

    credentials = lib.mkOption {
      type = lib.types.attrsOf credentialType;
      default = { };
      description = ''
        The credentials this software reads, keyed by the catalogue's ROLE for each one. WHICH
        environment variable a role arrives in is knowledge; which Secret holds it and under which
        key is a value. A role the software does not read is refused, and a required role that is
        missing is refused.

        A SECRET NAMED HERE MAY NOT ALSO BE NAMED FROM ANOTHER SIDE. One of these workloads renders
        pages chosen by whoever pasted a URL; the others hold everything their owner ever wrote.
      '';
    };

    envFromSecrets = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        NAMES of existing Secrets loaded wholesale into the environment, for software whose set of
        keys changes without its declaration changing. Counted by the cross-side guard exactly like
        a named credential -- a whole-Secret mount is the easiest way to hand one side something
        belonging to the other.
      '';
    };

    env = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = ''
        Extra plain environment, merged OVER whatever the catalogue supplies. Plain is the operative
        word: a credential belongs in a Secret, and an address belongs to whatever allocates
        addresses -- the app grammar scans these values and refuses an address literal.

        This is where capacity goes, and where the address of a service this repository does not run
        goes: a search index's host, a mail relay's name. The catalogue supplies what software needs
        in order to be CORRECT and never what it needs in order to be the right size.
      '';
    };

    args = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Extra entrypoint arguments, appended to whatever the catalogue supplies.";
    };

    publicUrl = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "https://example.com";
      description = ''
        The ORIGIN a browser reaches this workload at -- scheme and host, nothing else -- for
        software that has to be told. A fleet fact, which is why it is here and not in the
        catalogue.

        Give no path. The path the software insists on belongs to the software, lives in the
        catalogue entry, and is appended by this module: that split is what makes the classic
        failure -- a sign-in that redirects into nothing while every credential is correct --
        unwritable rather than merely documented.

        Refused on software that reads no such variable, and required on software that does.
      '';
    };
  };

  # Everything with a corpus. The `state` option lives here rather than in `sharedOptions` because
  # a stateless workload has no directory to back and no key to name.
  statefulOptions = sharedOptions // {
    state = lib.mkOption {
      type = lib.types.attrsOf backingType;
      default = { };
      description = ''
        What BACKS each directory this software cannot lose, keyed by the catalogue's own name for
        it. Where each lands inside the container is knowledge and comes from the catalogue; what
        holds it is a value and comes from here.

        EVERY directory the catalogue names must appear. The failure otherwise is the quiet one:
        the workload starts, uses the container's own filesystem, reports itself healthy, and
        loses the corpus at the next restart.
      '';
    };
  };

  # THE STATELESS GROUP, and the two differences are the whole reason it is a separate option set.
  # It has `replicas`, because it is the only thing here that is not the single writer of a store.
  # And its `exposure` enum does not contain `public`.
  statelessOptions = sharedOptions // {
    replicas = lib.mkOption {
      type = lib.types.ints.positive;
      default = 1;
      description = ''
        How many copies run. THE ONLY GROUP IN THIS REPOSITORY THAT HAS THIS OPTION, and the reason
        is the same one that makes it safe here: a workload with a corpus is the single writer of
        it, and a second copy sharing one directory with no coordination is corruption rather than
        capacity. A pure function has no such problem -- every request is independent and nothing
        is kept between two of them.

        Meaningful only with `scaling = "always"`; a scale-to-zero workload's count belongs to its
        wake front.
      '';
    };

    exposure = lib.mkOption {
      type = lib.types.enum [ "internal" "nb" ];
      default = "internal";
      description = ''
        WHO can reach this workload, as a class and never an address. `public` IS NOT IN THIS ENUM,
        and its absence is the encoding of the one thing this group's software has in common: it
        authenticates nobody, and it runs the description it is sent -- whose own documentation says
        it assumes everything it receives is friendly and must not be exposed to untrusted parties.

        That is a missing value rather than a guard that fires, so widening it means editing this
        repository and saying why. See ../studies/the-stateless-workload-is-the-dangerous-one.md.
      '';
    };
  };

  mkKind = { options, extra, description, example }: lib.mkOption {
    default = { };
    inherit description example;
    type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
      options = options // extra;
    }));
  };

  available = group: lib.concatStringsSep ", " (lib.attrNames catalogue.${group});
in
{
  options.nixnotes.platform = {
    notesNamespace = lib.mkOption {
      type = lib.types.str;
      description = ''
        The namespace everything YOU WROTE lands in: the capture surfaces and the notebooks. NO
        DEFAULT, and evaluation fails naming this option the moment one of them is declared.

        There is no per-workload override anywhere in this module, and that is the separation being
        structural rather than advisory: a workload's namespace is its side's, and its side is a
        property of where its content comes from.

        This is the namespace whose contents cannot be re-created by anyone. Nothing in it dials out.
      '';
    };

    linksNamespace = lib.mkOption {
      type = lib.types.str;
      description = ''
        The namespace everything SOMEBODY ELSE WROTE lands in: the archives of pages kept because
        the original may not last.

        It must differ from the other two, and eval fails when it does not, because this is the one
        side that FETCHES REMOTE CONTENT -- to hosts nobody enumerated, chosen by whoever pasted the
        URL. A namespace is what a network policy selects on, so a shared one makes "which of these
        may reach the internet" a question with no expressible answer.
      '';
    };

    chartsNamespace = lib.mkOption {
      type = lib.types.str;
      description = ''
        The namespace for the workloads that keep NOTHING: a description goes in, an artefact comes
        out, and there is no corpus, no backup and no restore.

        Its own namespace for two reasons that pull the same way. It is the side a backup policy
        can skip entirely, which is only expressible if it is separable. And it is the side that
        runs what it is sent, so it is the one whose reachability is worth deciding on its own.
      '';
    };

    project = lib.mkOption {
      type = lib.types.str;
      default = "default";
      description = ''
        Delivery project every workload lands in unless it says otherwise.

        Defaults to `default` -- the delivery tool's own built-in project, which permits every
        destination and is therefore the answer that cannot break a render. It is not the answer to
        leave in place: name a project of your own so this surface is governed like everything else.
      '';
    };

    origin = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "nixnotes";
      description = ''
        The declaring-origin name to stamp on the workloads the app grammar renders, handing their
        slots to the BAND MODEL -- which governs which range of the identity space a declaring
        repository's workloads may take a number from.

        `null` by default because `origin` and `slot` are that model's terms: defining them into a
        render that does not include it fails with "the option does not exist". Set this only when
        it is part of the same render, and set it to the name that model binds a band for.
      '';
    };
  };

  options.nixnotes.streams = mkKind {
    options = statefulOptions;
    description = ''
      Capture surfaces, keyed by a name of your choosing. Software whose unit is a short, dated
      note and whose promise is that writing something down costs seconds.

      This is the group whose entries may keep their content in a database, and it is the honest
      place for them: a capture surface is read through its own feed, and what makes it good is the
      three seconds between having a thought and having written it down. What it is NOT is a
      notebook -- see that group, whose defining property is that everything else can read it too.
    '';
    example = lib.literalExpression ''
      {
        example-jot = {
          stream = "memos";
          version = "0.0.0";
          store = "database";          # restated, and checked against the catalogue
          slot = 41;
          exposure = "nb";
          state.data.hostPath = "/example/state/jot";
        };
      }
    '';
    extra = {
      stream = lib.mkOption {
        type = lib.types.enum (lib.attrNames catalogue.streams);
        description = "Which capture surface, from the catalogue. Available: ${available "streams"}.";
      };
    };
  };

  options.nixnotes.notebooks = mkKind {
    options = statefulOptions;
    description = ''
      Notebooks, keyed by a name of your choosing. A corpus of PAGES ON DISK with a runtime over
      it: the pages are files in a documented format, and the software renders, links, queries and
      executes against them.

      THE ENUM OF THIS OPTION IS THE HOUSE RULE. It is built from the catalogue's notebook table,
      whose defining property is `store = "files"` -- so software that keeps its pages in a
      database is not a refused value here, it is not a value. That rule exists because a notebook
      is developer- and AI-facing by definition: what makes it one is that an editor, a grep, a
      backup and an agent can read it without asking this software anything.
    '';
    example = lib.literalExpression ''
      {
        example-wiki = {
          notebook = "silverbullet";
          version = "0.0.0";
          store = "files";             # the only value this group's catalogue holds
          slot = 42;
          exposure = "nb";
          createNamespace = true;
          state.space.hostPath = "/example/state/wiki";
          # Its authentication is opt-in, so anything past `internal` requires this.
          credentials.login = { secret = "example-wiki-login"; key = "userAndPassword"; };
        };
      }
    '';
    extra = {
      notebook = lib.mkOption {
        type = lib.types.enum (lib.attrNames catalogue.notebooks);
        description = ''
          Which notebook, from the catalogue. Available: ${available "notebooks"}.

          Every entry this enum offers keeps its pages as files on disk. That is not a coincidence
          about what has been catalogued so far -- it is what puts an entry in this group.
        '';
      };
    };
  };

  options.nixnotes.archives = mkKind {
    options = statefulOptions;
    description = ''
      Link archives, keyed by a name of your choosing. Software that keeps a COPY of somebody
      else's page -- the text, the rendering, the file -- rather than only its address, because an
      address is a promise somebody else has to keep.

      THE ONLY GROUP HERE THAT FETCHES REMOTE CONTENT, and every operational difference follows
      from that: it needs egress to hosts nobody enumerated, its store grows at page weight rather
      than at typing speed, and it is the one whose stored bytes came from outside. It lands in its
      own namespace for exactly those reasons, and it cannot be declared `scale-to-zero`, because
      its work outlives the request that started it.
    '';
    example = lib.literalExpression ''
      {
        example-keep = {
          archive = "linkwarden";
          version = "0.0.0";
          store = "database";          # its files are on disk and its records are not: see the catalogue
          slot = 57;
          exposure = "nb";
          createNamespace = true;
          publicUrl = "https://keep.example.com";   # origin only; the path is the catalogue's
          state.archives.hostPath = "/example/state/keep";
          env.MEILI_HOST = "http://example-search.example-links.svc.cluster.local:7700";
          credentials = {
            database = { secret = "example-keep-secrets"; key = "databaseUrl"; };
            session  = { secret = "example-keep-secrets"; key = "sessionSecret"; };
          };
        };
      }
    '';
    extra = {
      archive = lib.mkOption {
        type = lib.types.enum (lib.attrNames catalogue.archives);
        description = "Which archive, from the catalogue. Available: ${available "archives"}.";
      };
    };
  };

  options.nixnotes.renderers = mkKind {
    options = statelessOptions;
    description = ''
      Renderers, keyed by a name of your choosing. A pure function with a URL: a description goes
      in, an artefact comes out, and nothing is kept between two requests.

      IT IS THE ONE GROUP IN A REPOSITORY ABOUT FINDING THINGS AGAIN THAT KEEPS NOTHING, which is
      why it has a different option set rather than a note in a README. There is no `state`, because
      there is nothing to back. There IS a `replicas`, because it is the only thing here that is not
      the single writer of a store. And its `exposure` enum has no `public` in it, because it
      authenticates nobody and runs what it is sent.

      What it is doing in this repository at all: the artefact it produces is embedded in the pages
      the other sides hold. Nothing here depends on it and it depends on nothing here -- that is an
      honest resting place rather than a perfect fit, and moving it later costs one catalogue group
      and one namespace option.
    '';
    example = lib.literalExpression ''
      {
        example-charts = {
          renderer = "quickchart";
          version = "0.0.0";
          store = "none";              # there is nothing to back up, and the declaration says so
          slot = 58;
          scaling = "scale-to-zero";   # the only workload here where this is right without caveat
          createNamespace = true;
        };
      }
    '';
    extra = {
      renderer = lib.mkOption {
        type = lib.types.enum (lib.attrNames catalogue.renderers);
        description = "Which renderer, from the catalogue. Available: ${available "renderers"}.";
      };
    };
  };

  # ── Computed, read-only ───────────────────────────────────────────────────────────────────────

  options.nixnotes.bySide = lib.mkOption {
    type = lib.types.attrsOf (lib.types.listOf lib.types.str);
    readOnly = true;
    default = lib.genAttrs sidesInUse (side: lib.sort (a: b: a < b) (map (x: x.name) (onSide side)));
    defaultText = lib.literalExpression "computed from the declared workloads";
    description = ''
      side -> the workloads on it. Nothing declared a side: it is read from each workload's
      catalogue entry, and it is what decides the namespace.
    '';
  };

  options.nixnotes.onDisk = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    readOnly = true;
    default = lib.listToAttrs
      (map (x: lib.nameValuePair x.name x.entry.format)
        (lib.filter (x: x.entry.store == "files") allWorkloads));
    defaultText = lib.literalExpression "workload -> on-disk format, for every file-backed corpus";
    description = ''
      workload -> the format its corpus is in, for everything whose content is FILES: readable by
      an editor, a grep, a backup and an agent, with or without the software that wrote it.

      This is the list the house rule is about. A consumer can assert on it -- that the notebook is
      in it, and in which format -- rather than trusting that nothing changed.
    '';
  };

  options.nixnotes.opaque = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    readOnly = true;
    default = map (x: x.name) (lib.filter (x: x.entry.store == "database") allWorkloads);
    defaultText = lib.literalExpression "computed from the declared workloads";
    description = ''
      Workloads whose content only they can read. Not a criticism -- a capture surface earns it --
      but it is the list that says which corpora depend on one piece of software continuing to
      exist, and it should be a list somebody chose rather than one that grew.
    '';
  };

  options.nixnotes.stateless = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    readOnly = true;
    default = map (x: x.name) (lib.filter (x: x.entry.store == "none") allWorkloads);
    defaultText = lib.literalExpression "computed from the declared workloads";
    description = ''
      Workloads that keep nothing at all: nothing to back up, nothing to restore, nothing lost if
      the node they were on disappears.

      Together with `onDisk` and `opaque` this partitions every declared workload, and that
      partition is the subject of this repository stated as data.
    '';
  };

  options.nixnotes.egress = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    readOnly = true;
    default = map (x: x.name) (lib.filter (x: x.entry.fetchesRemoteContent) allWorkloads);
    defaultText = lib.literalExpression "computed from the declared workloads";
    description = ''
      Workloads that make requests to hosts their user names, and store what comes back. Read-only,
      and the point of it is that it is COUNTABLE: this is the list of places where content from
      outside enters, and every one of them is in the links namespace by construction.
    '';
  };

  options.nixnotes.dependencies = lib.mkOption {
    type = lib.types.attrsOf (lib.types.listOf lib.types.str);
    readOnly = true;
    default = lib.listToAttrs
      (map (x: lib.nameValuePair x.name (lib.attrNames x.entry.dependsOn))
        (lib.filter (x: x.entry.dependsOn != { }) allWorkloads));
    defaultText = lib.literalExpression "workload -> the service kinds it needs and this repository does not run";
    description = ''
      workload -> the kinds of service it cannot run without, or runs worse without, and that this
      repository neither renders nor names a host for: a SQL engine, a search index.

      Published rather than rendered. What runs a database is a different repository's subject, and
      naming a dependency is not the same as operating it -- but leaving it unnamed would make the
      one workload here that cannot run alone look like the three that can.
    '';
  };

  options.nixnotes.slots = lib.mkOption {
    type = lib.types.attrsOf lib.types.ints.unsigned;
    readOnly = true;
    default = lib.listToAttrs (map (x: lib.nameValuePair x.name x.w.slot) slotClaims);
    defaultText = lib.literalExpression "every declared workload that claims a slot";
    description = ''
      workload -> the position it claims. Nothing is rendered from it here: what an address looks
      like is the private layer's business, and this is what that layer reads to build one.
    '';
  };

  options.nixnotes.renderedByGrammar = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    readOnly = true;
    default = map (x: x.name) allWorkloads;
    defaultText = lib.literalExpression "every declared workload";
    description = ''
      Workloads rendered through the app grammar. EVERY declared workload appears here and there is
      no second list, because nothing in this repository is delivered as a chart, a custom resource
      or a schedule -- the untyped surface is empty, and the option that would create one does not
      exist.
    '';
  };

  config = {
    # THE WHOLE CLUSTER-FACING RENDER, and there is nothing else: every object this surface produces
    # is described as an app, in somebody else's vocabulary.
    nixk3s.apps = lib.listToAttrs (map (x: lib.nameValuePair x.name (mkGrammarApp x)) allWorkloads);

    nixidy.assertions =
      storeAssertions
      ++ storageAssertions
      ++ credentialAssertions
      ++ authAssertions
      ++ scalingAssertions
      ++ publicUrlAssertions
      ++ sideAssertions
      ++ tierAssertions;

    nixidy.warnings = warnings;
  };
}
