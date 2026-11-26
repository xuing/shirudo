---
name: testing
description: Run shirudo's tests and its test VM. Covers the unit, ci-checks, functional and end2end tiers, one suite or family of them, the target tests that each boot a QEMU guest with a software TPM, sanitizer and fuzz runs, and booting, reusing or stopping an interactive VM. Use when asked to run, add or debug a test, to boot or use a test VM, or when a task needs shirudo running as a target, which the host cannot do. Takes an optional kernel for the VM, bpf-next by default or a release from 7.4 up.
---

# Testing

`Documentation/contribute/testing/testing.rst` is the reference: the
tiers, the families and how tests are named, and the VM under "Boot an
interactive VM" and "Run a target test by hand".
`Documentation/contribute/testing/test-coverage.rst` lists what each test
covers and changes with every test added or removed.

## Tiers

```sh
make tests                                  # every test, as CI runs them
make -C testing unit|ci-checks|functional|end2end|backend
make -C testing unit/<suite>                # one unit suite
make -C testing functional/<family>         # one family, its VM tests too
make tests VM=0                             # without the target tests
make tests BACKEND=0                        # without the backend's SQL tests
make tests VM=0 BACKEND=0 SANITIZE=address,undefined  # CI: gcc on a PR, clang too on main
make tests VM=0 BACKEND=0 SANITIZE=thread CC=clang    # CI on main: TSan, for threads and handlers
sh .github/scripts/msan-deps.sh             # MSan: instrumented libraries once,
sh .github/scripts/msan-tests.sh [60]       # then unit and fuzz from a clean tree
make -C testing fuzz [FUZZ_SECONDS=60] [FUZZERS=<target>...]
.github/scripts/afl-deps.sh                 # AFL++ for clang 23, into build/afl
PATH=$PWD/build/afl/bin:$PATH make -C testing afl [AFL_SECONDS=600]
make -C testing help
tools/backend/test/run.sh <name>...         # only the SQL tests named
make -C tools/xtop tests                    # xtop: tsc and bun test, needs bun
```

The end2end tier runs t9107, and t9109 to t9112 on the host, against
the keepalive backend of `tools/backend`, which `host.sh` starts for
every run. The tier boots two VMs at once, each with its own
swtpm: node A runs the tests, node B (`make -C testing vm-node-end2end`,
node mode of `vm/run.sh`) takes `role=core` from `config-core` and waits.
Node mode first runs `vm/tpm-builder.sh`, which creates the node's AK
and EK with tpm2-tools, writes their names to `tpm-names` in the VM's
state directory, and stores an EK certificate from a throwaway CA whose
certificate it leaves in `ek-ca.pem` beside them; host.sh verifies node
B against the names and t9109 enrolls it in the backend, t9112 enrolls
the edge node through credential activation against its CA, so node mode
needs tpm2-tools, the swtpm TCTI of tpm2-tss (`libtss2-tcti-swtpm0t64`),
swtpm-tools and openssl on the host. The tier needs the quote checker,
which `make -C testing end2end` builds first. A fresh edge node
(`END2END_NODE=edge`, `role=edge` from `config-edge`) boots once node A
has stopped, and `host.sh` runs t9109,
then t9110, which continues t9109's tree in segments, and t9112, on the
host against it and node B. Then a second fresh pair boots in their
place, as `<name>-2-end2end-edge` and `-b`, the registry restarts empty, and
`host.sh` runs t9111, the backward walk over sealed segments, against
them. On x86-64 a third fresh edge node then boots alone, as
`<name>-3-end2end-edge`, the registry restarts empty again, and `host.sh`
runs t9113 against it: the java-base64 shield published, appended to a
new tree, pulled and blocking `upatches/test/badDecoder.jar` in a JVM,
then deleted and gone. Last, on every architecture, a fourth fresh edge
node boots alone, as `<name>-4-end2end-edge`, the registry restarts
empty once more, and `host.sh` runs t9114 against it: the app-sandbox
upatch built with the sandbox of `testing/fixtures/app-sandbox`,
published, appended to a new tree, pulled and restricting what
`testing/end2end/app_sandbox_probe.py` executes, connects to and
writes, then deleted and gone. Their output is
`build/test-vm/end2end/t9109.log` to `t9114.log`.
A test reaches the nodes with `node_sh b` or `node_sh edge` of
`testing/end2end/node-lib.sh`, and does to them, the registry and the
backend what `testing/end2end/pipeline-lib.sh` offers. Their boot logs
are `build/test-vm/end2end/node-b.log` and `node-edge.log`, with `-2`
for the second pair, their state `build/test-vm/vms/<name>-end2end-b/`
and `-edge/`. Every node
declares the image of `testing/vm/files/end2end.os-release` without a
root hash, so the backend binds them `declared`.

Host tests run as they are. A target test, `t?1??`, runs in a fresh VM
per family, which needs KVM, an unlimited `ulimit -l`, the test kernel
and the bundle, but not root; see
below. The VM always boots the dm-verity runtime and the signed config
from a dracut initrd. The runner caches the initrd by kernel, bundle and
initrd inputs, while each family keeps its own VM and guest state. CI
runs the same suite through `.github/scripts/tests.sh`. A change to
`util/<m>.c` adds or updates its cases in `testing/unit/<m>.c`, and a
parser of input from outside the host gets a target in `testing/fuzz/`.

## Reading results

- The host tiers print TAP. Look for `not ok`, `runtime error:` and
  `ERROR: AddressSanitizer`, and read the reason of every `# SKIP`: a
  skip can hide a failure. t7005 and t7006 skip when `bpm build` fails,
  so a sanitizer abort in `shirudo-build` reads as a skip there, and
  t3004 skips when the arena serializer does not build.
- A family's target tests print only `[test-vm] result: PASS` or
  `FAIL`. Their TAP output is in
  `build/test-vm/vms/<name>/result/guest.log`, the exit status in
  `result/status`. The end-to-end VM's tests run over SSH from the
  host, which appends their output to the same `guest.log`; there
  `result/status` is only the guest's preparation, and `the SSH session
  that ran the target tests failed` is the channel failing, not a test.
- `end2end` runs an operator VM, `end2end-<pid>-operator`, around node
  A and node B. A failure there reads `host.sh failed with status <n>`;
  the `end2end operator:` lines say which step, the package build log
  is its `result/operator-build.log`, and what it published and verified
  is in its `result/end2end/`.
- A fuzz failure leaves its input in `testing/fuzz/crash-<target>-*`.
  Run the target binary on that file to reproduce it. An `abort()` in
  the harness is a property that failed, which can be the harness's own.

## Before a VM goal

- `vm`, `test-vm-bundle` and every family with target tests require a CI
  kernel artifact under `artifacts/bpf-next-kernel-debs/`.
  `testing/vm/kernel-artifact.sh` pins a build run and a SHA-256 for each
  architecture. Dispatch Build kernel packages and Publish test kernel
  on shirudo's main branch for a new pin. Update the run ID and both
  checksums together. CI builds x86-64 and arm64 from `testing/kernel/`
  for a run that changes the kernel inputs. Otherwise it downloads the pinned
  prerelease. Local VM goals use `testing/vm/kernel-artifact.sh fetch`
  when the kernel is missing. It downloads the prerelease ZIP with
  `curl` and verifies its checksum before extraction. Use authenticated
  `gh` with `KERNEL_RUN_ID` for a specific shirudo Actions run. A kernel
  already staged is left alone: remove the directory to get the pinned
  one.
- The bundle builds in the build container (`testing/container/`) from
  a copy of the files git sees in the checkout, tracked and untracked but
  not ignored, so uncommitted changes are tested; edit nothing until the
  copy is made. The first build makes the image, with network access,
  and the static target dependencies, which takes minutes; say so.
- With `BUILD_CONTAINER=0` the bundle builds in the checkout itself: edit
  nothing and run no other build there until it is built. It then
  compiles its BPF fixtures with the clang `shirudo-build` was built
  for, `SHIRUDO_CLANG_PATH`, `/usr/bin/clang` unless set. It must be
  clang 23; an older one stops at a release store with
  `Cannot select: ... AtomicStore`. Make does not rebuild the helper
  when only that variable changes: remove
  `tools/shirudo-build/compile.o` first.
- `end2end` prepares the operator VM's image on first use, with network
  access for clang 23 from apt.llvm.org, and caches it beside the
  runtime image; every run then builds the operator package in that VM,
  which takes minutes. Say so before starting.

## Run unconfined

No VM goal needs root. A terminal installed as a snap, such as
Alacritty, gives everything it starts its `snap.<name>` AppArmor label
(`cat /proc/self/attr/current`), and Ubuntu's `swtpm` profile takes
signals only from unconfined processes and from `swtpm`: Ctrl-C, the
runner's cleanup and `vm-stop` then leave `swtpm` running. Run the goal
as a transient user service, which runs unconfined. It starts with the
environment and limits of the user manager, not the shell's. The
families build the host tier on the host, and so does the bundle with
`BUILD_CONTAINER=0`; pass on the `PATH` and `LD_LIBRARY_PATH` a host
with an older OpenSSL or clang than the tree needs for that. `end2end`
builds nothing on the host and needs neither. Check that `systemctl
--user show -p DefaultLimitMEMLOCK` reads `infinity`, the unlimited
`ulimit -l` a VM goal needs.

```sh
systemd-run --user --pipe --same-dir --wait --collect \
	--setenv=PATH="$PATH" --setenv=LD_LIBRARY_PATH="$LD_LIBRARY_PATH" \
	--setenv=PKG_CONFIG_PATH="$PKG_CONFIG_PATH" \
	--setenv=SHIRUDO_CLANG_PATH="${SHIRUDO_CLANG_PATH:-/usr/bin/clang}" \
	make -C testing <goal>
```

- `make -C testing vm` adds `-p KillMode=process`, so that QEMU and
  `swtpm`, started inside the unit, outlive it. Leave it out for the
  families and `end2end`, whose VM ends with the run: stopping the unit,
  `systemctl --user stop run-u<N>.service` with the name `systemd-run`
  prints, then stops everything the run started.
- Run `vm-stop` and `vm-clean` the same way. `vm-ssh` and `vm-console`
  need the terminal and signal nothing; run them from the shell.
- A leftover `swtpm` dies the same way, by PID:
  `systemd-run --user --wait --collect --quiet kill <pid>...`. A
  `pkill -f <pattern>` also matches the shell whose command line
  carries the pattern, and kills it.

## Kernel

The optional argument is passed as `KERNEL=` to select an already staged
artifact. Leave it out for `bpf-next`, the kernel the test suite runs.
The BPF build reads `artifacts/bpf-next-kernel-debs/vmlinux.btf` in
place of `/sys/kernel/btf/vmlinux` (`Makefile.shirudo`).

## Reuse a running VM

A VM belongs to the checkout that booted it. Its state lives in that
checkout's `build/test-vm/vms/<name>/`, and the guest mounts that
checkout's source. Consider only VMs of the current checkout. Other QEMU
processes on the host, such as little-vm-helper guests, are not shirudo
targets.

A VM named `<name>-operator` or `<name>-end2end` belongs to an
end-to-end run, which stops it when it ends; `vm-ssh` reaches it while
the run lasts, but never reuse, stop or clean it.

A VM under `build/test-vm/vms/<name>/` can be reused when all of these
hold:

1. It runs. `qemu.pid` holds a live PID, and `/proc/<pid>/cmdline`
   names the state directory.
2. It booted the requested kernel. The `-kernel` path in that command
   line lies in the selected staged kernel artifact directory.
3. It runs the current build. The command line names the bundle it
   booted, `shirudo-bundle,path=<bundle>`. The VM is stale when
   `<bundle>/.stamp` is newer than `created-at` (nanoseconds since the
   epoch), or when the tree has changed since the bundle was built, which
   `make -C testing -q KERNEL=<kernel> <bundle>/.stamp` reports with a
   non-zero exit.

```sh
for vm in build/test-vm/vms/*/; do
	vm=${vm%/}
	pid=$(cat "$vm/qemu.pid" 2>/dev/null) || continue
	cmd=$(tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null) || continue
	case $cmd in *"$PWD/$vm"*) ;; *) continue ;; esac
	printf '%s\n' "$vm: $cmd"
done
```

Use a VM that passes all three checks, and name it in every command with
`VM_NAME=<name>`. Ask the user what to do in any other case: when no VM
runs, when one runs a different kernel or a stale build, or when several
pass. Offer to boot a new VM, to stop or replace the old one, or to use it
anyway. Never stop, replace or clean a VM without that answer.

## Commands

Run each as yourself, as above; root is not needed.

```sh
make -C testing vm VM_NAME=<name> [KERNEL=<kernel>]
make -C testing vm-ssh VM_NAME=<name>
make -C testing vm-console VM_NAME=<name>
make -C testing vm-stop VM_NAME=<name>
make -C testing vm-clean VM_NAME=<name>
```

Adding `VM_SSH_COMMAND='<command>'` to `vm-ssh` runs one command in the
guest and returns. In the guest, `shirudo-runtime` is the runtime the
initrd verified, and `shirudo` an alias of it only in the shell `vm-ssh`
opens from a terminal; `shirudo-runtime status` shows an initialized target,
and `. /etc/shirudo-test-vm.env` sets the environment a family run
gives the target tests.
The checkout is mounted read-only at `/workspace/shirudo`. Without
`VM_NAME`, `vm-clean` stops every VM and removes the state and logs of
them all, and leaves the bundles, the cache and the local stack; name
the VM to remove only its state. `make stack-down` removes the local
stack with its data and CA.
