set -euo pipefail
evidence="$RUNNER_TEMP/evidence"
support="$GITHUB_WORKSPACE/support/.github/codex"
source="$PWD"
mkdir -p "$evidence/tools" "$RUNNER_TEMP/bin"
export GOBIN="$RUNNER_TEMP/bin"
export PATH="$GOBIN:$PATH"
record() {
  local label="$1"
  shift
  set +e
  "$@" > "$evidence/$label.log" 2> "$evidence/$label-stderr.txt"
  local raw=$?
  set -e
  echo "$raw" > "$evidence/$label-exit.txt"
  echo "$label raw exit=$raw"
}
go version > "$evidence/go-version.txt"
go env > "$evidence/go-env.txt"
go install golang.org/x/tools/cmd/goimports@v0.51.0 > "$evidence/tools/goimports-install.log" 2>&1
go install github.com/urfave/gfmrun/cmd/gfmrun@v1.3.2 > "$evidence/tools/gfmrun-install.log" 2>&1
url='https://github.com/golangci/golangci-lint/releases/download/v2.14.0'
curl -fsSL "$url/golangci-lint-2.14.0-linux-amd64.tar.gz" -o "$RUNNER_TEMP/lint.tar.gz"
curl -fsSL "$url/golangci-lint-2.14.0-checksums.txt" -o "$evidence/tools/lint-checksums.txt"
expected=$(awk '$2 == "golangci-lint-2.14.0-linux-amd64.tar.gz" {print $1}' "$evidence/tools/lint-checksums.txt")
echo "$expected  $RUNNER_TEMP/lint.tar.gz" | sha256sum -c - > "$evidence/tools/lint-download-check.txt"
tar -xzf "$RUNNER_TEMP/lint.tar.gz" -C "$RUNNER_TEMP"
cp "$RUNNER_TEMP/golangci-lint-2.14.0-linux-amd64/golangci-lint" "$GOBIN/"
golangci-lint --version > "$evidence/tools/lint-version.txt"
gfmrun --version > "$evidence/tools/gfmrun-version.txt"
go version -m "$GOBIN/goimports" > "$evidence/tools/goimports-version.txt"
go version -m "$GOBIN/gfmrun" > "$evidence/tools/gfmrun-module-version.txt"
git worktree add --detach "$RUNNER_TEMP/baseline" 2f64589904992914a49b1c1869eba269e580bc5d
for label in baseline fixed; do
  if [ "$label" = baseline ]; then
    cd "$RUNNER_TEMP/baseline"
  else
    cd "$source"
  fi
  python "$support/manifest.py" "$evidence/$label-source-before.json"
  mkdir -p .local/bin
  cp "$GOBIN/goimports" .local/bin/goimports
  record "$label-ensure-goimports" make ensure-goimports
  record "$label-make-lint" make lint
  record "$label-golangci-lint" golangci-lint run --timeout=10m
  record "$label-golangci-format" golangci-lint fmt --diff
  record "$label-make-all" make all
  record "$label-no-template" make test 'GFLAGS=--tags urfave_cli_no_template'
  record "$label-v3diff" make v3diff
  record "$label-diffcheck" make diffcheck
  git diff > "$evidence/$label-generated.diff"
  python "$support/manifest.py" "$evidence/$label-source-after.json" "$evidence/$label-source-before.json"
done
EVIDENCE="$evidence" python - <<'PY'
import json, os, pathlib
p = pathlib.Path(os.environ['EVIDENCE'])
results = {f.name[:-9]: int(f.read_text()) for f in p.glob('*-exit.txt')}
(p / 'quality-summary.json').write_text(json.dumps(results, indent=2))
print(json.dumps(results, indent=2))
assert all(v == 0 for v in results.values()), results
assert all(not (p / (label + '-golangci-format.log')).read_text().strip() for label in ['baseline', 'fixed']), 'nonempty formatter diff'
PY
