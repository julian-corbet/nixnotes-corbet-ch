#
# nixnotes' cluster surface: declare what the personal knowledge surface runs, and render it.
#
# This is a consumer of nixk3s' app grammar, not a Kubernetes renderer. The factory owns the
# repeated image/port/probe/addressing translation. This module keeps the subject-specific split:
# where content came from, what form it has at rest, which namespace therefore contains it, and
# which Secrets may cross none of those boundaries.
#
# All four roots render through the app grammar. There is deliberately no manifests/raw route.
# Stateful roots keep the historical claim-or-hostPath option shape rather than adopting the
# factory's wider backing vocabulary; their exact key and backing guards therefore remain here.
{ mkConsumerModule }:

{ lib, ... }:

let
  rawCatalogue = import ../lib/engines.nix { };

  # The factory's generic public-URL guard needs an environment-variable witness. nixnotes' public
  # catalogue keeps the richer `{ env, path }` record, so adapt the witness without changing the
  # exported catalogue; `extendApp` remains responsible for appending the catalogue-owned path.
  adaptEntry = entry:
    entry
    // lib.optionalAttrs ((entry.publicUrl or null) != null) {
      selfUrlEnv = entry.publicUrl.env;
    };

  catalogue = lib.mapAttrs
    (_: entries: lib.mapAttrs (_: adaptEntry) entries)
    rawCatalogue;

  rootOrder = [ "streams" "notebooks" "archives" "renderers" ];
  ordered = workloads:
    lib.concatMap
      (root: lib.filter (x: x.root == root) workloads)
      rootOrder;

  sideOf = x: x.entry.side;
  onSide = workloads: side: lib.filter (x: sideOf x == side) workloads;
  sides = [ "notes" "links" "charts" ];
  sidesInUse = workloads: lib.filter (side: onSide workloads side != [ ]) sides;

  namespaceOfSide = platform: side: {
    notes = platform.notesNamespace;
    links = platform.linksNamespace;
    charts = platform.chartsNamespace;
  }.${side};

  namespaceOf = x: namespaceOfSide x.platform (sideOf x);

  knownState = x:
    lib.filterAttrs (key: _: x.entry.state ? ${key}) (x.w.state or { });

  stateOf = x:
    lib.mapAttrs
      (key: backing: {
        inherit (x.entry.state.${key}) mountPath readOnly;
        inherit (backing) claim hostPath hostPathType;
      })
      (knownState x);

  publicUrlOf = x:
    lib.optionalAttrs ((x.entry.publicUrl or null) != null && x.w.publicUrl != null) {
      ${x.entry.publicUrl.env} = x.w.publicUrl + x.entry.publicUrl.path;
    };

  secretsOf = x:
    lib.mapAttrs
      (role: declaration: {
        secret = declaration.secret;
        env.${x.entry.credentials.${role}.env} = declaration.key;
      })
      (lib.filterAttrs (role: _: x.entry.credentials ? ${role}) x.w.credentials)
    // lib.listToAttrs
      (map
        (secret: lib.nameValuePair secret { inherit secret; envFrom = true; })
        x.w.envFromSecrets);

  secretNamesOf = x:
    lib.unique
      (lib.mapAttrsToList (_: declaration: declaration.secret) x.w.credentials
      ++ x.w.envFromSecrets);

  probesOf = x:
    lib.optionalAttrs (x.entry.readiness != null) {
      readiness = { port = x.entry.primaryPort; } // x.entry.readiness;
    }
    // lib.optionalAttrs ((x.entry.liveness or null) != null) {
      liveness = { port = x.entry.primaryPort; } // x.entry.liveness;
    };

  extendApp = x:
    x.app // {
      # These are the three deliberately domain-shaped terms. `state` and `credentials` are
      # structurally opted out of the common factory vocabulary; public URL rendering is repeated
      # here so the public catalogue's `{ env, path }` contract remains the sole authority.
      state = stateOf x;
      secrets = secretsOf x;
      env = x.entry.env // publicUrlOf x // x.w.env;
      probes = probesOf x;
    };

  listNames = names: lib.concatMapStringsSep ", " (name: "`${name}`") names;

  legacyStateAssertions = workloads:
    lib.concatMap
      (x: [
        {
          assertion = lib.attrNames (x.w.state or { }) == lib.attrNames x.entry.state;
          message =
            "nixnotes: `${x.name}` must back every directory this software cannot lose, and backs "
            + (if (x.w.state or { }) == { }
              then "none"
              else listNames (lib.attrNames (x.w.state or { })))
            + ". It writes: "
            + (if x.entry.state == { }
              then "nothing at all"
              else lib.concatStringsSep ", "
                (lib.mapAttrsToList (key: state: "`${key}` at ${state.mountPath}") x.entry.state))
            + ". An unbacked one is not an error at runtime -- the workload starts, uses the "
            + "container's own filesystem, reports itself healthy, and loses it at the next restart"
            + lib.optionalString (x.entry.corpus != [ ])
              (", and " + listNames x.entry.corpus + " "
              + (if lib.length x.entry.corpus == 1 then "is" else "are")
              + " the corpus itself")
            + ".";
        }
        {
          assertion = lib.all
            (backing: (backing.claim == null) != (backing.hostPath == null))
            (lib.attrValues (x.w.state or { }));
          message =
            "nixnotes: `${x.name}` backs a directory with neither or both of `claim` and "
            + "`hostPath`. Storage needs exactly one backing: an existing claim by name, or a "
            + "path on the node.";
        }
      ])
      workloads;

  domainAssertions = unorderedWorkloads:
    let
      workloads = ordered unorderedWorkloads;
      inSide = side: onSide workloads side;
      usedSides = sidesInUse workloads;
      namersOf = side: secret:
        map (x: x.name)
          (lib.filter
            (x: sideOf x == side && lib.elem secret (secretNamesOf x))
            (inSide side));
      sidesNaming = secret:
        lib.filter (side: namersOf side secret != [ ]) usedSides;
      crossSideSecrets =
        lib.filter
          (secret: lib.length (sidesNaming secret) > 1)
          (lib.unique (lib.concatMap secretNamesOf workloads));
      catalogueApps = lib.concatMap
        (root: lib.attrNames rawCatalogue.${root})
        rootOrder;
      sidePairs =
        let count = lib.length usedSides;
        in lib.concatMap
          (i: map
            (j: { a = lib.elemAt usedSides i; b = lib.elemAt usedSides j; })
            (lib.range (i + 1) (count - 1)))
          (lib.range 0 (count - 1));
      isOrigin = url:
        (lib.hasPrefix "https://" url || lib.hasPrefix "http://" url)
        && !(lib.hasInfix "/"
          (lib.removePrefix "http://" (lib.removePrefix "https://" url)));
      slotClaims = lib.filter (x: x.w.slot != null) workloads;
      claimantsOf = slot:
        map (x: x.name) (lib.filter (x: x.w.slot == slot) slotClaims);
      duplicatedSlots =
        lib.filter
          (slot: lib.length (claimantsOf slot) > 1)
          (lib.unique (map (x: x.w.slot) slotClaims));
      creatorsOf = namespace:
        map (x: x.name)
          (lib.filter
            (x: x.w.createNamespace && namespaceOf x == namespace)
            workloads);
      createdNamespaces =
        lib.unique
          (map namespaceOf (lib.filter (x: x.w.createNamespace) workloads));
    in
    map
      (x: {
        assertion = x.w.store == x.entry.store;
        message =
          "nixnotes: `${x.name}` declares `store = \"${x.w.store}\"` and this software keeps "
          + "its content as `${x.entry.store}`. The restatement is required on every declaration "
          + "on purpose: it is what makes a declaration answer, on its own, whether anything "
          + "other than this software can read what it holds -- `files` means a person, an editor, "
          + "a backup and an agent can; `database` means only this software can; `none` means "
          + "there is nothing to read. Correct the declaration rather than the catalogue: the "
          + "catalogue is measured.";
      })
      workloads
    ++ lib.concatMap
      (x:
        let
          known = lib.attrNames x.entry.credentials;
          unknown = lib.filter
            (role: !(x.entry.credentials ? ${role}))
            (lib.attrNames x.w.credentials);
          missing = lib.attrNames
            (lib.filterAttrs
              (role: credential:
                credential.required && !(x.w.credentials ? ${role}))
              x.entry.credentials);
        in
        [
          {
            assertion = unknown == [ ];
            message =
              "nixnotes: `${x.name}` names credential role(s) " + listNames unknown
              + " that this software does not read. It reads "
              + (if known == [ ] then "none at all" else listNames known)
              + ". A role nothing reads renders a reference into a variable no process looks at, "
              + "which is worse than being refused because it looks provisioned.";
          }
          {
            assertion = missing == [ ];
            message =
              "nixnotes: `${x.name}` is missing required credential role(s) "
              + listNames missing
              + ". Name the existing Secret and the key inside it -- never the value; everything "
              + "this module renders is committed to git.";
          }
        ])
      workloads
    ++ map
      (x: {
        assertion =
          x.entry.authentication != "optional"
          || x.w.exposure == "internal"
          || (x.w.credentials ? ${toString x.entry.authCredential});
        message =
          "nixnotes: `${x.name}` declares exposure `${x.w.exposure}`, and this software only asks "
          + "for credentials when it is given some -- with none, everyone who can reach it can "
          + "read and write everything in it, and this one can execute inside it too. Supply the "
          + "`${toString x.entry.authCredential}` credential role, or leave the workload "
          + "`internal`. Nothing here will pick the safer class for you: which of the two you "
          + "meant is a decision.";
      })
      workloads
    ++ map
      (x: {
        assertion = !x.entry.backgroundWork || x.w.scaling != "scale-to-zero";
        message =
          "nixnotes: `${x.name}` is declared `scale-to-zero`, and this software keeps working "
          + "after the request that started the work has been answered. A wake front counts "
          + "REQUESTS: it brings the pod up for the one that saved the item and puts it back to "
          + "sleep while the fetch is still running, so the item is saved and its content never "
          + "arrives -- silently, and only for the ones saved in a hurry. Leave it `always`.";
      })
      workloads
    ++ lib.concatMap
      (x: [
        {
          assertion = x.entry.publicUrl == null || x.w.publicUrl != null;
          message =
            "nixnotes: `${x.name}` needs to be told the URL a browser reaches it at, and "
            + "`publicUrl` is unset. There is no default anybody could know -- it is a fleet fact "
            + "-- and the failure without it is a sign-in that redirects into nothing while every "
            + "credential is correct. Give the ORIGIN only (scheme and host); the path this "
            + "software insists on is knowledge and this module appends it.";
        }
        {
          assertion = x.entry.publicUrl != null || x.w.publicUrl == null;
          message =
            "nixnotes: `${x.name}` sets `publicUrl`, and this software reads no such variable -- "
            + "so the value would reach no object at all. Whatever fronts it knows its own "
            + "address; this workload does not need to.";
        }
        {
          assertion = x.w.publicUrl == null || isOrigin x.w.publicUrl;
          message =
            "nixnotes: `${x.name}` gives `publicUrl = \"${toString x.w.publicUrl}\"`, which is "
            + "not a bare origin. It must be a scheme and a host and nothing else (no trailing "
            + "slash, no path): the path this software requires comes from the catalogue and is "
            + "appended here, so a path in this value produces a URL with two of them.";
        }
      ])
      workloads
    ++ map
      (secret: {
        assertion = false;
        message =
          "nixnotes: Secret `${secret}` is named from more than one side -- "
          + lib.concatMapStringsSep "; "
            (side: "`${side}`: " + listNames (namersOf side secret))
            (sidesNaming secret)
          + ". The sides are separate because their contents have different origins and different "
          + "consequences: the links side fetches pages chosen by whoever pasted a URL and renders "
          + "them in a browser, and the notes side holds everything its owner ever wrote. One "
          + "Secret object reaching both makes a compromise of the first a compromise of the "
          + "second. Unseal a second Secret, in the other namespace, carrying only what that "
          + "workload needs.";
      })
      crossSideSecrets
    ++ map
      (pair: {
        assertion =
          namespaceOf (lib.head (inSide pair.a))
          != namespaceOf (lib.head (inSide pair.b));
        message =
          "nixnotes: the `${pair.a}` and `${pair.b}` sides are declared into the SAME namespace, "
          + "and this surface has workloads on both. The separation IS the namespaces: it is what "
          + "a network policy selects on when it decides which of these may dial the internet, "
          + "what a backup policy selects on when it decides what is irreplaceable, and what a "
          + "Secret set unseals into. Give them one each.";
      })
      sidePairs
    ++ map
      (side:
        let namespace = namespaceOf (lib.head (inSide side));
        in {
          assertion = !(lib.elem namespace catalogueApps);
          message =
            "nixnotes: the `${side}` side's namespace is `${namespace}`, which is the name of an "
            + "application in this catalogue. A namespace named after one of its own tenants stops "
            + "being able to hold the second one honestly -- every other workload in it reads as "
            + "a guest, and the day you add one the only fix is renaming a namespace, which is a "
            + "migration. Name it after what the side IS.";
        })
      usedSides
    ++ map
      (slot: {
        assertion = false;
        message =
          "nixnotes: slot ${toString slot} is claimed by more than one workload: "
          + listNames (claimantsOf slot)
          + ". A slot is one identity in every address space the fleet maps it into, so two "
          + "claimants is a collision in all of them at once.";
      })
      duplicatedSlots
    ++ map
      (namespace: {
        assertion = lib.length (creatorsOf namespace) == 1;
        message =
          "nixnotes: namespace `${namespace}` is created by more than one workload: "
          + listNames (creatorsOf namespace)
          + ". Two Applications owning one Namespace fight over it. Let exactly one anchor it, "
          + "or anchor it in the tenancy layer and set `createNamespace = false` on all of them.";
      })
      createdNamespaces;

  domainWarnings = unorderedWorkloads:
    let
      workloads = ordered unorderedWorkloads;
      showSlot = x: if x.w.slot == null then "(none)" else toString x.w.slot;
    in
    map
      (x: {
        when = x.w.scaling == "scale-to-zero";
        message =
          "nixnotes: `${x.name}` is a capture surface declared `scale-to-zero`. Nothing breaks -- "
          + "it keeps no outstanding work -- but the entire promise of this kind of software is "
          + "that writing something down costs seconds, and a cold start is the one cost that "
          + "defeats it. The thought you were capturing is gone by the time the pod is up.";
      })
      (lib.filter (x: x.root == "streams") workloads)
    ++ map
      (x: {
        when = x.w.scaling == "always";
        message =
          "nixnotes: `${x.name}` keeps nothing at all and is declared `always`, so it is a pod "
          + "holding a rendering toolchain between two requests that may be hours apart. This is "
          + "the one workload here that can idle at zero with nothing to reload and nothing "
          + "outstanding -- which is worth saying because it is the only one.";
      })
      (lib.filter (x: x.entry.store == "none") workloads)
    ++ map
      (x: {
        when = x.w.slot != null && x.platform.origin == null;
        message =
          "nixnotes: `${x.name}` claims slot ${showSlot x}, and `nixnotes.platform.origin` is "
          + "unset -- so the number is checked for collisions inside this surface, and by nothing "
          + "for which RANGE it may come from. Set the origin when the band model is part of the "
          + "same render.";
      })
      workloads;

  backingType = lib.types.submodule {
    options = {
      claim = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Name of an existing PersistentVolumeClaim backing this directory.";
      };
      hostPath = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Path on the node backing this directory instead of a claim.";
      };
      hostPathType = lib.mkOption {
        type = lib.types.enum [ "Directory" "DirectoryOrCreate" ];
        default = "Directory";
        description = "Whether a missing node directory is an error or is created empty.";
      };
    };
  };

  credentialType = lib.types.submodule {
    options = {
      secret = lib.mkOption {
        type = lib.types.str;
        description = "Name of an existing Secret holding this credential.";
      };
      key = lib.mkOption {
        type = lib.types.str;
        description = "Key inside that Secret carrying the credential.";
      };
    };
  };

  versionOption = lib.mkOption {
    type = lib.types.str;
    example = "0.0.0";
    description = "Version this workload runs; required and defaulted nowhere.";
  };

  storeOption = lib.mkOption {
    type = lib.types.enum [ "files" "database" "none" ];
    description = "How this workload keeps its content at rest, restated from the catalogue.";
  };

  credentialsOption = lib.mkOption {
    type = lib.types.attrsOf credentialType;
    default = { };
    description = "Existing Secret references keyed by the catalogue's credential roles.";
  };

  envFromSecretsOption = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    description = "Existing Secrets loaded wholesale into the environment.";
  };

  stateOption = lib.mkOption {
    type = lib.types.attrsOf backingType;
    default = { };
    description = "Claim-or-hostPath backing for every catalogue state directory.";
  };

  replicasOption = lib.mkOption {
    type = lib.types.ints.positive;
    default = 1;
    description = "Replica count for the stateless renderer.";
  };

  rendererExposureOption = lib.mkOption {
    type = lib.types.enum [ "internal" "nb" ];
    default = "internal";
    description = "Who can reach the unauthenticated renderer; public is structurally absent.";
  };

  sharedEnabledOptions = [
    "version"
    "image"
    "createNamespace"
    "adopt"
    "project"
    "slot"
    "exposure"
    "scaling"
    "publicUrl"
    "env"
    "args"
  ];

  sharedExtraOptions = {
    version = versionOption;
    store = storeOption;
    credentials = credentialsOption;
    envFromSecrets = envFromSecretsOption;
  };

  statefulRoot = root: selector: {
    catalogue = catalogue.${root};
    inherit selector namespaceOf;
    enabledOptions = sharedEnabledOptions;
    extraOptions = sharedExtraOptions // { state = stateOption; };
    extend = extendApp;
    assertions = legacyStateAssertions;
    description = "Stateful nixnotes ${root}, keyed by a workload name.";
  };

  reportOptions = {
    bySide = lib.mkOption {
      type = lib.types.attrsOf (lib.types.listOf lib.types.str);
      readOnly = true;
      description = "Side to the workloads catalogued on it.";
    };
    onDisk = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      readOnly = true;
      description = "Workload to on-disk format for file-backed corpora.";
    };
    opaque = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      readOnly = true;
      description = "Workloads whose content only their own software can read.";
    };
    stateless = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      readOnly = true;
      description = "Workloads that keep no content.";
    };
    egress = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      readOnly = true;
      description = "Workloads that fetch remote content selected by their user.";
    };
    dependencies = lib.mkOption {
      type = lib.types.attrsOf (lib.types.listOf lib.types.str);
      readOnly = true;
      description = "Services each workload needs and this repository does not run.";
    };
    slots = lib.mkOption {
      type = lib.types.attrsOf lib.types.ints.unsigned;
      readOnly = true;
      description = "Legacy workload-to-slot report; equal to clusterSlots.";
    };
  };

  reportConfig = unorderedWorkloads:
    let
      workloads = ordered unorderedWorkloads;
      usedSides = sidesInUse workloads;
      slotClaims = lib.filter (x: x.w.slot != null) workloads;
    in {
      nixnotes = {
        bySide = lib.genAttrs usedSides
          (side: lib.sort (a: b: a < b)
            (map (x: x.name) (onSide workloads side)));
        onDisk = lib.listToAttrs
          (map
            (x: lib.nameValuePair x.name x.entry.format)
            (lib.filter (x: x.entry.store == "files") workloads));
        opaque = map
          (x: x.name)
          (lib.filter (x: x.entry.store == "database") workloads);
        stateless = map
          (x: x.name)
          (lib.filter (x: x.entry.store == "none") workloads);
        egress = map
          (x: x.name)
          (lib.filter (x: x.entry.fetchesRemoteContent) workloads);
        dependencies = lib.listToAttrs
          (map
            (x: lib.nameValuePair x.name (lib.attrNames x.entry.dependsOn))
            (lib.filter (x: x.entry.dependsOn != { }) workloads));
        slots = lib.listToAttrs
          (map (x: lib.nameValuePair x.name x.w.slot) slotClaims);
      };
    };

  factoryModule = mkConsumerModule {
    namespace = "nixnotes";
    platformOption = "platform";

    roots = {
      streams = statefulRoot "streams" "stream";
      notebooks = statefulRoot "notebooks" "notebook";
      archives = statefulRoot "archives" "archive";
      renderers = {
        catalogue = catalogue.renderers;
        selector = "renderer";
        inherit namespaceOf;
        enabledOptions = sharedEnabledOptions ++ [ "replicas" ];
        extraOptions = sharedExtraOptions // {
          replicas = replicasOption;
          exposure = rendererExposureOption;
        };
        extend = extendApp;
        description = "Stateless nixnotes renderers, keyed by a workload name.";
      };
    };

    extraPlatformOptions = {
      notesNamespace = lib.mkOption {
        type = lib.types.str;
        description = "Namespace for content its owner wrote.";
      };
      linksNamespace = lib.mkOption {
        type = lib.types.str;
        description = "Namespace for archived remote content.";
      };
      chartsNamespace = lib.mkOption {
        type = lib.types.str;
        description = "Namespace for stateless renderers.";
      };
    };

    extraNamespaceOptions = reportOptions;
    extraAssertions = domainAssertions;
    extraWarnings = domainWarnings;
    extraConfig = reportConfig;
  };
in
{
  imports = [ factoryModule ];

  # The factory deliberately has no project default. nixnotes already does, and retaining it here
  # also keeps every per-workload `project` default resolved through the same platform option.
  config.nixnotes.platform.project = lib.mkDefault "default";
}
