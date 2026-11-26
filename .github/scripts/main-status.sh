#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Authors of shirudo
#
# .github/scripts/main-status.sh -- keep an issue open, labelled ci-main,
# while a workflow fails on main: open it, or add the run to it, when the
# workflow's newest finished push run on main failed, and close it when
# that run passed.
#
#   .github/scripts/main-status.sh
#
# The workflow is WORKFLOW_ID and WORKFLOW_NAME, the repository
# GITHUB_REPOSITORY, and gh reads the token from GH_TOKEN.

set -eu

repo=repos/$GITHUB_REPOSITORY
label=ci-main
TITLE="main: $WORKFLOW_NAME fails"
export TITLE

# Runs finish out of order: judge main by the newest run that finished,
# leaving out the cancelled and skipped ones, which say nothing about it.
newest_run() {
	gh api "$repo/actions/workflows/$WORKFLOW_ID/runs?branch=main&event=push&status=completed&per_page=20" \
		--jq '[.workflow_runs[] | select(.conclusion != "cancelled" and .conclusion != "skipped")][0]
		      | select(. != null) | [.id, .conclusion, .head_sha, .html_url] | @tsv'
}

open_issue() {
	gh api "$repo/issues?state=open&labels=$label&per_page=100" \
		--jq '[.[] | select(.title == env.TITLE and .pull_request == null)][0].number // empty'
}

failed_jobs() {
	gh api "$repo/actions/runs/$1/jobs?filter=latest&per_page=100" \
		--jq '[.jobs[] | select(.conclusion == "failure" or .conclusion == "timed_out") | .name] | join(", ")'
}

# Two runs of this script can judge main by the same run.
reported() {
	gh api "$repo/issues/$1" --jq .body | grep -qF "$2" ||
		gh api --paginate "$repo/issues/$1/comments" --jq '.[].body' | grep -qF "$2"
}

# Another workflow's run can create the label first.
ensure_label() {
	gh api "$repo/labels/$label" --silent 2>/dev/null ||
		gh api -X POST "$repo/labels" -f name="$label" -f color=d73a4a \
			-f description='A workflow fails on main' --silent ||
		gh api "$repo/labels/$label" --silent
}

report_failure() {
	jobs=$(failed_jobs "$id")
	if [ -n "$jobs" ]; then
		jobs="

Failed jobs: $jobs"
	fi
	if [ -z "$issue" ]; then
		ensure_label
		gh api -X POST "$repo/issues" -f title="$TITLE" -f "labels[]=$label" \
			-f body="\`$WORKFLOW_NAME\` fails on main at $sha: $url$jobs

A later failure on main adds a comment here, and the next pass closes this issue." \
			--silent
		echo "::notice::opened an issue: $TITLE"
	elif ! reported "$issue" "$url"; then
		gh api -X POST "$repo/issues/$issue/comments" \
			-f body="Still failing at $sha: $url$jobs" --silent
		echo "::notice::added the run to issue #$issue"
	fi
}

report_pass() {
	[ -n "$issue" ] || return 0
	gh api -X POST "$repo/issues/$issue/comments" \
		-f body="Passes again at $sha: $url" --silent
	gh api -X PATCH "$repo/issues/$issue" -f state=closed \
		-f state_reason=completed --silent
	echo "::notice::closed issue #$issue"
}

run=$(newest_run)
[ -n "$run" ] || exit 0
tab=$(printf '\t')
IFS=$tab read -r id conclusion sha url <<EOF
$run
EOF
issue=$(open_issue)

case "$conclusion" in
failure | timed_out | startup_failure) report_failure ;;
success) report_pass ;;
esac
