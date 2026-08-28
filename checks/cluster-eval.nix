# Proves the cluster module resolves what it claims and REFUSES what it claims to refuse, both
# directions, through the real renderer and the real app grammar.
#
# Both halves matter and neither is enough alone. A guard nobody has watched fire is a comment; a
# guard that fires on everything is a wall. So every case below is a complete, otherwise-valid
# surface with exactly one thing wrong, and the `control` case is the same shape with nothing wrong
# and MUST render -- without it, a typo in the shared base would make every other case "pass" for
# the wrong reason.
#
# ── THE PART THAT IS NOT AN ASSERTION ──────────────────────────────────────────────────────────
#
# Several of the most important refusals in this repository are not guards at all. Giving a
# workload its own namespace, giving a corpus a second replica, giving the stateless renderer a
# directory, or passing verbatim manifests through are UNKNOWN OPTIONS: they fail with "the option
# does not exist", which is the difference between a boundary somebody has to remember and one
# nobody can cross. Those cases are in `structurallyImpossible` below, so re-adding any of those
# options would break this check rather than quietly widening the surface.
#
# Two more are refused VALUES rather than missing options, and they are in `mustFail` with the
# guards: a database-store engine declared as a notebook (the enum is built from the notebook
# table) and the renderer declared `public` (that enum has no such value).
#
# Three refusals additionally have their MESSAGE asserted by content, because `tryEval` can only say
# THAT something was refused: the cross-side Secret refusal (it has to name the Secret and both
# sides), the store-mismatch refusal (it has to name both values, since the declaration is the half
# that is wrong), and the scale-to-zero refusal (it has to explain a failure nobody would guess).
{ pkgs, lib, nixidy, appsModule, addressingModule, clusterModule }:
let
  base = {
    nixidy.target.repository = "https://example.com/example-org/example-gitops.git";
    nixidy.target.branch = "main";
    nixnotes.platform = {
      notesNamespace = "example-notes";
      linksNamespace = "example-links";
      chartsNamespace = "example-charts";
      project = "example-knowledge";
    };
  };

  mkEnv = values: nixidy.lib.mkEnv {
    inherit pkgs;
    modules = [ appsModule addressingModule clusterModule base values ];
  };

  renders = values:
    (builtins.tryEval (builtins.seq (mkEnv values).environmentPackage.drvPath true)).success;

  # The assertions themselves rather than the throw they eventually cause.
  failures = values:
    map (a: a.message)
      (lib.filter (a: !a.assertion) (mkEnv values).config.nixidy.assertions);

  sorted = lib.sort (a: b: a < b);

  ## ---------------------------------------------------------------------
  ## The floor: an empty surface renders nothing at all
  ## ---------------------------------------------------------------------

  emptyCfg = (mkEnv { }).config;

  ## ---------------------------------------------------------------------
  ## The control: one workload of every kind, on all three sides
  ## ---------------------------------------------------------------------

  good = {
    nixnotes.streams.jot = {
      stream = "memos";
      version = "0.0.0";
      store = "database";
      slot = 41;
      exposure = "nb";
      state.data.hostPath = "/example/state/jot";
    };

    nixnotes.notebooks.wiki = {
      notebook = "silverbullet";
      version = "0.0.0";
      store = "files";
      slot = 42;
      exposure = "nb";
      createNamespace = true;
      state.space.hostPath = "/example/state/wiki";
      credentials.login = { secret = "example-notes-secrets"; key = "wikiLogin"; };
    };

    nixnotes.archives.keep = {
      archive = "linkwarden";
      version = "0.0.0";
      store = "database";
      slot = 43;
      exposure = "nb";
      createNamespace = true;
      publicUrl = "https://keep.example.com";
      state.archives.hostPath = "/example/state/keep";
      env.MEILI_HOST = "http://example-search.example-links.svc.cluster.local:7700";
      credentials = {
        database = { secret = "example-links-secrets"; key = "databaseUrl"; };
        session = { secret = "example-links-secrets"; key = "sessionSecret"; };
      };
    };

    nixnotes.renderers.charts = {
      renderer = "quickchart";
      version = "0.0.0";
      store = "none";
      slot = 44;
      scaling = "scale-to-zero";
      createNamespace = true;
    };
  };

  goodCfg = (mkEnv good).config;

  # The factory's platform project is defaultless by design; nixnotes' established public contract
  # resolves it to the delivery tool's `default`. Exercise that without the test base supplying a
  # project of its own.
  defaultProjectCfg = (nixidy.lib.mkEnv {
    inherit pkgs;
    modules = [
      appsModule
      addressingModule
      clusterModule
      {
        nixidy.target.repository = "https://example.com/example-org/example-gitops.git";
        nixidy.target.branch = "main";
        nixnotes.platform.notesNamespace = "example-notes";
        nixnotes.streams.default-project = {
          stream = "memos";
          version = "0.0.0";
          store = "database";
          state.data.claim = "example-default-project";
        };
      }
    ];
  }).config;

  ## ---------------------------------------------------------------------
  ## The failing direction: guards
  ## ---------------------------------------------------------------------

  mustFail = {
    # THE RESTATEMENT. A declaration that claims its corpus is readable when it is rows is the one
    # mistake this repository most wants to be impossible to make quietly.
    store-restated-as-something-it-is-not =
      lib.recursiveUpdate good { nixnotes.streams.jot.store = "files"; };

    # THE HOUSE RULE, as a value the option does not have. The enum comes from the notebook table,
    # whose defining property is files on disk.
    database-backed-engine-declared-as-a-notebook =
      lib.recursiveUpdate good { nixnotes.notebooks.wiki.notebook = "memos"; };

    # THE OPT-IN AUTHENTICATION GUARD. Nothing breaks: it works perfectly, for everybody.
    optional-authentication-reachable-with-no-credential =
      lib.recursiveUpdate good { nixnotes.notebooks.wiki.credentials = lib.mkForce { }; };

    # THE BACKGROUND-WORK GUARD. The request succeeds and the content never arrives.
    archive-scaled-to-zero =
      lib.recursiveUpdate good { nixnotes.archives.keep.scaling = "scale-to-zero"; };

    # THE CROSS-SIDE SECRET. The thing that renders arbitrary pages in a browser must not hold the
    # credential that opens the thing holding everything you ever wrote.
    one-secret-named-from-two-sides =
      lib.recursiveUpdate good { nixnotes.streams.jot.envFromSecrets = [ "example-links-secrets" ]; };

    # And the floor under that: one namespace for two sides makes the split unenforceable by
    # anything, since a network policy and a backup policy both select on the namespace.
    two-sides-in-one-namespace =
      lib.recursiveUpdate good { nixnotes.platform.linksNamespace = "example-notes"; };

    # A namespace named after one of its own tenants cannot hold the second one honestly.
    namespace-named-after-an-application =
      lib.recursiveUpdate good { nixnotes.platform.notesNamespace = "silverbullet"; };

    # Every directory the software cannot lose must be backed. The failure otherwise is an empty
    # notebook that reports itself healthy.
    corpus-directory-left-unbacked =
      lib.recursiveUpdate good { nixnotes.notebooks.wiki.state = lib.mkForce { }; };

    state-with-no-backing =
      lib.recursiveUpdate good { nixnotes.notebooks.wiki.state.space.hostPath = lib.mkForce null; };

    state-with-both-backings =
      lib.recursiveUpdate good { nixnotes.notebooks.wiki.state.space.claim = "example-wiki-space"; };

    state-key-the-catalogue-does-not-hold =
      lib.recursiveUpdate good { nixnotes.streams.jot.state.attachments.hostPath = "/example/state/jot-files"; };

    credential-role-the-software-does-not-read =
      lib.recursiveUpdate good {
        nixnotes.streams.jot.credentials.rootPassword = { secret = "x"; key = "y"; };
      };

    missing-required-credential-role =
      lib.recursiveUpdate good {
        nixnotes.archives.keep.credentials = lib.mkForce {
          session = { secret = "example-links-secrets"; key = "sessionSecret"; };
        };
      };

    # The public URL: required where the software reads one, refused where it does not, and an
    # ORIGIN rather than a URL with a path -- the module appends the path the software insists on.
    public-url-missing-on-software-that-needs-one =
      lib.recursiveUpdate good { nixnotes.archives.keep.publicUrl = lib.mkForce null; };

    public-url-set-on-software-that-reads-none =
      lib.recursiveUpdate good { nixnotes.notebooks.wiki.publicUrl = "https://wiki.example.com"; };

    public-url-carrying-a-path-of-its-own =
      lib.recursiveUpdate good { nixnotes.archives.keep.publicUrl = "https://keep.example.com/api/v1/auth"; };

    # The renderer authenticates nobody and runs what it is sent: `public` is not in its enum.
    renderer-declared-public =
      lib.recursiveUpdate good { nixnotes.renderers.charts.exposure = "public"; };

    two-workloads-on-one-slot =
      lib.recursiveUpdate good { nixnotes.streams.jot.slot = 42; };

    two-workloads-creating-one-namespace =
      lib.recursiveUpdate good { nixnotes.streams.jot.createNamespace = true; };
  };

  ## ---------------------------------------------------------------------
  ## The failing direction: the separation, which is not a guard
  ##
  ## Each of these is an UNKNOWN OPTION rather than a refused value. That is the whole claim of this
  ## repository's design, so it is checked rather than asserted in prose.
  ## ---------------------------------------------------------------------

  structurallyImpossible = {
    workload-given-its-own-namespace =
      lib.recursiveUpdate good { nixnotes.archives.keep.namespace = "example-somewhere-else"; };

    workload-declaring-its-own-side =
      lib.recursiveUpdate good { nixnotes.archives.keep.side = "notes"; };

    # Everything with a corpus is the single writer of it. A second copy is corruption, not
    # capacity, and there is no option here to ask for one.
    corpus-workload-given-a-replica-count =
      lib.recursiveUpdate good { nixnotes.notebooks.wiki.replicas = 2; };

    # The stateless group has no `state` option: there is nothing to back.
    stateless-workload-given-a-directory =
      lib.recursiveUpdate good { nixnotes.renderers.charts.state.data.hostPath = "/example/state/charts"; };

    # Nothing in this repository is delivered as anything but an image, so neither of the two
    # escape hatches the siblings need exists here.
    workload-passing-verbatim-manifests =
      lib.recursiveUpdate good {
        nixnotes.streams.jot.manifests = [ "apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: x\n" ];
      };

    workload-passing-raw-objects =
      lib.recursiveUpdate good {
        nixnotes.streams.jot.raw = [ "apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: x\n" ];
      };
  };

  wronglyRendered =
    lib.attrNames (lib.filterAttrs (_: v: v) (lib.mapAttrs (_: renders) mustFail));
  wronglyAccepted =
    lib.attrNames (lib.filterAttrs (_: v: v) (lib.mapAttrs (_: renders) structurallyImpossible));

  ## ---------------------------------------------------------------------
  ## Messages, read as text
  ## ---------------------------------------------------------------------

  firstMatching = values: needle:
    let msgs = lib.filter (m: lib.hasInfix needle m) (failures values); in
    if msgs == [ ] then "" else lib.head msgs;

  crossSideMessage = firstMatching mustFail.one-secret-named-from-two-sides "example-links-secrets";
  storeMessage = firstMatching mustFail.store-restated-as-something-it-is-not "`jot`";
  scalingMessage = firstMatching mustFail.archive-scaled-to-zero "`keep`";

  ## ---------------------------------------------------------------------
  ## Positive resolution, with the band model in the render
  ## ---------------------------------------------------------------------

  addressed = (mkEnv (lib.recursiveUpdate good {
    nixnotes.platform.origin = "nixnotes";
    nixk3s.addressing = {
      enable = true;
      bands.example-personal = { base = 40; size = 16; };
      bindings.nixnotes = "example-personal";
    };
  })).config;

  results = {
    # ── The floor ─────────────────────────────────────────────────────────────────────────────
    "an empty surface defines no app in the grammar at all" =
      emptyCfg.nixk3s.apps == { };

    "an empty surface reports nothing on any side, nothing stored, and no slot" =
      emptyCfg.nixnotes.bySide == { } && emptyCfg.nixnotes.onDisk == { }
      && emptyCfg.nixnotes.opaque == [ ] && emptyCfg.nixnotes.stateless == [ ]
      && emptyCfg.nixnotes.egress == [ ] && emptyCfg.nixnotes.dependencies == { }
      && emptyCfg.nixnotes.slots == { } && emptyCfg.nixnotes.renderedByGrammar == [ ];

    "an empty surface raises no assertion of its own -- an unused module must be silent" =
      lib.all (a: a.assertion) emptyCfg.nixidy.assertions;

    # ── The control ───────────────────────────────────────────────────────────────────────────
    "one workload of every kind, on all three sides, renders" = renders good;

    "every declared workload goes through the grammar -- there is no second, untyped route" =
      sorted goodCfg.nixnotes.renderedByGrammar == [ "charts" "jot" "keep" "wiki" ]
      && sorted (lib.attrNames goodCfg.nixk3s.apps) == [ "charts" "jot" "keep" "wiki" ];

    "the established project default survives factory construction" =
      defaultProjectCfg.nixnotes.platform.project == "default"
      && defaultProjectCfg.nixk3s.apps.default-project.project == "default";

    "legacy and standard reports agree, and this repository has no untyped render route" =
      goodCfg.nixnotes.slots == goodCfg.nixnotes.clusterSlots
      && goodCfg.nixnotes.renderedDirectly == [ ]
      && goodCfg.nixnotes.notRendered == [ ];

    # ── THE SIDES, RESOLVED ───────────────────────────────────────────────────────────────────
    "a workload's namespace is its SIDE's, and nothing declared it" =
      goodCfg.nixk3s.apps.jot.namespace == "example-notes"
      && goodCfg.nixk3s.apps.wiki.namespace == "example-notes"
      && goodCfg.nixk3s.apps.keep.namespace == "example-links"
      && goodCfg.nixk3s.apps.charts.namespace == "example-charts";

    "the sides are exactly what the catalogue puts on them" =
      goodCfg.nixnotes.bySide == {
        notes = [ "jot" "wiki" ];
        links = [ "keep" ];
        charts = [ "charts" ];
      };

    # ── WHAT EACH ONE KEEPS, WHICH IS THE SUBJECT OF THIS REPOSITORY ──────────────────────────
    "the three stores partition the surface, and the readable one names its format" =
      goodCfg.nixnotes.onDisk == { wiki = "markdown"; }
      && sorted goodCfg.nixnotes.opaque == [ "jot" "keep" ]
      && goodCfg.nixnotes.stateless == [ "charts" ]
      && lib.length
        (lib.attrNames goodCfg.nixnotes.onDisk
        ++ goodCfg.nixnotes.opaque ++ goodCfg.nixnotes.stateless) == 4;

    "the one workload that fetches remote content is countable, and it is on the links side" =
      goodCfg.nixnotes.egress == [ "keep" ]
      && goodCfg.nixnotes.bySide.links == goodCfg.nixnotes.egress;

    "what this surface needs and does not run is named rather than left implicit" =
      goodCfg.nixnotes.dependencies == { keep = [ "search" "sql" ]; };

    # ── The knowledge reaches the objects ─────────────────────────────────────────────────────
    "the image is the catalogue repository plus THIS workload's version" =
      goodCfg.nixk3s.apps.wiki.image == "ghcr.io/silverbulletmd/silverbullet:0.0.0"
      && goodCfg.nixk3s.apps.jot.image == "neosmemo/memos:0.0.0";

    "each directory lands where the software writes it, backed by what the consumer supplied" =
      goodCfg.nixk3s.apps.wiki.state.space.mountPath == "/space"
      && goodCfg.nixk3s.apps.wiki.state.space.hostPath == "/example/state/wiki"
      && goodCfg.nixk3s.apps.jot.state.data.mountPath == "/var/opt/memos"
      && goodCfg.nixk3s.apps.keep.state.archives.mountPath == "/data/data";

    "the stateless workload mounts nothing, and asks for no storage at all" =
      goodCfg.nixk3s.apps.charts.state == { };

    "single-writer reaches the grammar from the catalogue rather than from a backing accident" =
      goodCfg.nixk3s.apps.jot.singleWriter
      && goodCfg.nixk3s.apps.wiki.singleWriter
      && goodCfg.nixk3s.apps.keep.singleWriter
      && !goodCfg.nixk3s.apps.charts.singleWriter;

    # THE ONE COMPOSED VALUE. The origin is the declaration's, the path is the catalogue's, and
    # nobody writes the second half.
    "the public URL is joined from a supplied origin and a known path" =
      goodCfg.nixk3s.apps.keep.env.NEXTAUTH_URL == "https://keep.example.com/api/v1/auth";

    "correctness environment comes from the catalogue, and a value from the declaration" =
      goodCfg.nixk3s.apps.keep.env.STORAGE_FOLDER == "/data/data"
      && goodCfg.nixk3s.apps.keep.env.MEILI_HOST
      == "http://example-search.example-links.svc.cluster.local:7700";

    "a credential arrives as a reference, under the variable the SOFTWARE names, never as a value" =
      goodCfg.nixk3s.apps.wiki.secrets.login.env.SB_USER == "wikiLogin"
      && goodCfg.nixk3s.apps.keep.secrets.database.env.DATABASE_URL == "databaseUrl"
      && goodCfg.nixk3s.apps.keep.secrets.session.secret == "example-links-secrets";

    "an optional credential nobody named renders nothing at all" =
      !(goodCfg.nixk3s.apps.keep.secrets ? searchKey);

    "a probe watches the port the catalogue calls primary, with the software's own timing" =
      goodCfg.nixk3s.apps.wiki.probes.readiness.path == "/.ping"
      && goodCfg.nixk3s.apps.jot.probes.readiness.path == "/healthz"
      && goodCfg.nixk3s.apps.charts.probes.readiness.path == "/healthcheck"
      && goodCfg.nixk3s.apps.keep.probes.readiness.path == null
      && goodCfg.nixk3s.apps.keep.probes.readiness.initialDelaySeconds == 30;

    "the only workload that scales to zero is the one with nothing to reload" =
      goodCfg.nixk3s.apps.charts.scaling == "scale-to-zero"
      && goodCfg.nixk3s.apps.jot.scaling == "always"
      && goodCfg.nixk3s.apps.keep.scaling == "always";

    # ── The band model ────────────────────────────────────────────────────────────────────────
    "with the band model in the render, every workload carries the declaring origin and its slot" =
      addressed.nixk3s.apps.wiki.origin == "nixnotes"
      && addressed.nixk3s.apps.wiki.slot == 42
      && addressed.nixk3s.apps.charts.slot == 44;

    "without that switch the grammar's apps name no origin at all -- those are the band model's terms" =
      goodCfg.nixk3s.apps.wiki.origin == null && goodCfg.nixk3s.apps.wiki.slot == null;

    "and the slot report is what a private layer reads to build an address" =
      goodCfg.nixnotes.slots == { jot = 41; wiki = 42; keep = 43; charts = 44; };

    # ── The failing direction ─────────────────────────────────────────────────────────────────
    "every guard fires: nothing in the must-fail set renders" =
      wronglyRendered == [ ];

    "the separation is structural: every boundary-crossing declaration is an unknown option" =
      wronglyAccepted == [ ];

    "the cross-side refusal names the Secret and the workloads on both sides of it" =
      lib.hasInfix "example-links-secrets" crossSideMessage
      && lib.hasInfix "`jot`" crossSideMessage
      && lib.hasInfix "`keep`" crossSideMessage;

    "the store-mismatch refusal names both values, since the declaration is the half that is wrong" =
      lib.hasInfix "\"files\"" storeMessage && lib.hasInfix "`database`" storeMessage;

    "the scale-to-zero refusal explains a failure nobody would guess from the symptom" =
      lib.hasInfix "after the request" scalingMessage
      && lib.hasInfix "back to sleep" scalingMessage;
  };

  failed = lib.attrNames (lib.filterAttrs (_: passed: !passed) results);
in
if failed == [ ]
then
  pkgs.writeText "nixnotes-cluster-eval" ''
    control renders, the floor holds, and every guard fires:
    ${lib.concatMapStringsSep "\n" (n: "  refused: ${n}") (lib.attrNames mustFail)}
    and these are not refusals at all -- they are unknown options:
    ${lib.concatMapStringsSep "\n" (n: "  impossible: ${n}") (lib.attrNames structurallyImpossible)}
  ''
else
  throw ''
    nixnotes: cluster-eval check failed. Failing assertions:
    ${lib.concatMapStringsSep "\n" (f: "  - ${f}") failed}
    ${lib.optionalString (wronglyRendered != [ ])
      "Declarations that rendered but had to be refused: ${lib.concatStringsSep ", " wronglyRendered}"}
    ${lib.optionalString (wronglyAccepted != [ ])
      "Declarations that evaluated but had to be unknown options: ${lib.concatStringsSep ", " wronglyAccepted}"}
  ''
