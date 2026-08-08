# Placeholder values for the cluster module — the file that makes the render check real.
# `nix flake check` renders the whole surface from here, so a module that stops evaluating, or that
# grows a required value nobody supplies, fails in CI rather than in somebody's cluster.
#
# NOTHING HERE IS REAL. Every namespace, path, name, number, URL and image is invented for this
# file, and no credential appears in any form — only the NAMES of Secrets that would hold them.
#
# The declarations are chosen to put ALL THREE SIDES in one render, and to cover the paths that
# differ in what gets RENDERED rather than merely in what evaluates:
#
#   - a capture surface whose corpus is rows, on node-path state, reachable to a private overlay;
#   - a notebook whose corpus is Markdown files, anchoring the notes namespace, with the credential
#     that switches its opt-in authentication on — without which nothing here would let it past
#     `internal`;
#   - an archive on the OTHER side: its own namespace, its own Secret, a public URL joined from an
#     origin it supplies and a path it does not, the address of a service this repository does not
#     run, and a digest-pinned image;
#   - a renderer on the THIRD side, which mounts nothing, scales to zero, and is the only workload
#     here with a replica count available to it at all.
{
  # Required by the nixidy environment itself, not by any module here.
  nixidy.target.repository = "https://example.com/example-org/example-gitops.git";
  nixidy.target.branch = "main";

  # A cluster fact the app grammar refuses to guess: which node holds the directories that
  # node-path state lives on. Set once here instead of on every workload.
  nixk3s.appPlatform.hostPathNodeSelector = { "kubernetes.io/hostname" = "example-node"; };

  # The band model, with the layout a consumer would supply. Every value is invented: the model
  # ships no band, no base and no binding, because which category owns which run of the number
  # space is the shape of somebody's fleet — and so does this repository.
  nixk3s.addressing = {
    enable = true;
    bands.example-personal = {
      base = 40;
      size = 16;
      description = "one person's own things";
    };
    bindings.nixnotes = "example-personal";
  };

  nixnotes.platform = {
    # THE THREE NAMESPACES ARE THE SEPARATION. What you wrote, what somebody else wrote and you
    # kept, and the thing that keeps nothing. None of them is named after an application in the
    # catalogue, and evaluation refuses it if one is.
    notesNamespace = "example-notes";
    linksNamespace = "example-links";
    chartsNamespace = "example-charts";
    project = "example-knowledge";
    # Hands the workloads' slots to the band model above. Null (the default) everywhere that model
    # is not part of the render.
    origin = "nixnotes";
  };

  # A capture surface: open it, type, done. Its notes are rows in a database inside that directory,
  # which is what `store` says out loud — copying the directory gets the notes back, and nothing
  # else will ever read one of them.
  nixnotes.streams.example-jot = {
    stream = "memos";
    version = "0.0.0";
    store = "database";
    slot = 41;
    exposure = "nb";
    state.data.hostPath = "/example/state/jot";
  };

  # The notebook: a directory of Markdown pages with a runtime over them. It anchors the notes
  # namespace, because it is rendered by the app grammar and therefore stamps the protection a
  # namespace holding somebody's corpus needs.
  nixnotes.notebooks.example-wiki = {
    notebook = "silverbullet";
    # Deliberately tag-only, so the render sees the grammar's unpinned-image warning fire as well
    # as the digest-pinned path further down.
    version = "0.0.0";
    store = "files";
    slot = 42;
    exposure = "nb";
    createNamespace = true;
    state.space.hostPath = "/example/state/wiki";
    # Its authentication is OPT-IN. Without this the module refuses any exposure past `internal`,
    # because the failure is not an outage: it works perfectly, for everybody who finds it.
    credentials.login = { secret = "example-notes-secrets"; key = "wikiLogin"; };
  };

  # The archive, on the other side of the line: everything in it was written by somebody else and
  # fetched on its owner's behalf. Its own namespace, and its own Secret — naming the notes side's
  # Secret here fails eval.
  nixnotes.archives.example-keep = {
    archive = "linkwarden";
    version = "0.0.0";
    # Its archived copies are files and its records are rows, and neither half is usable alone.
    store = "database";
    # A whole reference rather than a version: pinned by digest, which is what the grammar asks for
    # and what the notebook above deliberately does not do.
    image = "registry.example.com/example-org/example-archive:0.0.0@sha256:0000000000000000000000000000000000000000000000000000000000000000";
    slot = 43;
    exposure = "nb";
    createNamespace = true;
    # THE ORIGIN ONLY. The path its session layer insists on is knowledge and lives in the
    # catalogue; the module joins them, so the classic "every credential is correct and nobody can
    # log in" failure is not writable here.
    publicUrl = "https://keep.example.com";
    state.archives.hostPath = "/example/state/keep";
    # The address of a service this repository names as a dependency and does not run. An address
    # is a value, so it arrives here rather than from the catalogue.
    env.MEILI_HOST = "http://example-search.example-links.svc.cluster.local:7700";
    credentials = {
      database = { secret = "example-links-secrets"; key = "databaseUrl"; };
      session = { secret = "example-links-secrets"; key = "sessionSecret"; };
    };
  };

  # The renderer: a description in, a picture out, nothing kept. It has no `state` option at all,
  # it is the only workload here with a `replicas` option, and its `exposure` enum has no `public`
  # in it.
  nixnotes.renderers.example-charts = {
    renderer = "quickchart";
    version = "0.0.0";
    store = "none";
    slot = 44;
    # The only workload in this repository where scaling to zero is right without a caveat.
    scaling = "scale-to-zero";
    createNamespace = true;
  };
}
