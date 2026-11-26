---
name: pre-submit
description: Run the checks CI runs on a series of shirudo commits before handing it over, and the proofs CI runs only once a series is on main. Covers each commit built on its own, checkpatch, sign-offs, Coccinelle, sparse, SPDX and the documentation check, both compilers, the sanitizer and fuzz runs, the proofs that read the code the series changed, and the VM families the change reaches. Use before saying a change is ready, after rebasing or reordering a series, and to reproduce a CI failure.
---

# Pre-submit checks

CI runs these on every pull request (`.github/workflows/`, with the
scripts in `.github/scripts/`). Run them on the series before handing it
over, and again on the commits a fixup or rebase rewrote. The
`testing` skill covers running the tests and reading their results.

## Where to run

- `build-commits.sh` checks out each commit in the checkout it runs in
  and goes back to the branch afterwards. Run it, the Coccinelle loop
  below and a build with another compiler in a `git worktree`, never in
  the checkout being edited or one a VM bundle builds from.
- A worktree has no `artifacts/`, so its build reads the host's kernel
  BTF: set `BPF_VMLINUX_BTF=<checkout>/artifacts/bpf-next-kernel-debs/vmlinux.btf`
  when the host kernel lacks the signed-loader ABI.
- Objects of another `CC` or `SANITIZE` stay behind and break the link:
  `make clean` or `make -B` when switching.
- Every compiler check takes clang 23. CI's
  `.github/scripts/install-clang.sh` makes `/usr/bin/clang` that one;
  where the host's is older, pass `CC=clang-23` and build
  `shirudo-build` with `SHIRUDO_CLANG_PATH=/usr/bin/clang-23`.

## Each commit of the series

```sh
range=origin/main..HEAD
.github/scripts/build-commits.sh $range
.github/scripts/check-style.sh $range
.github/scripts/check-dco.sh $range
for c in $(git rev-list --reverse $range); do
	git checkout -q --detach "$c" &&
	.github/scripts/check-coccinelle.sh || break
done
```

`check-style.sh` runs the kernel's checkpatch.pl in strict mode over the
C each commit touches and over its message, with the userspace
exceptions the script lists, and refuses the netdev block-comment
opener. `check-dco.sh` wants a one-line subject, a body beyond the tags
and the author's sign-off from a real address; a noreply address or a
`[bot]` is refused as author, signer or co-developer. An agent never
adds a sign-off, so it fails until the person who submits the series
signs off.

## The head of the series

```sh
.github/scripts/check-sparse.sh
.github/scripts/check-spdx.sh
.github/scripts/check-unused.sh
scan-build-23 --status-bugs --exclude vendor make ANALYZE=1  # from a clean tree
make -C Documentation check         # DOCS_CONTAINER=0 without podman or docker
make -B && make -B shirudo-build && make -B quote-check &&
	make -B -f Makefile.shirudo test-helpers
make -B CC=clang && make -B CC=clang shirudo-build &&
	make -B CC=clang quote-check &&
	make -B -f Makefile.shirudo CC=clang test-helpers
make tests VM=0 BACKEND=0 SANITIZE=address,undefined # CC=gcc and CC=clang,
                                                     # one worktree each
make tests VM=0 BACKEND=0 SANITIZE=thread CC=clang   # and TSan in a third
sh .github/scripts/msan-deps.sh &&                   # MSan, a worktree of
	sh .github/scripts/msan-tests.sh 60          # its own
make -C testing fuzz FUZZ_SECONDS=60
make proofs-cbmc CHANGED=$range                      # the proofs that read
make proofs-lean4                                    # what the series changed
make -C testing functional/<family>                  # each family it touches
make -C testing backend                              # after a change to
                                                     # tools/backend
make -C tools/xtop tests                             # after one to tools/xtop;
                                                     # not in make tests
```

A warning fails every build. Fix it rather than silence it; `WERROR=0`
is only for a compiler newer than the tree while its new warnings get
fixed. `check-sparse.sh` refuses a little- or big-endian field read or
written without `le32_to_cpu()`, `cpu_to_le32()` or their kin, and
`check-spdx.sh` the wrong license tag for a file's kind,
`check-unused.sh` an extern function whose last caller went, and
scan-build what clang's static analyzer proves on some path: a NULL or
uninitialized value used, a leak, a use after free, a store never read.

CI runs the proofs only after a push to main, in the `Proofs` workflow,
so this run is the only one a series gets before it lands, and the only
one at all of a proof `testing/proofs/cbmc/ci-skip.list` names, which CI
leaves out. `CHANGED` takes what `git diff` takes and runs the CBMC
proofs whose harness reads a file changed there, all of them after a
change to `run.sh` or `proofs.list`. A proof that fails, or that passes
and no longer states what the changed code does, is brought back in
step in the series, with its row in
`Documentation/contribute/testing/proof-coverage.rst`; so is a Lean 4
model that the page links to the changed C by review, which no run
checks: read it against the change. A proof out of step with the code
is a security bug, as the `security-audit` skill has it; the `proofs`
skill says how to fix one.

The clang and TSan legs of the `Sanitizers` workflow and its `afl-fuzz`
job also run only after a push to main, so the clang and TSan runs
above are the only ones a series gets before it lands.

## Fixing a commit of the series

Fold a fix into the commit it belongs to rather than adding one on top:

```sh
git commit --fixup=<commit>
GIT_SEQUENCE_EDITOR=: git rebase -q -i --autosquash <base>
```

Then run the checks again on the commits that changed. A commit message
follows `Documentation/contribute/code/contributing.rst`: a subject of
`area: imperative summary` of at most 75 characters, a body that says
why before what, and a `Fixes:` tag with the 12-character hash and the
subject as `git log -1 --format=%s` prints it.
