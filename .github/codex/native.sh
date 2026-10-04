set -euo pipefail
evidence="$RUNNER_TEMP/evidence"
support="$GITHUB_WORKSPACE/support/.github/codex"
mkdir -p "$evidence"
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
hashes() {
  if command -v sha256sum >/dev/null; then
    sha256sum "$@"
  else
    shasum -a 256 "$@"
  fi
}
go version > "$evidence/go-version.txt"
go env > "$evidence/go-env.txt"
python --version > "$evidence/python-version.txt"
python "$support/manifest.py" "$evidence/source-before.json"
cp command_parse.go "$RUNNER_TEMP/fixed.go"
git show 2f64589904992914a49b1c1869eba269e580bc5d:command_parse.go > command_parse.go
hashes command_parse.go command_stop_boundary_test.go > "$evidence/original-before.txt"
regression='^TestCommand_StopOnNthArg_(PreservesBoundaryTokens|PersistentFlagsBeforeBoundary|Process)$'
record original-default go test -json -count=1 -run "$regression" .
record original-no-template go test -tags urfave_cli_no_template -json -count=1 -run "$regression" .
hashes -c "$evidence/original-before.txt" > "$evidence/original-after-check.txt"
cp "$RUNNER_TEMP/fixed.go" command_parse.go
record fixed-default go test -json -count=1 -run "$regression" .
record fixed-no-template go test -tags urfave_cli_no_template -json -count=1 -run "$regression" .
record vet make vet
record full-default go test -race -json -count=1 -coverprofile=default.coverprofile -covermode=atomic ./...
record full-no-template go test -race -tags urfave_cli_no_template -json -count=1 -coverprofile=no-template.coverprofile -covermode=atomic ./...
record binary-size make check-binary-size
record diffcheck make diffcheck
python "$support/manifest.py" "$evidence/source-after.json" "$evidence/source-before.json"
git worktree add --detach "$RUNNER_TEMP/baseline" 2f64589904992914a49b1c1869eba269e580bc5d
cd "$RUNNER_TEMP/baseline"
python "$support/manifest.py" "$evidence/baseline-before.json"
record baseline-binary-size make check-binary-size
python "$support/manifest.py" "$evidence/baseline-after.json" "$evidence/baseline-before.json"
python "$support/results.py" "$evidence"
