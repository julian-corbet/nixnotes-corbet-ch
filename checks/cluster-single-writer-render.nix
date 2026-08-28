{ pkgs, claimEnv }:

pkgs.runCommand "nixnotes-cluster-single-writer-render"
{
  nativeBuildInputs = [ pkgs.yq-go ];
  manifests = claimEnv.environmentPackage;
  singleWriter = if claimEnv.config.nixk3s.apps.example-wiki.singleWriter then "true" else "false";
} ''
  set -euo pipefail

  deployment=$manifests/example-wiki/Deployment-example-wiki.yaml

  test "$singleWriter" = true
  test "$(yq -r '.spec.strategy.type' "$deployment")" = Recreate
  test "$(yq -r '.spec.template.spec.volumes[] | select(.name == "space") | .persistentVolumeClaim.claimName' "$deployment")" = example-wiki-space

  mkdir -p "$out"
  cp "$deployment" "$out/"
''
