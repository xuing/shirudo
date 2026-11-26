#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Authors of shirudo
#
# t3108 -- status --json reports every loaded upatch however many there
# are: with eighty loaded, more than a fixed-size document holds, the
# report still parses, lists all of them and exits 0.

cd "$(dirname "$0")/../.."
. ./integration-lib.sh
target_guard
command -v python3 >/dev/null 2>&1 || test_skip_all "no python3"

MANY=${SHIRUDO_TEST_FIXTURES_DIR:?target fixture directory is not set}/many
[ -s "$MANY/shirudo-test-many-80.upatch" ] ||
	test_skip_all "missing the many fixtures"
W=$(mktemp -d) || exit 1

cleanup()
{
	for f in "$MANY"/shirudo-test-many-*.unload.upatch; do
		n=$(basename "$f" .unload.upatch)
		[ -e "/run/shirudo/bpffs/upatches/$n" ] || continue
		"$SHIRUDO_BIN" upatch unload "$f" --no-precheck >/dev/null 2>&1 ||
			echo "cleanup: cannot unload $n" >&2
	done
	rm -rf "$W"
}
trap cleanup EXIT HUP INT TERM

test_expect_success 'eighty upatches load' '
	failed=0 &&
	for f in "$MANY"/shirudo-test-many-??.upatch; do
		"$SHIRUDO_BIN" upatch load "$f" --no-precheck >/dev/null 2>&1 ||
			failed=$((failed + 1))
	done &&
	[ "$failed" -eq 0 ]
'

test_expect_success 'status --json lists every loaded upatch' '
	"$SHIRUDO_BIN" status --json >"$W/status.json" &&
	python3 - "$W/status.json" <<"PY"
import json, sys
with open(sys.argv[1], encoding="utf-8") as stream:
    loaded = json.load(stream)["upatches_loaded"]
many = [u for u in loaded if u["name"].startswith("shirudo-test-many-")]
assert len(many) == 80, many
# A tp_btf program, whose skipped runs the kernel counts.
for row in many:
    assert isinstance(row["missed_runs"], int) and row["missed_runs"] >= 0, row
PY
'

test_done
