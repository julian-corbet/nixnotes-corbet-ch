# Asserts what this surface actually RENDERS, by reading the manifests out of the rendered
# environment with a YAML parser.
#
# Why not just evaluate: a module that type-checks can still mount a corpus somewhere the software
# does not write, put a rolling update in front of a single writer, or leak a Secret name across
# the line between what you wrote and what you fetched. None of that is an eval error. The first is
# an empty notebook that reports itself healthy; the second is two processes on one directory; the
# third is the whole reason the sides are separate.
#
# TWO OF THE ASSERTIONS IN THIS FILE ARE ABSENCES, checked on the bytes rather than on the model:
# nothing belonging to one side is rendered into another side's namespace, and no notes-side Secret
# name appears anywhere in a links-side manifest. A claim about a boundary is worth exactly as much
# as the test that reads the output and finds nothing there.
{ pkgs, lib, env }:

pkgs.runCommand "nixnotes-cluster-render"
{
  nativeBuildInputs = [ pkgs.yq-go ];
  manifests = env.environmentPackage;
  # Not manifests, so they cannot be asserted from the tree: the reports that say what each
  # workload keeps, which side it landed on, and which of them reaches out to the network.
  onDisk = lib.concatStringsSep " "
    (lib.mapAttrsToList (n: f: "${n}=${f}") env.config.nixnotes.onDisk);
  opaque = lib.concatStringsSep " " (lib.sort (a: b: a < b) env.config.nixnotes.opaque);
  stateless = lib.concatStringsSep " " (lib.sort (a: b: a < b) env.config.nixnotes.stateless);
  egress = lib.concatStringsSep " " (lib.sort (a: b: a < b) env.config.nixnotes.egress);
  notesSide = lib.concatStringsSep " " env.config.nixnotes.bySide.notes;
  linksSide = lib.concatStringsSep " " env.config.nixnotes.bySide.links;
  chartsSide = lib.concatStringsSep " " env.config.nixnotes.bySide.charts;
} ''
  set -euo pipefail
  fail=0

  check() {
    if [ "$2" = "$3" ]; then
      echo "  ok   $1: $3"
    else
      echo "  FAIL $1: expected '$2', got '$3'"
      fail=1
    fi
  }

  present() {
    if [ -e "$2" ]; then echo "  ok   $1: rendered"; else echo "  FAIL $1: not rendered ($2)"; fail=1; fi
  }

  absent() {
    if [ -e "$2" ]; then echo "  FAIL $1: rendered but should not be ($2)"; fail=1; else echo "  ok   $1: correctly not rendered"; fi
  }

  y() { yq -r "$1" "$2"; }

  NOTES_NS=example-notes
  LINKS_NS=example-links
  CHARTS_NS=example-charts

  JOT_D=$manifests/example-jot/Deployment-example-jot.yaml
  JOT_S=$manifests/example-jot/Service-example-jot.yaml
  WIKI_D=$manifests/example-wiki/Deployment-example-wiki.yaml
  WIKI_S=$manifests/example-wiki/Service-example-wiki.yaml
  WIKI_NS=$manifests/example-wiki/Namespace-example-notes.yaml
  KEEP_D=$manifests/example-keep/Deployment-example-keep.yaml
  KEEP_S=$manifests/example-keep/Service-example-keep.yaml
  KEEP_NS=$manifests/example-keep/Namespace-example-links.yaml
  CHART_D=$manifests/example-charts/Deployment-example-charts.yaml
  CHART_S=$manifests/example-charts/Service-example-charts.yaml
  CHART_NS=$manifests/example-charts/Namespace-example-charts.yaml

  echo "== the whole rendered Deployment of the notebook -- the corpus this repository exists for =="
  cat $WIKI_D

  echo
  echo "== WHAT EACH ONE KEEPS, AND WHERE THE SOFTWARE ACTUALLY WRITES IT =="
  check "the notebook's corpus is a directory of files, mounted where it writes them" "/space" \
    "$(y '.spec.template.spec.containers[0].volumeMounts[] | select(.name == "space") | .mountPath' $WIKI_D)"
  check "and the backing is the consumer's, never this repository's" "/example/state/wiki" \
    "$(y '.spec.template.spec.volumes[] | select(.name == "space") | .hostPath.path' $WIKI_D)"
  check "the corpus must already exist -- an empty directory is a brand new, healthy, EMPTY notebook" \
    "Directory" "$(y '.spec.template.spec.volumes[] | select(.name == "space") | .hostPath.type' $WIKI_D)"
  check "the capture surface's database directory is the catalogue's" "/var/opt/memos" \
    "$(y '.spec.template.spec.containers[0].volumeMounts[] | select(.name == "data") | .mountPath' $JOT_D)"
  check "the archive's own directory is the catalogue's too" "/data/data" \
    "$(y '.spec.template.spec.containers[0].volumeMounts[] | select(.name == "archives") | .mountPath' $KEEP_D)"
  # Correctness environment: the software's own default for this is a RELATIVE path, resolved
  # against a working directory nobody promised. It has to agree with the mount above.
  check "the archive's storage root agrees with where it is mounted" "/data/data" \
    "$(y '.spec.template.spec.containers[0].env[] | select(.name == "STORAGE_FOLDER") | .value' $KEEP_D)"

  echo
  echo "== THE ONE THAT KEEPS NOTHING: no volume, no mount, and the only rolling update here =="
  check "no volumes at all"       "0" "$(y '[.spec.template.spec.volumes // [] | .[]] | length' $CHART_D)"
  check "no volume mounts at all" "0" "$(y '[.spec.template.spec.containers[0].volumeMounts // [] | .[]] | length' $CHART_D)"
  check "nothing to lose, so a rolling update is safe" "RollingUpdate" "$(y '.spec.strategy.type' $CHART_D)"
  # And the contrast, which is the point: everything with a corpus is a single writer, so the old
  # pod must be gone before the new one starts.
  for d in "$WIKI_D" "$JOT_D" "$KEEP_D"; do
    check "$(basename $d): single writer, so Recreate and never a rolling update" "Recreate" \
      "$(y '.spec.strategy.type' $d)"
  done
  check "and the stateless one is not pinned to a node, because it needs no directory" "null" \
    "$(y '.metadata.labels."nixk3s.dev/node-pinned"' $CHART_D)"
  check "while the notebook is, and the objects say so" "true" \
    "$(y '.metadata.labels."nixk3s.dev/node-pinned"' $WIKI_D)"

  echo
  echo "== A SIDE DECIDED EVERY NAMESPACE; NO DECLARATION DID =="
  check "capture surface" "$NOTES_NS"  "$(y '.metadata.namespace' $JOT_D)"
  check "notebook"        "$NOTES_NS"  "$(y '.metadata.namespace' $WIKI_D)"
  check "archive"         "$LINKS_NS"  "$(y '.metadata.namespace' $KEEP_D)"
  check "renderer"        "$CHARTS_NS" "$(y '.metadata.namespace' $CHART_D)"

  echo
  echo "== THE CAPTURE SURFACE'S TWO DIFFERENT FAILURE BUDGETS =="
  check "cold-start readiness probes every five seconds" "5" \
    "$(y '.spec.template.spec.containers[0].readinessProbe.periodSeconds' $JOT_D)"
  check "cold-start readiness permits twenty-four failures" "24" \
    "$(y '.spec.template.spec.containers[0].readinessProbe.failureThreshold' $JOT_D)"
  check "liveness probes less aggressively" "15" \
    "$(y '.spec.template.spec.containers[0].livenessProbe.periodSeconds' $JOT_D)"
  check "liveness restarts after six failures" "6" \
    "$(y '.spec.template.spec.containers[0].livenessProbe.failureThreshold' $JOT_D)"

  echo
  echo "== NOTHING BELONGING TO ONE SIDE IS RENDERED INTO ANOTHER SIDE'S NAMESPACE =="
  for w in example-jot example-wiki; do
    for f in $(find -L $manifests/$w -type f -name '*.yaml' | sort); do
      ns=$(y '.metadata.namespace // ""' $f)
      if [ "$ns" = "$LINKS_NS" ] || [ "$ns" = "$CHARTS_NS" ]; then
        echo "  FAIL a notes-side object landed outside the notes namespace: $f ($ns)"; fail=1
      fi
    done
  done
  for f in $(find -L $manifests/example-keep -type f -name '*.yaml' | sort); do
    ns=$(y '.metadata.namespace // ""' $f)
    if [ "$ns" = "$NOTES_NS" ] || [ "$ns" = "$CHARTS_NS" ]; then
      echo "  FAIL a links-side object landed outside the links namespace: $f ($ns)"; fail=1
    fi
  done
  echo "  ok   every object is in its own side's namespace"

  echo
  echo "== NO NOTES-SIDE SECRET NAME APPEARS IN A LINKS-SIDE MANIFEST, OR THE REVERSE =="
  # The archive fetches pages chosen by whoever pasted a URL and renders them in a browser. This is
  # the grep that says it cannot reach the credential that opens the notebook.
  for f in $(find -L $manifests/example-keep -type f | sort); do
    if grep -q 'example-notes-secrets' "$f"; then
      echo "  FAIL a notes-side Secret is named in a links-side manifest: $f"; fail=1
    fi
  done
  for f in $(find -L $manifests/example-wiki $manifests/example-jot -type f | sort); do
    if grep -q 'example-links-secrets' "$f"; then
      echo "  FAIL a links-side Secret is named in a notes-side manifest: $f"; fail=1
    fi
  done
  echo "  ok   neither side names the other's Secret"

  echo
  echo "== CREDENTIALS ARE REFERENCES, AND NO SECRET OBJECT IS EVER RENDERED =="
  check "the notebook's login is a reference" "example-notes-secrets" \
    "$(y '.spec.template.spec.containers[0].env[] | select(.name == "SB_USER") | .valueFrom.secretKeyRef.name' $WIKI_D)"
  check "and it carries a user AND a password as one value, so the KEY is the pair" "wikiLogin" \
    "$(y '.spec.template.spec.containers[0].env[] | select(.name == "SB_USER") | .valueFrom.secretKeyRef.key' $WIKI_D)"
  check "no credential ever appears as a value" "null" \
    "$(y '.spec.template.spec.containers[0].env[] | select(.name == "SB_USER") | .value' $WIKI_D)"
  check "the archive's connection string is a reference too" "example-links-secrets" \
    "$(y '.spec.template.spec.containers[0].env[] | select(.name == "DATABASE_URL") | .valueFrom.secretKeyRef.name' $KEEP_D)"
  check "an optional credential nobody named is not rendered at all" "0" \
    "$(y '[.spec.template.spec.containers[0].env[] | select(.name == "MEILI_MASTER_KEY")] | length' $KEEP_D)"
  absent "a rendered Secret object anywhere" "$manifests/example-wiki/Secret-example-notes-secrets.yaml"

  echo
  echo "== THE ONE COMPOSED VALUE: an origin the consumer supplied, a path the software insists on =="
  check "the public URL is joined rather than written down" "https://keep.example.com/api/v1/auth" \
    "$(y '.spec.template.spec.containers[0].env[] | select(.name == "NEXTAUTH_URL") | .value' $KEEP_D)"

  echo
  echo "== A PORT IS NOT AN IDENTITY: two of these listen on the same number, in two namespaces =="
  check "the notebook's port" "3000" \
    "$(y '.spec.template.spec.containers[0].ports[] | select(.name == "http") | .containerPort' $WIKI_D)"
  check "the archive's port, the same number, a different Service" "3000" \
    "$(y '.spec.template.spec.containers[0].ports[] | select(.name == "http") | .containerPort' $KEEP_D)"
  check "the capture surface's own" "5230" \
    "$(y '.spec.template.spec.containers[0].ports[] | select(.name == "http") | .containerPort' $JOT_D)"
  check "the renderer's own"        "3400" \
    "$(y '.spec.template.spec.containers[0].ports[] | select(.name == "http") | .containerPort' $CHART_D)"

  echo
  echo "== PROBES ARE THE SOFTWARE'S OWN, INCLUDING WHERE THERE IS NONE TO HAVE =="
  check "the notebook is probed on the one path it does not authenticate" "/.ping" \
    "$(y '.spec.template.spec.containers[0].readinessProbe.httpGet.path' $WIKI_D)"
  check "the capture surface answers this before any account exists" "/healthz" \
    "$(y '.spec.template.spec.containers[0].readinessProbe.httpGet.path' $JOT_D)"
  check "the renderer's cheap endpoint, not the one that renders a chart" "/healthcheck" \
    "$(y '.spec.template.spec.containers[0].readinessProbe.httpGet.path' $CHART_D)"
  # The archive documents no health endpoint, so the honest probe is a TCP connect with a budget
  # sized for a first start that migrates a database before serving anything.
  check "the archive gets a TCP connect, because it documents nothing better" "null" \
    "$(y '.spec.template.spec.containers[0].readinessProbe.httpGet' $KEEP_D)"
  check "and a delay sized for its first start" "30" \
    "$(y '.spec.template.spec.containers[0].readinessProbe.initialDelaySeconds' $KEEP_D)"
  check "no liveness probe is synthesized where the catalogue declares none" "null" \
    "$(y '.spec.template.spec.containers[0].livenessProbe' $WIKI_D)"

  echo
  echo "== SCALING: the wake front owns the count of the one workload that sleeps =="
  check "a scale-to-zero workload renders NO replica count" "null" "$(y '.spec.replicas' $CHART_D)"
  check "and its Application ignores that field, so a sync cannot fight the autoscaler" \
    "/spec/replicas" \
    "$(y '.spec.ignoreDifferences[0].jsonPointers[0]' $manifests/apps/Application-example-charts.yaml)"
  check "an adopted workload uses server-side diff" "ServerSideDiff=true" \
    "$(y '.metadata.annotations."argocd.argoproj.io/compare-options"' $manifests/apps/Application-example-charts.yaml)"
  check "an adopted workload uses server-side apply" "ServerSideApply=true" \
    "$(y '.spec.syncPolicy.syncOptions[0]' $manifests/apps/Application-example-charts.yaml)"
  check "adoption does not leak onto an ordinary workload" "null" \
    "$(y '.metadata.annotations."argocd.argoproj.io/compare-options"' $manifests/apps/Application-example-jot.yaml)"
  check "the corpus workloads keep exactly one" "1" "$(y '.spec.replicas' $WIKI_D)"
  check "the scaling class is on the objects as a label" "scale-to-zero" \
    "$(y '.metadata.labels."nixk3s.dev/scaling"' $CHART_D)"

  echo
  echo "== each namespace is anchored once, and cannot be cascade-deleted =="
  present "the notes namespace"  "$WIKI_NS"
  present "the links namespace"  "$KEEP_NS"
  present "the charts namespace" "$CHART_NS"
  for ns in "$WIKI_NS" "$KEEP_NS" "$CHART_NS"; do
    check "$(basename $ns): Prune=false" "Prune=false" \
      "$(y '.metadata.annotations."argocd.argoproj.io/sync-options"' $ns)"
  done
  absent "a second anchor for the notes namespace" "$manifests/example-jot/Namespace-example-notes.yaml"

  echo
  echo "== NO FLEET ADDRESS REACHES ANY OBJECT: a class is a label, never a number =="
  for svc in "$JOT_S" "$WIKI_S" "$KEEP_S" "$CHART_S"; do
    check "$(basename $svc): type"           "ClusterIP" "$(y '.spec.type' $svc)"
    check "$(basename $svc): no pinned IP"   "null"      "$(y '.spec.clusterIP' $svc)"
    check "$(basename $svc): no LB address"  "null"      "$(y '.spec.loadBalancerIP' $svc)"
    check "$(basename $svc): no externalIPs" "null"      "$(y '.spec.externalIPs' $svc)"
    check "$(basename $svc): no nodePort"    "null"      "$(y '.spec.ports[0].nodePort' $svc)"
  done
  check "the notebook's exposure is a class on a label" "nb" \
    "$(y '.metadata.labels."nixk3s.dev/exposure"' $WIKI_D)"
  check "and the renderer is not reachable from outside at all" "internal" \
    "$(y '.metadata.labels."nixk3s.dev/exposure"' $CHART_D)"

  echo
  echo "== nothing is rendered below the app grammar: no verbatim object anywhere =="
  for app in example-jot example-wiki example-keep example-charts; do
    check "$app: no server-side apply, because nothing here needs adopting" "null" \
      "$(y '.spec.syncPolicy.syncOptions' $manifests/apps/Application-$app.yaml)"
    check "$app project" "example-knowledge" "$(y '.spec.project' $manifests/apps/Application-$app.yaml)"
  done
  # Every file this surface produced is a Deployment, a Service, a Namespace or an Application.
  for f in $(find -L $manifests -type f -name '*.yaml' | sort); do
    kind=$(y '.kind' $f)
    case "$kind" in
      Deployment|Service|Namespace|Application) ;;
      *) echo "  FAIL an object of kind $kind was rendered: $f"; fail=1 ;;
    esac
  done
  echo "  ok   only Deployments, Services, Namespaces and Applications exist"

  echo
  echo "== WHAT THIS SURFACE KEEPS, AS DATA: the three stores partition it =="
  check "readable without the software, and in which format" "example-wiki=markdown" "$onDisk"
  check "only its own software can read these"               "example-jot example-keep" "$opaque"
  check "keeps nothing at all"                               "example-charts" "$stateless"
  check "and exactly one of them reaches out to the network" "example-keep" "$egress"
  check "the notes side"  "example-jot example-wiki" "$notesSide"
  check "the links side"  "example-keep"             "$linksSide"
  check "the charts side" "example-charts"           "$chartsSide"

  if [ "$fail" -ne 0 ]; then
    echo "rendered output does not match this surface's promises" >&2
    exit 1
  fi
  echo "all render assertions hold"
  cp -rL $manifests $out
''
