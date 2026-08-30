#
# The cluster catalogue: what the personal knowledge surface can run. Four groups, because it
# genuinely contains four kinds of thing and flattening them would make the model lie:
#
#   `streams`    a CAPTURE surface. The unit is a short, dated note, the reading order is
#                chronological, and the whole product promise is that writing something down costs
#                seconds. You wrote everything in it.
#   `notebooks`  a corpus of PAGES ON DISK with a runtime over it. The unit is a named page, it is
#                edited and linked rather than appended, and the corpus is a directory of files any
#                other tool can read. You wrote everything in it.
#   `archives`   a copy of somebody ELSE'S page, kept because the original may not last. It is the
#                only group here whose stored bytes arrive from the network.
#   `renderers`  a pure function with a URL: a description goes in, an artefact comes out, nothing
#                is kept. The only group here that stores nothing at all.
#
# ── THE ONE AXIS ALL FOUR SIT ON ───────────────────────────────────────────────────────────────
#
# WHERE THE BYTES CAME FROM, AND WHAT LOSING THEM MEANS. That is the whole organising idea of this
# repository, and every group above is a position on it:
#
#   you wrote it        losing it means it is GONE. Nothing else has a copy, and no fetch will
#                       bring it back. (`streams`, `notebooks`)
#   somebody else wrote
#   it, and you kept it losing it means a re-fetch that MAY FAIL -- and an archive exists precisely
#                       because re-fetching often does fail. (`archives`)
#   nobody wrote it     losing it means nothing. Ask again and get the same picture back.
#                       (`renderers`)
#
# The `side` field below is that position, and ../modules/cluster.nix reads a workload's NAMESPACE
# from it. Three namespaces, because the three positions want three different answers to "what
# happens if this is lost, and what may it talk to":
#
#   the notes side  is irreplaceable and never dials out.
#   the links side  is the one thing here that FETCHES REMOTE CONTENT on its user's behalf. It
#                   dials arbitrary hosts, chosen by whoever pasted the URL, and its store grows at
#                   page weight rather than at typing speed. A namespace is what a network policy
#                   selects on, which is the operational reason this is a separate one rather than
#                   a note in a README.
#   the charts side has nothing to lose and nothing to back up -- and is the one thing here that
#                   RUNS WHAT IT IS SENT.
#
# ── THE PLACEMENT RULE, so the next candidate is decidable rather than argued ───────────────────
#
#   Does the thing hold, or produce, something a person expects to be able to FIND AGAIN LATER --
#   their own writing, a page they decided to keep, or the picture that goes in one?
#     yes -> it belongs here
#     no  -> it belongs to whichever repository owns the thing it actually is
#
# "IT HAS MARKDOWN IN IT" IS NOT THE TEST, and that clause is load-bearing: a static site
# generator, a documentation build and a chat client all read and write Markdown, and if handling
# the format were the test this catalogue would swallow half the application layer. The test is
# whether the thing IS somebody's personal corpus.
#
# A DOWNLOADER IS NOT AN ARCHIVE EITHER, which is the near miss on the other side. A tool that
# fetches a page and writes a file has done the fetching half and none of the keeping half: no
# collection, no index, nothing that answers "what did I save about this six months ago". The
# archive group is defined by the corpus, not by the fetch.
#
# ── ONE PIECE OF SOFTWARE IS NOT ONE VERSION, so no entry below carries one ─────────────────────
#
# For the same reason the sibling catalogues state: a version is a value, supplied by whoever
# declares a workload, and an entry here is a KIND of software rather than a copy of one. Two of
# these four have shipped a whole-runtime rewrite under the same name, which is exactly the case a
# pinned version in a catalogue gets wrong.
#
# ── FIELDS ─────────────────────────────────────────────────────────────────────────────────────
#
# Shared by every group:
#
#   `side`         `notes`, `links` or `charts`. See above. NOT DECLARABLE anywhere: which side a
#                  piece of software belongs on is a property of where its bytes come from, and
#                  ../modules/cluster.nix reads the namespace from it.
#   `store`        WHAT THE CORPUS IS AT REST, and the most useful field in this file:
#                    `files`     the corpus is files a person or another tool can read WITHOUT this
#                                software running. Deleting the engine loses nothing.
#                    `database`  the corpus is rows. The files that may sit beside them are named
#                                by identifiers only the database maps back to anything, so they
#                                are not a second, readable copy -- see the archive entry.
#                    `none`      there is no corpus. Nothing to back up, nothing to restore.
#                  Every declaration RESTATES this and evaluation fails if the two disagree, so a
#                  declaration alone answers "can anything else read this".
#   `format`       the on-disk format when `store = "files"`, and null otherwise. The house rule
#                  this repository exists to serve names one: `markdown`.
#   `corpus`       WHICH state directories hold the corpus itself, by their catalogue names. Empty
#                  for a stateless entry. What is NOT in this list is derived: an index, a thumbnail
#                  cache, a session store -- things whose loss costs a rebuild rather than content.
#   `image`        container image REPOSITORY, with no tag. The tag is the declaration's `version`.
#   `ports`        named container-side ports, `<name> = <number>`. A container port is a property
#                  of the software rather than of any network, which is the one kind of number a
#                  public catalogue may carry.
#   `primaryPort`  which of those the readiness probe watches.
#   `state`        directories this software writes and cannot lose, as `<name> = { mountPath,
#                  readOnly }`. WHERE each lands inside the container is knowledge and lives here;
#                  what BACKS it is a value and comes from the declaration. Every one must be
#                  backed or the declaration is refused.
#   `env`          plain environment the software needs in order to be CORRECT. Never sizing, never
#                  credentials, never an address of anything outside the container.
#   `args`         entrypoint arguments in the same spirit.
#   `readiness`    probe shape and timing, measured rather than guessed. `path = null` is a TCP
#                  connect, which is the honest answer for software that documents no health
#                  endpoint.
#   `liveness`     an independent restart opinion where the software has one, or absent. A cold
#                  start budget and a wedged-process budget are not interchangeable.
#   `credentials`  `<role> = { env, required }`. The role is what the credential IS; which Secret
#                  holds it and under which key is a value.
#   `authentication`
#                    `builtin`   the software has accounts and always asks.
#                    `optional`  it asks ONLY when a credential is supplied. Whoever reaches it
#                                otherwise is the owner of everything in it.
#                    `none`      it authenticates nobody, ever.
#   `authCredential` for `optional`, the credential ROLE that switches authentication on. The
#                  module refuses a workload reachable beyond the cluster without it.
#   `executes`     true when the software runs code its CALLERS supply. Two entries here do, for
#                  completely different reasons, and the pairing with `authentication` is what
#                  decides how much that matters.
#   `fetchesRemoteContent`
#                  true when the software makes requests to hosts its user names, and stores what
#                  comes back. Exactly one entry does. It is the reason the links side is a
#                  separate namespace.
#   `backgroundWork`
#                  true when work continues AFTER the request that started it has been answered.
#                  This is the field that refuses scale-to-zero: a request-driven wake front counts
#                  requests, so it puts the pod back to sleep while the work is still running.
#   `singleWriter` true when a second replica would write the same store with no coordination. Only
#                  a stateless entry is false, and only the group whose entries are all false has a
#                  `replicas` option at all.
#   `publicUrl`    `{ env, path }` for software that must be told the URL a browser reaches it at,
#                  or null. The VALUE is a fleet fact and comes from the declaration; the variable
#                  AND the path suffix are knowledge and live here, so the module can join them and
#                  nobody can get the second half wrong.
#   `dependsOn`    `<kind> = { required }` for services this repository does NOT run and does not
#                  render: a SQL engine, a search index. Naming the dependency is not the same as
#                  operating it -- what runs the database is a different repository's subject.
#   `note`         what the entry is, and every non-obvious thing about running it.
{ ... }:
{
  # ── Streams: a capture surface. Short, dated, yours ──────────────────────────────────────────
  streams = {
    memos = {
      side = "notes";
      store = "database";
      format = null;
      corpus = [ "data" ];

      image = "neosmemo/memos";
      ports.http = 5230;
      primaryPort = "http";

      state.data = { mountPath = "/var/opt/memos"; readOnly = false; };

      env = { };
      args = [ ];

      readiness = {
        path = "/healthz";
        periodSeconds = 5;
        failureThreshold = 24;
      };

      liveness = {
        path = "/healthz";
        periodSeconds = 15;
        failureThreshold = 6;
      };

      credentials = { };
      authentication = "builtin";
      authCredential = null;
      executes = false;
      fetchesRemoteContent = false;
      backgroundWork = false;
      singleWriter = true;
      publicUrl = null;
      dependsOn = { };

      note = ''
        A lightweight note service with a quick-capture bias: one text box, a chronological feed,
        and a note written in the time it takes to open the tab. That speed is the product, and it
        is the reason this is its own group rather than a small notebook -- the unit here is a
        dated note with no filename and no place in a hierarchy, which is a different thing from a
        page.

        ITS CORPUS IS ROWS, AND THAT IS THE ENTRY'S DEFINING FACT. The notes live in a database
        inside the data directory -- embedded by default -- so nothing but this software can read
        them. Copying the directory to another machine gets you the notes back; opening one note in
        an editor is not a thing you can do. That is why it is catalogued as a `database` store and
        why it is NOT a notebook: this repository's notebook group is defined by files on disk.

        IT ALSO SPEAKS EXTERNAL DRIVERS, through its own driver and connection-string variables,
        and pointing it at the database tier is a perfectly reasonable thing for a consumer to do.
        It does not change what the corpus IS -- the notes are rows either way -- so it changes
        nothing in this entry, and the connection string is a credential like any other.

        THERE IS NO ROOT CREDENTIAL TO NAME, and the absence is deliberate rather than missing. The
        first account created through the interface becomes the owner; there is no environment
        variable that establishes or rotates one. Naming a credential role here would suggest a
        password can be changed by editing a declaration, which is exactly the belief that produces
        a service nobody can log into.

        `/healthz` IS A REAL ENDPOINT rather than a guess: the server registers it explicitly and
        its own release smoke test polls it. It answers before any account exists, which is what
        makes it usable as a readiness probe on a first boot.
      '';
    };
  };

  # ── Notebooks: pages on disk, with a runtime over them ───────────────────────────────────────
  #
  # THE GROUP IS DEFINED BY ITS STORE, NOT BY ITS INTERFACE, and that is the encoding of the house
  # rule rather than a coincidence. A notebook here is developer- and AI-facing: its pages are
  # files that other tools -- an editor, a grep, an agent, a backup -- read without asking this
  # software anything. Software whose pages are rows may be an excellent note service and is
  # catalogued as one, in `streams` above; it cannot be a notebook, and the way that rule binds is
  # that ../modules/cluster.nix builds this group's `notebook` enum from THIS TABLE. Declaring a
  # database-store engine as a notebook is not a refused value, it is a value the option does not
  # have. See ../studies/a-notebook-is-defined-by-its-store.md.
  notebooks = {
    silverbullet = {
      side = "notes";
      store = "files";
      format = "markdown";
      corpus = [ "space" ];

      image = "ghcr.io/silverbulletmd/silverbullet";
      ports.http = 3000;
      primaryPort = "http";

      state.space = { mountPath = "/space"; readOnly = false; };

      env = { };
      args = [ ];

      readiness = {
        path = "/.ping";
        initialDelaySeconds = 5;
        periodSeconds = 10;
        timeoutSeconds = 3;
        failureThreshold = 6;
      };

      credentials.login = { env = "SB_USER"; required = false; };
      authentication = "optional";
      authCredential = "login";
      executes = true;
      fetchesRemoteContent = false;
      backgroundWork = false;
      singleWriter = true;
      publicUrl = null;
      dependsOn = { };

      note = ''
        A Markdown notebook that is also a runtime: the space is a plain directory of `.md` files,
        and the software renders, links, queries and executes against them. Both halves matter
        here. The files alone would make it a good wiki; the runtime is what makes a page able to
        list, roll up and act on the other pages.

        THE SPACE IS THE CORPUS AND IT IS ORDINARY FILES. That is the whole reason this entry is in
        this repository at all: every page is readable, greppable, diffable and editable by
        anything else on the machine, including tools that have never heard of this software. An
        index exists and lives inside the space directory rather than in a mount of its own, which
        is why `corpus` names one directory and not two -- deleting the index costs a reindex,
        deleting the space costs the notebook.

        IT RUNS AS THE OWNER OF THE MOUNTED DIRECTORY. The process reads the UID and GID of
        whatever is mounted at the space path and drops to them, which is a genuinely good default
        and a surprising one: a directory owned by root produces a server running as root, and a
        directory that does not exist yet is created by the container runtime with ownership
        nobody chose. Create it deliberately, with the ownership you want the process to have.

        AUTHENTICATION IS OPT-IN, WHICH IS THE TRAP IN THIS ENTRY. With no credential supplied the
        server asks nobody for anything: whoever can reach it can read, edit and -- because this is
        a runtime -- execute inside your notebook. The credential is a single variable carrying
        `user:password` as one string, so the Secret key holds the PAIR rather than a password;
        ../modules/cluster.nix refuses any declaration that is reachable beyond the cluster without
        it.

        `/.ping` IS THE PROBE, and the reason it works is worth writing down: it is one of the few
        paths the software excludes from authentication, so it keeps answering 200 after the
        credential above is supplied. An authenticated probe path would start failing the moment
        somebody secured the notebook, which reads as an outage caused by locking your door.
      '';
    };
  };

  # ── Archives: somebody else's page, kept ─────────────────────────────────────────────────────
  archives = {
    linkwarden = {
      side = "links";
      store = "database";
      format = null;
      corpus = [ "archives" ];

      image = "ghcr.io/linkwarden/linkwarden";
      ports.http = 3000;
      primaryPort = "http";

      state.archives = { mountPath = "/data/data"; readOnly = false; };

      env = {
        # Correctness, not policy. The software's own default for this variable is a RELATIVE
        # path, resolved against whatever the process's working directory happens to be -- which
        # is not a promise the image makes and not a thing a mount can depend on. Stating it
        # absolutely is what makes the mount above and the storage root the same directory.
        STORAGE_FOLDER = "/data/data";
      };
      args = [ ];

      readiness = {
        path = null;
        initialDelaySeconds = 30;
        periodSeconds = 10;
        timeoutSeconds = 5;
        failureThreshold = 30;
      };

      credentials = {
        database = { env = "DATABASE_URL"; required = true; };
        session = { env = "NEXTAUTH_SECRET"; required = true; };
        searchKey = { env = "MEILI_MASTER_KEY"; required = false; };
      };
      authentication = "builtin";
      authCredential = null;
      executes = false;
      fetchesRemoteContent = true;
      backgroundWork = true;
      singleWriter = true;

      publicUrl = {
        env = "NEXTAUTH_URL";
        path = "/api/v1/auth";
      };

      dependsOn = {
        sql = { required = true; };
        search = { required = false; };
      };

      note = ''
        A bookmark manager that ARCHIVES: it keeps the URL, the metadata and a copy of the page --
        a screenshot, a PDF, a readable text extraction, a single-file HTML -- so that what you
        saved survives the site that served it. Saving the address alone is a bookmark, and a
        bookmark is a promise somebody else has to keep.

        IT IS THE ONLY THING IN THIS REPOSITORY THAT FETCHES REMOTE CONTENT, and three consequences
        follow rather than one. It needs EGRESS, to hosts nobody enumerated in advance -- whoever
        pastes a URL chooses the destination, including addresses inside your own network, which is
        the shape of a server-side request forgery whether or not anybody is attacking. Its store
        grows at PAGE WEIGHT rather than at typing speed, so it is the one corpus here whose size
        is not bounded by how much its owner writes. And the fetching is done by a HEADLESS
        BROWSER: its cost is a browser's cost, not a web application's, and it is the component
        that renders content chosen by whoever it is pointed at.

        ITS FILES ARE ON DISK AND IT IS STILL A DATABASE STORE. The archived copies are files, and
        the records that say what each one is -- the URL, the title, the tags, the collection --
        are rows in an engine this repository does not run. Neither half is usable alone: a
        directory of files named after record identifiers is not an archive, and the records
        without the files are an index of things you no longer have. That is why `store` here means
        "can anything else read this" rather than "are there files", and why the pair must be
        backed up together, in one consistent moment.
        See ../studies/an-archive-with-files-on-disk-is-still-opaque.md.

        IT CANNOT SCALE TO ZERO, and that is refused rather than warned about. Archiving happens
        AFTER the request that saved the link is answered: a wake front that counts requests puts
        the pod back to sleep while the browser is still rendering, and the archive never
        completes, silently, for exactly the links you saved in a hurry.
        See ../studies/an-archive-cannot-scale-to-zero.md.

        THE PUBLIC URL IS NOT JUST A HOSTNAME. Its session layer wants a full URL ending in a
        specific path, and a value that is merely the origin produces sign-ins that redirect into
        nothing -- the classic failure where every credential is correct and nobody can log in.
        The path is knowledge and is recorded above; the declaration supplies the origin and the
        module joins them.

        IT DEPENDS ON TWO SERVICES THIS REPOSITORY DOES NOT RUN. A SQL engine, without which
        nothing starts -- that is the database tier's subject, and the connection string is a
        credential rather than an address. And a search index, without which it still runs and
        searches less well, which is why that dependency is optional and its key is not required.

        THE READINESS PROBE IS A TCP CONNECT and the budget is wide. The software documents no
        health endpoint, so the honest probe says the port is open and nothing about whether the
        database answered; the delay and the failure budget are sized for a first start that runs
        database migrations before it serves anything.
      '';
    };
  };

  # ── Renderers: a pure function with a URL ────────────────────────────────────────────────────
  #
  # THE GROUP THAT KEEPS NOTHING, and it is in a repository about things you expect to find again
  # on purpose: it is the far end of the axis in this file's header, and having it here is what
  # makes the other three groups' storage properties visible as choices rather than as background.
  # A renderer has no corpus, no backup, no restore and no single-writer problem -- and it is the
  # only group with a `replicas` option, for exactly that reason.
  renderers = {
    quickchart = {
      side = "charts";
      store = "none";
      format = null;
      corpus = [ ];

      image = "ianw/quickchart";
      ports.http = 3400;
      primaryPort = "http";

      state = { };

      env = { };
      args = [ ];

      readiness = {
        path = "/healthcheck";
        # A caller is already waiting behind the KEDA interceptor during a cold start. The live
        # deployment has repeatedly established this two-minute budget without either inventing an
        # initial delay or widening the one-second request timeout.
        periodSeconds = 5;
        failureThreshold = 24;
      };

      liveness = {
        path = "/healthcheck";
        # Once warm, six misses fifteen seconds apart distinguish a wedged renderer from a large
        # chart without turning cold-start latency into a restart loop.
        periodSeconds = 15;
        failureThreshold = 6;
      };

      credentials = { };
      authentication = "none";
      authCredential = null;
      executes = true;
      fetchesRemoteContent = false;
      backgroundWork = false;
      singleWriter = false;
      publicUrl = null;
      dependsOn = { };

      note = ''
        A chart image API: post a chart description, get a PNG or a PDF back. Also renders QR codes
        and graph descriptions. It holds nothing between two requests -- there is no data
        directory, no volume, no database, and no first-run state -- which makes it the one
        workload here with nothing to lose and nothing to restore.

        WHY IT IS IN THIS REPOSITORY AT ALL, stated plainly rather than justified. The artefact it
        produces is embedded in the pages the notes side holds: a chart in a note is why a person
        runs one of these. Nothing here depends on it and it depends on nothing here, so it is a
        resting place rather than a perfect fit -- and because it renders no state and names no
        namespace of its own, moving it later costs one catalogue group and one namespace option.

        IT AUTHENTICATES NOBODY AND RUNS WHAT IT IS SENT. Chart descriptions may contain
        JavaScript, which is a feature -- axis formatters and label callbacks are functions -- and
        its own documentation is explicit that the server assumes everything it is sent is
        friendly and must not be exposed to untrusted parties. Those two facts together are why
        this group's `exposure` option does not accept `public` at all: the class is not refused by
        a guard, it is not in the enum.
        See ../studies/the-stateless-workload-is-the-dangerous-one.md.

        SCALING TO ZERO IS RIGHT HERE, and it is the only entry in this catalogue where that is
        true without qualification: no state to reload, no work outstanding when a request is
        answered, and an idle chart API is a pod holding a browser toolchain for nothing.

        `/healthcheck` IS CHEAP AND SAYS LITTLE, WHICH IS THE RIGHT TRADE FOR A PROBE. It answers
        200 with a version and touches no rendering path. There is a second, deliberately
        expensive endpoint that renders a random chart, and it is the one that would actually
        prove the renderer works -- which is precisely why it is not the readiness probe: a probe
        that renders an image every ten seconds is a load generator with a health-check-shaped
        name.
      '';
    };
  };
}
