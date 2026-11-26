#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Authors of shirudo
# shellcheck disable=SC2016,SC2329 # test_expect_success evaluates the body.

cd "$(dirname "$0")/.." || exit 1
# shellcheck source=testing/test-lib.sh
. ./test-lib.sh
command -v jq >/dev/null 2>&1 || test_skip_all "jq is required"

reporter=$(cd .. && pwd)/.github/scripts/main-status.sh
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
export fixture
mkdir "$fixture/bin"

# Each GET answers from a file of the fixture, and each write is recorded.
cat >"$fixture/bin/gh" <<'SH'
#!/bin/sh
set -eu
[ "$1" = api ] || exit 1
shift
method=GET path= filter= fields=
while [ $# -gt 0 ]; do
	case $1 in
	-X) method=$2; shift 2 ;;
	--jq) filter=$2; shift 2 ;;
	-f) fields="$fields $2"; shift 2 ;;
	--paginate | --silent) shift ;;
	*) path=$1; shift ;;
	esac
done
if [ "$method" != GET ]; then
	printf '%s %s%s\n' "$method" "$path" "$fields" >>"$fixture/writes"
	exit 0
fi
case $path in
repos/o/r/actions/workflows/7/runs\?*) file=runs ;;
repos/o/r/actions/runs/*/jobs\?*) file=jobs ;;
repos/o/r/issues\?*) file=issues ;;
repos/o/r/issues/*/comments) file=comments ;;
repos/o/r/issues/*) file=issue ;;
repos/o/r/labels/ci-main) file=label ;;
*) exit 1 ;;
esac
[ -e "$fixture/$file.json" ] || exit 1
if [ -n "$filter" ]; then
	jq -r "$filter" "$fixture/$file.json"
fi
SH
chmod +x "$fixture/bin/gh"

# runs <id>:<conclusion>..., newest first
runs() {
	sep=
	printf '{"workflow_runs":['
	for r; do
		id=${r%%:*}
		printf '%s{"id":%s,"conclusion":"%s","head_sha":"sha%s","html_url":"https://github.com/o/r/actions/runs/%s"}' \
			"$sep" "$id" "${r#*:}" "$id" "$id"
		sep=,
	done
	printf ']}\n'
}

# state <runs> <open issues> <issue body> <comments>
state() {
	rm -f "$fixture"/*.json "$fixture/writes"
	printf '%s\n' "$1" >"$fixture/runs.json"
	printf '%s\n' "$2" >"$fixture/issues.json"
	printf '{"body":"%s"}\n' "$3" >"$fixture/issue.json"
	printf '%s\n' "$4" >"$fixture/comments.json"
	printf '{"jobs":[{"name":"CI functional tests (shard 1)","conclusion":"failure"},{"name":"CI unit tests","conclusion":"success"}]}\n' \
		>"$fixture/jobs.json"
	printf '{"name":"ci-main"}\n' >"$fixture/label.json"
}

report() {
	env PATH="$fixture/bin:$PATH" GITHUB_REPOSITORY=o/r GH_TOKEN=token \
		WORKFLOW_ID=7 WORKFLOW_NAME="CI suite" sh "$reporter" >/dev/null
	touch "$fixture/writes"
}

# The issue a failure of the workflow left open.
ci_suite_issue() {
	printf '[{"number":5,"title":"main: CI suite fails"}]'
}

url=https://github.com/o/r/actions/runs
export url

test_expect_success 'a failure opens an issue with the commit, the run and the failed jobs' '
	state "$(runs 12:failure)" "[]" "" "[]" &&
	rm "$fixture/label.json" &&
	report &&
	grep -Fx "POST repos/o/r/labels name=ci-main color=d73a4a description=A workflow fails on main" "$fixture/writes" &&
	grep -F "POST repos/o/r/issues title=main: CI suite fails labels[]=ci-main body=" "$fixture/writes" &&
	grep -F "fails on main at sha12: $url/12" "$fixture/writes" &&
	grep -F "Failed jobs: CI functional tests (shard 1)" "$fixture/writes" &&
	! grep -F "CI unit tests" "$fixture/writes"
'

test_expect_success 'a label that exists is not created again' '
	state "$(runs 12:failure)" "[]" "" "[]" &&
	report &&
	! grep -F "repos/o/r/labels" "$fixture/writes" &&
	grep -F "POST repos/o/r/issues title=" "$fixture/writes"
'

test_expect_success 'a later failure adds its run to the open issue' '
	state "$(runs 12:failure 11:failure)" "$(ci_suite_issue)" "fails on main at sha11: $url/11" "[]" &&
	report &&
	! grep -F "POST repos/o/r/issues title=" "$fixture/writes" &&
	grep -F "POST repos/o/r/issues/5/comments body=Still failing at sha12: $url/12" "$fixture/writes" &&
	grep -F "Failed jobs: CI functional tests (shard 1)" "$fixture/writes"
'

test_expect_success 'a run the issue already names is not added twice' '
	state "$(runs 12:failure 11:failure)" "$(ci_suite_issue)" "fails on main at sha11: $url/11" \
		"[{\"body\":\"Still failing at sha12: $url/12\"}]" &&
	report &&
	test ! -s "$fixture/writes"
'

test_expect_success 'a pass closes the open issue' '
	state "$(runs 13:success 12:failure)" "$(ci_suite_issue)" "fails on main at sha12: $url/12" "[]" &&
	report &&
	grep -Fx "POST repos/o/r/issues/5/comments body=Passes again at sha13: $url/13" "$fixture/writes" &&
	grep -Fx "PATCH repos/o/r/issues/5 state=closed state_reason=completed" "$fixture/writes"
'

test_expect_success 'a pass with no issue open, or a failure finishing after it, writes nothing' '
	state "$(runs 13:success 12:failure)" "[]" "" "[]" &&
	report &&
	test ! -s "$fixture/writes"
'

test_expect_success 'a cancelled or skipped run leaves main judged by the run before it' '
	state "$(runs 15:cancelled 14:skipped 13:failure)" "[]" "" "[]" &&
	report &&
	grep -F "fails on main at sha13: $url/13" "$fixture/writes"
'

test_expect_success 'the issue of another workflow is left alone' '
	state "$(runs 13:success)" "[{\"number\":6,\"title\":\"main: Lint fails\"}]" "" "[]" &&
	report &&
	test ! -s "$fixture/writes" &&
	state "$(runs 14:failure)" "[{\"number\":6,\"title\":\"main: Lint fails\"}]" "" "[]" &&
	report &&
	grep -F "POST repos/o/r/issues title=main: CI suite fails" "$fixture/writes" &&
	! grep -F "issues/6" "$fixture/writes"
'

test_expect_success 'no finished run writes nothing' '
	state "$(runs 15:cancelled)" "$(ci_suite_issue)" "" "[]" &&
	report &&
	test ! -s "$fixture/writes"
'

test_done
