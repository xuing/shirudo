..
   SPDX-License-Identifier: BSD-2-Clause
   Copyright (c) 2026 Authors of shirudo

:page-type: How-to
:audience: shirudo contributors

Run and write tests
===================

This page shows how to run shirudo's tests, from one unit suite to the
full run CI makes, how to use the test VM that plays the target, and
where a test you add goes. :doc:`/contribute/testing/test-coverage` lists what
the tests cover.

Before you begin
----------------

- A tree that builds, see :doc:`/contribute/code/developer-guide`. ``make -C
  testing`` builds the binaries, the helper and the test helpers it needs
  itself.
- For the unit and operator tests: ``python3``, ``clang``, OpenSSL 3.5
  or newer and the ``openssl`` command. ``veritysetup`` from
  ``cryptsetup-bin`` and ``mkfs.ext4`` from ``e2fsprogs`` for the image
  tests, ``libtpms-dev`` for the TPM simulator helper and ``rpmbuild``
  for the rpm packaging test.
- For the ``ci-checks`` tests: ``git``, ``jq``, ``pkg-config``,
  ``readelf``, ``spatch`` from Coccinelle with ``libpython3-dev``,
  which its Python rules load, and the kernel's
  ``checkpatch.pl``, which ``check-style.sh`` fetches into
  ``build/checkpatch/`` on its first run. A test whose tool is missing
  skips, and so does t0007's check of the operator binaries until they
  are built without a sanitizer. The ``CI suite`` workflow and the
  sanitizer jobs give the tests every tool.
- For the tests that boot a VM: a readable and writable ``/dev/kvm``,
  a locked-memory limit (``ulimit -l``) of ``unlimited``, which the
  shirudo binaries the runner calls require, an x86-64 or arm64 host,
  and podman or Docker, in which the bundle a VM boots builds; with
  ``BUILD_CONTAINER=0`` it builds on the host instead, which then needs
  what ``make target`` needs. On Ubuntu,
  ``.github/scripts/tests.sh setup`` installs ``cloud-image-utils``,
  ``dracut-core``, ``file``, ``isc-dhcp-client``, ``libguestfs-tools``,
  ``qemu-system-x86``, ``qemu-utils``, ``swtpm``, ``swtpm-tools``,
  ``tpm2-tools`` and the swtpm TCTI ``libtss2-tcti-swtpm0t64`` among
  others; ``tpm2-tss`` carries that TCTI on Fedora. :src:`testing/vm/run.sh` names the packages
  it misses with an install command for ``apt-get`` or ``dnf``. The
  bundle carries the TPM simulator helper, so
  :src:`testing/vm/build-bundle.sh` builds no bundle without
  ``libtpms-dev``.
- For the end-to-end tests: Docker on the host, and network access the
  first time, when the runner adds clang 23 from apt.llvm.org and the
  operator's build dependencies, a JDK among them, to the image of the
  operator VM.

The ``CI suite`` workflow runs the x86-64 unit and script checks,
four functional shards, and the end-to-end tests in parallel jobs.
The functional shards run upatch, tamperproof, the BPM families, and
the remaining families. The arm64 host job runs unit, script, and host
functional tests together.

The merge queue tests a pull request again on top of the changes that
land before it, and runs only what such a change most often breaks: the
gcc and clang jobs of ``Build`` with their unit tests, ``Build every
commit``, the documentation, the sign-offs, and the checkpatch, SPDX,
ShellCheck and unused-function jobs of ``Lint``. The ``CI suite``, the
arm64, riscv64 and scan-build jobs, sparse, Coccinelle and the packages
run on the pull request and on every push to ``main``. In the merge queue
their jobs pass without running.

On pull requests and pushes to ``main``, Lint runs the full-tree Coccinelle
and unused-function checks. The CI suite, coverage, and sanitizer jobs still
run the self-tests for both scripts. Local, manually dispatched, and sanitizer
tag runs also scan the full tree as part of ``ci-checks``.

The ``CI suite`` workflow uses the x86-64 CI kernel package.
:src:`testing/vm/kernel-artifact.sh` pins its build run ID and checksums.
When a change touches the kernel build inputs, CI builds packages for
x86-64 and arm64 using the bpf-next commit recorded in
:src:`testing/kernel/bpf-next.commit` and the patches and configuration in
:src:`testing/kernel/`. Both builds must pass and the test VM uses the
x86-64 package from that run. For a manual CI run, set ``kernel_run_id``
to use a ``kernel-packages-x86-64-ci`` artifact from a shirudo Actions run.
Setup extracts the packages, checks BTF for the signed-loader ABI and
every LSM hook a program of ``bpf/`` attaches to, and stages the result
for the test VM.

To update the published pin, dispatch ``Build kernel packages`` on
shirudo's ``main``, then dispatch ``Publish test kernel`` with the
successful build run ID. The workflow publishes ``test-kernel-<run-id>``
with the original x86-64 and arm64 bundle ZIPs and
``kernel-ci-source.tar.zst``. The source archive contains the patched
kernel, the patch series, the CI configuration fragments and the build
script. The bundles contain the generated configurations and build
metadata. Use the release's ``SHA256SUMS`` to update both architecture
checksums and the run ID in :src:`testing/vm/kernel-artifact.sh` together.
Land kernel input changes first. After publishing their bundles, update
the pin in the same change as any shirudo code that requires the new
kernel.

The merge queue starts the runs on ``main``, so GitHub tells no one when
one fails. The ``Main status`` workflow opens an issue labelled
``ci-main`` instead, ``main: <workflow> fails``, with the commit, the run
and the jobs that failed. A later failure on ``main`` adds its run to the
issue, and the workflow's next pass there closes it.

.. raw:: html

   <details>
   <summary>CI dashboard</summary>

Open the `CI dashboard <ci-status.html>`__ to see the last 24 hours of
workflow and check results for ``main``. Select a cell to see its results
and follow the links to GitHub. The dashboard caches results in the browser.
On reload, it fetches recent runs and revisits runs still in progress.
It checks the full window on the first load and on the next load after
an hour. If GitHub rate-limits requests, the dashboard shows cached results
and waits until the displayed retry time before sending more requests.

.. raw:: html

   </details>

Coverage
--------

The ``Coverage`` workflow, :src:`.github/workflows/coverage.yml`, runs after
a push to main, never on a pull request: the ``CI suite`` tests the binaries
as they ship, and no pull request waits on a coverage figure. It builds the
userspace C code with coverage instrumentation, the host's binaries and the
target the test VMs boot, and runs unit tests, four functional shards and
end-to-end tests in parallel. It merges the six tracefiles and sends one
LCOV report to Coveralls. A test failure still allows the report to be
sent if every job produced a tracefile.

Start the workflow by hand on a branch for the figure of a change before it
lands, or make the report on a host with ``lcov``, from a clean checkout:

.. code-block:: console

   $ make tests COVERAGE=1
   $ .github/scripts/coverage.sh

``coverage/shirudo.lcov`` is the report. With ``COVERAGE=1`` the bundle
carries a target built with gcov and the notes of that build, and every
shirudo process in a guest, from ``init`` in the initrd on, writes its
counters under ``/run/shirudo-gcov`` when it exits. A guest packs them
into its result directory before it powers off, a node of the end-to-end
test when ``run.sh --stop`` asks it to, and :src:`testing/vm/run.sh` keeps
them in ``build/test-vm/coverage/``. :src:`.github/scripts/coverage.sh`
reads them in the build container, whose gcov matches the compiler of the
target, and merges them with the host's.

If the tests ran under ``sudo``, pass ``--sudo-container`` to
``coverage.sh`` to reuse root's build image for guest coverage.

The report leaves out test code, vendored code and BPF programs, and counts
nothing for a process that is killed, as the loads that ``t6143`` and
``t6144`` interrupt are, since gcov writes its counters at exit.

Check the quickstart and quick guides
-------------------------------------

The ``Linux quickstart`` workflow runs on manual dispatch. It runs the
console examples from :doc:`/start/quickstart` and the three
:doc:`/start/guides/index` on one interactive x86-64 test VM. It uses the
same kernel pin as the ``CI suite`` workflow. It runs the attestation
tutorial before the other guides change the register. The log gives the
page and line for each command. If a guide fails, CI uploads the QEMU
console.

Run the examples on a disposable Linux host from a fresh checkout after
staging the kernel and preparing the operator environment as the
quickstart describes. To see the commands without running them, add
``--list``:

.. code-block:: console

   $ python3 .github/scripts/check-guides.py

A reStructuredText comment of the form ``.. guide-check: match REGEX``
checks the last command's output in the next console block. Use
``fail REGEX`` for an expected failure, ``capture NAME`` for a hex value
a later command uses as ``<NAME>``, and ``write PATH`` to save the next
code block as a file. The other console commands must succeed.

Manually dispatch the ``macOS quickstart`` workflow to check the Lima
template from :doc:`/start/quickstart-macos` on a GitHub-hosted Apple
silicon runner. It runs ``limactl validate``.

Test tiers
----------

.. list-table::
   :header-rows: 1
   :widths: 14 26 30 30

   * - Tier
     - Directory
     - Runs
     - Command
   * - Unit
     - :src:`testing/unit/`
     - On the build host
     - ``make -C testing unit``
   * - CI checks
     - :src:`testing/ci-checks/`
     - On the build host
     - ``make -C testing ci-checks``
   * - Functional
     - ``testing/functional/<family>/``
     - Operator tests on the build host, target tests in a VM per
       family
     - ``make -C testing functional``
   * - End-to-end
     - :src:`testing/end2end/`
     - In an operator VM and a target VM, with a registry and a
       collector in containers on the host
     - ``make -C testing end2end``
   * - Fuzz
     - :src:`testing/fuzz/`
     - On the build host, under libFuzzer with ASan and UBSan, or with
       MSan, and under AFL++
     - ``make -C testing fuzz``, ``make -C testing afl``
   * - Proofs
     - :src:`testing/proofs/`
     - On the build host, with CBMC and Lean 4, hours of CPU for all
     - ``make proofs``
   * - Backend
     - :src:`tools/backend/test/`
     - On the build host, against a ClickHouse container
     - ``make -C testing backend``

``make tests`` in the checkout root, or ``make -C testing``, runs the
unit, CI check, functional, end-to-end and backend tiers in that order.
``BACKEND=0`` leaves out the backend tier, which needs docker or podman
and reads no C: the sanitizer runs pass it. The fuzz targets and the
proofs run on their own. CI runs the
proofs only after a push to main, in the ``Proofs`` workflow, never on a
pull request: :doc:`proofs` says which to run for a change.

Each functional family with target tests gets a fresh VM. The VM runner
caches the generated dracut initrd in ``build/test-vm/cache/initrd/``
using the kernel, bundle and initrd inputs as the cache key. Every VM
still gets its own copy of the cached initrd and its own guest state.

Test numbers and families
-------------------------

A shell test is named ``t<F><K><NN>-<what>.sh``:

- ``F`` is the numbered family. A family may have multiple named
  directories when tests need separate VM suites.
- ``K`` is ``0`` for an operator test, which runs on the build host
  without root, a kernel or a TPM of its own, and ``1`` for a target
  test, which runs as root in the family's VM against an initialized
  target.
- ``NN`` orders the tests of a family and kind, and is the order they
  run in.

.. list-table::
   :header-rows: 1
   :widths: 6 30 64

   * - F
     - Directory
     - Covers
   * - 0
     - ``ci-checks/``
     - The DCO, SPDX and style checkers, the CI commit range and the
       SBOM generator
   * - 1
     - ``functional/build/``
     - Helper dispatch, the command surface, the static target, rpm
       packaging, the initrd generator and installer, and the test VM
       scripts
   * - 2
     - ``functional/signing/``
     - Keys, signatures, vouching, revocation and the trusted set
   * - 3
     - ``functional/upatch/``
     - The ``.upatch`` container, attach metadata, decoders,
       serializers, signed policy labels, load, unload and ``upatch get``
   * - 4
     - ``functional/tpm/``
     - TPM structures, the measurement register, the eventlog,
       attestation, the initrd binding and the register guard
   * - 5
     - ``functional/image/``, ``functional/image-reboot/``
     - Runtime and config images, settings, keys, activation,
       revocation and interruption; ``image-reboot`` boots a VM of its
       own twice, for what only the next boot does with a config
   * - 6
     - ``functional/tamperproof/``, ``functional/labels/``
     - Attacks on the admission and BPF command policy, bpffs, the
       seal, task authority, task and socket policy inheritance, the
       keyrings and the TPM path
   * - 7
     - ``functional/bpm/``, ``functional/bpm-segments/``,
       ``functional/bpm-pending/``
     - Package commands, Beefile policy labels, publishing and the
       upatch tree; ``bpm-segments`` boots a VM of its own, whose node
       starts without a tree, for the walk through a tree's segments
       and the keepalive window over them, and ``bpm-pending`` one for
       a pending operation a later segment no longer holds
   * - 8
     - ``functional/otel/``
     - Map export, the status keepalive, OTLP transport and TLS policy
   * - 9
     - ``end2end/``
     - The ``kernel-obs`` package against real kernel activity and the
       whole delivery path

A test you add takes the next free number of its family and kind. A
number is never reused for another test. A file under :src:`testing/` that
is not a test does not take a name of this form. A target test can have
a Python companion with the same stem, such as
``t5101-verity-boot-signers.py``, which only its shell test runs.

``t4003`` and ``t4004`` carry operator numbers but test the register
before ``init``. They skip on the build host and run in a separate VM
that the ``tpm`` family boots without the production initrd.

``t9109`` to ``t9114`` carry target numbers but run on the host:
:src:`testing/end2end/host.sh` runs them after node A's suite, ``t9109``,
``t9110``, ``t9112``, ``t9111``, ``t9113`` and then ``t9114``, against
other nodes (see :ref:`testing-two-nodes`), and node A's runner leaves
them out.

Run the tests
-------------

Run everything, as CI does:

.. code-block:: console

   $ make tests

``make -C testing help`` lists the unit suites and the families. Run
one tier, one unit suite or one family:

.. code-block:: console

   $ make -C testing unit
   $ make -C testing unit/<suite>
   $ make -C testing functional/<family>

``<suite>`` is a file name under :src:`testing/unit/` without ``.c``, such
as ``json``. ``<family>`` is a directory under :src:`testing/functional/`,
such as ``upatch``. A family runs its operator tests in number order,
then boots its VM and runs its target tests there. ``make -j`` boots the
VMs of several families side by side.

Leave out every test that boots a VM, for a host without KVM:

.. code-block:: console

   $ make tests VM=0
   $ make -C testing functional/<family> VM=0

In GCC coverage builds, each unit test child writes its coverage
counters before it exits.

Run the cases of a unit suite whose names contain ``<substring>``:

.. code-block:: console

   $ build/unit/<suite> <substring>

Run one operator test directly. It changes to :src:`testing/` itself and
uses the binaries in the checkout root, so build them first:

.. code-block:: console

   $ make && make shirudo-build && make -C testing test-helpers
   $ sh testing/functional/<family>/<test>.sh

A target test runs only in a VM, with its family or by hand in an
interactive VM, see :ref:`testing-by-hand`.

CI builds with both GCC and Clang using ``-Werror``.
Use ``-B`` when switching ``CC`` to avoid reusing objects:

.. code-block:: console

   $ make -B -C testing unit/<suite> CC=<gcc>
   $ make -B -C testing unit/<suite> CC=<clang>

Read the results
~~~~~~~~~~~~~~~~

Every test prints TAP: ``ok <n> - <title>``, ``not ok <n> - <title>``
and a closing ``1..<n>``. A failing case's standard error follows as
lines that start with ``#``. :src:`testing/run-tests.sh` exits with the
number of test scripts that failed.

A test that cannot run prints ``1..0 # SKIP <reason>``. On the build
host a skip counts as a pass, so look for ``# SKIP`` when an operator
test seems to pass too quickly. A target test that skips as a whole
fails its family with ``required target test was skipped``, since every
target test is required.

Run under the sanitizers
------------------------

1. Remove the objects of an earlier build. The build does not track
   compiler flags, so it would keep objects built without the
   sanitizers:

   .. code-block:: console

      $ make clean

2. Build and run every test that needs no VM under ASan and UBSan:

   .. code-block:: console

      $ make tests VM=0 SANITIZE=address,undefined

``SANITIZE`` instruments the host binaries and the test helpers. The BPF
objects are unaffected. Recovery is off, so every report fails the run.
CI runs the same with gcc and with clang.

``SANITIZE=thread`` runs the same tests under ThreadSanitizer, which
reports data races and, in a signal handler, a call that is not
async-signal-safe or a changed ``errno``. shirudo starts no thread and
installs no signal handler, so it reports nothing today; the ``TSan``
leg of the ``Sanitizers`` workflow runs it with clang so that the first
one added is checked.

These three CI jobs install dependencies with
:src:`.github/scripts/sanitizer-deps.sh` inside a disposable LVH guest.
The script replaces the image's apt sources with the Debian sid snapshot
``20261119T120000Z`` so an incomplete distribution transition cannot
break the install. It disables the snapshot's expiry check and keeps
signature verification. Refresh the snapshot deliberately when updating
the toolchain; the jobs do not receive package updates automatically.

Run under MemorySanitizer
-------------------------

MemorySanitizer reports a read of memory that nothing wrote, which ASan
and UBSan do not. It takes what code it did not instrument writes as
never written, so every library the code reads from must be built with
it too.

1. Build the instrumented zlib, OpenSSL, libelf, libcurl and tpm2-tss
   into ``/tmp/shirudo-msan``. The script keeps a copy in
   ``build/msan-deps`` and copies it back on a later run instead of
   building again:

   .. code-block:: console

      $ sh .github/scripts/msan-deps.sh

2. Remove the objects of an earlier build:

   .. code-block:: console

      $ make clean

3. Build with ``SANITIZE=memory`` and run the unit tests and every fuzz
   target, here for 60 seconds each:

   .. code-block:: console

      $ sh .github/scripts/msan-tests.sh 60

Both need clang 23 with its MemorySanitizer and libFuzzer runtimes.
``SANITIZE=memory`` instruments the vendored libbpf as well. The suite
leaves out the decoder's unit tests and fuzz target: LuaJIT's
interpreter is assembly, which no sanitizer instruments, so the values
it hands back would read as uninitialized. ASan and UBSan cover those.
The ``MSan`` job of the ``Sanitizers`` workflow runs the same, the fuzz
targets for 60 seconds on each push and pull request and for ten
minutes in a run started by hand.

Run the fuzz targets
--------------------

The fuzz targets cover the parsers of input from outside the host. They
need clang with its libFuzzer runtime, ``libclang-rt-23-dev`` on the CI
runner.

1. Build and run every target on its seed corpus for 60 seconds each:

   .. code-block:: console

      $ make -C testing fuzz FUZZ_SECONDS=60

2. Run one target again, for example after a fix:

   .. code-block:: console

      $ sh testing/fuzz/run.sh 60 <target>

   ``<target>`` is the name of ``testing/fuzz/fuzz-<target>.c``, such as
   ``json``.

``FUZZERS`` names the targets ``make -C testing fuzz`` runs, all of them
by default, and ``FUZZ_JOBS`` how many run at a time, one per CPU by
default. The targets are built under the sanitizers ``SANITIZE`` names,
ASan and UBSan without it. A crash fails the run and leaves its input in
``testing/fuzz/crash-<target>-*``.

What a target finds is discarded after the run unless
``FUZZ_CORPUS=<dir>`` names a directory to keep it in. Each target then
starts from ``<dir>/<target>`` as well as its seed corpus and adds what
it finds there, and after a run without a crash the directory is merged
down to the inputs that add coverage, so that it does not grow with
every run. A relative ``<dir>`` is taken from the directory the command
runs in, which ``make -C testing`` changes to ``testing/``:

.. code-block:: console

   $ make -C testing fuzz FUZZ_SECONDS=600 FUZZ_CORPUS=$PWD/build/fuzz-corpus

An input in the kept corpus that crashes a later build fails that run
like any new crash.

The ``libFuzzer`` job of the ``Sanitizers`` workflow runs every target
for 60 seconds on each push to ``main`` and each pull request, and for
ten minutes in a run started by hand from the Actions page. Every run
starts from the corpus the last push to ``main`` or run by hand kept in
the Actions cache, and only those runs save it: a pull request keeps
what it finds to itself. When a run fails, the inputs that crashed are
in its ``fuzz-crashes`` artifact; copy one into ``testing/fuzz/`` and
run its target on it to reproduce the crash:

.. code-block:: console

   $ testing/fuzz/fuzz-<target> testing/fuzz/crash-<target>-<hash>

The same targets run under AFL++, whose mutations and comparison
logging find inputs libFuzzer does not, such as a magic value or a
checksum the parser compares the input with. AFL++ builds each target
twice, with ``afl-clang-fast`` and again logging its comparisons, into
``build/fuzz-afl`` and ``build/fuzz-afl-cmplog``, apart from the
libFuzzer builds. Its compiler passes must be built for clang 23:
:src:`.github/scripts/afl-deps.sh` builds a pinned AFL++ into
``build/afl``, and needs ``llvm-23-dev``.

.. code-block:: console

   $ .github/scripts/afl-deps.sh
   $ PATH=$PWD/build/afl/bin:$PATH make -C testing afl AFL_SECONDS=600 \
         FUZZ_CORPUS=$PWD/build/fuzz-corpus

``AFL_SECONDS`` is the time per target, ten minutes by default, and
``FUZZERS``, ``FUZZ_JOBS`` and ``FUZZ_CORPUS`` work as for
``make -C testing fuzz``. What AFL++ queued goes into the same kept
corpus, which the next libFuzzer run merges down. A crash fails the run
and leaves its input in ``testing/fuzz/crash-afl-<target>-<n>``; the
libFuzzer build of the target reproduces it like any other input.

The ``afl-fuzz`` job of the ``Sanitizers`` workflow runs every target
under AFL++ when the ``libFuzzer`` job does, for as long, and saves its
corpus when that job does. Each starts from the newest corpus either
kept, so that what one finds the other starts from. What crashed is in
the job's ``afl-fuzz-crashes`` artifact.

Use the test VM
---------------

The test VM plays a production target. It boots a test kernel, an
Ubuntu cloud image and a software TPM, and runs ``init`` from a dracut
initrd with the dm-verity runtime image and a signed config image. The
family runs, the end-to-end run and the interactive VM all boot it.

A family's VM runs its target tests itself and powers off. The VM of
``image-reboot`` runs its tests, reboots and runs them again before it
powers off: the reboot keeps the disk and resets the TPM, and a test
reads which boot it is in from ``SHIRUDO_TEST_BOOT``, ``1`` or ``2``, and
keeps what it carries across in ``SHIRUDO_TEST_RESULTS``. The second
boot's output follows the first in ``result/guest.log``. The
end-to-end VM prepares itself the same way and waits while the host runs
its target tests over SSH, then powers off. The operator VM of the
end-to-end test has no TPM and no shirudo kernel arguments; it builds
and installs the operator package and serves the end-to-end run. The
interactive VM stays up until you stop it.

Use a CI kernel artifact
~~~~~~~~~~~~~~~~~~~~~~~~

The kernel CI artifacts contain the kernel image, BTF, configuration and
modules. :src:`testing/vm/kernel-artifact.sh` pins the run the tests use.
A goal of ``make -C testing`` that finds no kernel under
``artifacts/bpf-next-kernel-debs/`` downloads and stages the CI artifact
for the VM architecture. A target VM goal uses its kernel image, and a
build uses its BTF unless ``BPF_VMLINUX_BTF`` or ``BPF_VMLINUX_H`` names
another source. ``fetch`` downloads the architecture's ZIP from the
pinned run's ``test-kernel-<run-id>`` prerelease in
``shirudo-dev/shirudo`` with ``curl``. It checks the pinned SHA-256 before
extracting the ZIP with Python 3.

.. code-block:: console

   $ testing/vm/kernel-artifact.sh fetch

``KERNEL_RUN_ID=<run>`` selects a shirudo Actions run that has the CI
artifact for the architecture and fetches it using authenticated ``gh``. A kernel that is staged is
left as it is, whatever run it came from, and
``artifacts/bpf-next-kernel-debs/kernel-run-id`` names the run of one
that was fetched: remove the directory to get the pinned kernel after
the pin moved. An artifact downloaded by other means is staged with
``testing/vm/kernel-artifact.sh stage <dir>``, which the setup script
of the CI runner calls with ``KERNEL_CI_ARTIFACT_DIR``:

.. code-block:: console

   $ KERNEL_CI_ARTIFACT_DIR=$HOME/Downloads/kernel-packages-x86-64-ci .github/scripts/tests.sh setup

Target VM goals require a kernel artifact; they do not build a kernel
from this checkout.

Build the bundle
~~~~~~~~~~~~~~~~

The bundle is the operator's side of a VM run: shirudo built for the
target, the test helpers, the upatch fixtures signed with keys
generated for the bundle, the dm-verity runtime image and the signed
config images. :src:`testing/vm/build-bundle.sh` builds the bpf-next
bundle into ``build/test-vm/host-bundle-bpf-next-verity/`` and keeps
the signing key outside the checkout, which every guest can read, in
``/tmp/shirudo-test-vm-private-<uid>/operator-keys/keys/``.
``TEST_VM_HOST_PRIVATE_DIR`` names another directory, which must lie
outside the repository. Every target that boots a VM rebuilds the bundle
when one of its inputs changed, or when that directory does not hold the
key the bundle's fixtures are signed with. The end-to-end test builds it
once, before its two VMs: the target must trust the key the operator
signs with. Build it alone with:

.. code-block:: console

   $ make -C testing bundle

The host prepares the VM images and keeps the stamp. The rest, the build
and everything it signs, :src:`testing/vm/build-bundle-payload.sh` does
in the build container: Ubuntu 26.04, the release the VMs run, with its
OpenSSL 3.5, the static archives its ``libcrypto.a`` names, which
:src:`.github/scripts/install-static-libcrypto-deps.sh` installs as it
does in CI, and clang 23, so that it needs nothing of the host's
toolchain and what it puts into a guest links against the guest's
libraries. The image builds from :src:`testing/container/Containerfile` on
first use, with network access, and is tagged ``shirudo-build:<hash>``
by its inputs; :src:`testing/container/run.sh` builds it and runs a
command in it. The container builds from a copy of the files git sees in
the checkout, tracked and untracked but not ignored, so uncommitted
changes are in the bundle and the host's own build is left alone. It
keeps the static target dependencies it builds under
``build/test-vm/cache/target-deps/``, one directory per image and
:src:`Makefile.target-deps`.

``BUILD_CONTAINER=0`` builds the bundle in the checkout with the host's
toolchain, the way the host tier always builds: OpenSSL 3.5 and clang 23,
found through ``PATH`` and ``LD_LIBRARY_PATH`` as
:doc:`/contribute/code/developer-guide` shows. ``CONTAINER`` names another
engine than the first of ``podman`` and ``docker`` on ``PATH``.
The bundle script runs Make builds with one job per available CPU reported
by ``nproc``. The eighty status-many fixture pairs build in parallel batches, with one
worker per available CPU reported by ``nproc``. Each worker builds a load
artifact and its matching unload artifact. The ordinary fixture builders, including
the policy and observability fixtures, and the independent unload artifacts
also build in CPU-sized batches. Payload hashes are read after their builders
finish, and the tree test registry is generated after its unload artifacts.

Boot an interactive VM
~~~~~~~~~~~~~~~~~~~~~~

1. Boot a VM and leave it running:

   .. code-block:: console

      # make -C testing vm VM_NAME=<name>

   ``<name>`` names the VM state directory
   ``build/test-vm/vms/<name>/``. Without ``VM_NAME`` the script picks a
   unique name and prints it. ``KERNEL=7.4`` boots a release kernel
   instead of bpf-next and builds it if needed.

2. Open a shell on it:

   .. code-block:: console

      # make -C testing vm-ssh VM_NAME=<name>

   Without ``VM_NAME``, ``vm-ssh`` connects to the most recently created
   VM. From a terminal, the shell it opens has ``shirudo`` as an alias
   of ``shirudo-runtime``; with ``VM_SSH_COMMAND`` or a script on its
   standard input it sets none, and the command names
   ``shirudo-runtime`` itself.

3. Verify that the guest is an initialized target:

   .. code-block:: console

      target# shirudo-runtime status

4. Attach to the serial console when SSH does not answer. ``Ctrl-]``
   detaches:

   .. code-block:: console

      # make -C testing vm-console VM_NAME=<name>

5. Stop the VM and keep its state, or remove its state and logs:

   .. code-block:: console

      # make -C testing vm-stop VM_NAME=<name>
      # make -C testing vm-clean VM_NAME=<name>

   Without ``VM_NAME``, ``vm-clean`` stops every VM and removes the state
   and logs of them all, ``build/test-vm/vms/`` and
   ``build/test-vm/logs/``. The bundles, the cached kernels and runtime
   image, and the local stack stay; ``make -C testing clean`` removes the
   bundles, and ``make stack-down`` the stack.

.. list-table::
   :header-rows: 1
   :widths: 34 66

   * - Variable
     - Effect
   * - ``TEST_VM_CPUS``, ``TEST_VM_MEMORY``, ``TEST_VM_DISK_SIZE``
     - 4 CPUs, ``4G`` and ``30G`` by default.
   * - ``TEST_VM_SSH_PORT=<port>``
     - The host port for SSH. A free port from 22000 to 22999 by
       default.
   * - ``TEST_VM_QEMU=<path>``
     - Another emulator, such as RHEL's ``/usr/libexec/qemu-kvm``.
   * - ``TEST_VM_TIMEOUT=<seconds>``
     - How long a VM that runs tests may run, 3600 by default. CI sets
       900.
   * - ``TEST_VM_VERBOSE=1``
     - Streams the console of a VM that runs tests to the terminal, and
       what the end-to-end tests print over SSH.

Inside the guest:

.. list-table::
   :header-rows: 1
   :widths: 40 60

   * - Path
     - Contents
   * - ``/usr/local/bin/shirudo-runtime``
     - The command that runs the runtime image's binary, which holds
       task authority. ``/usr/local/bin/shirudo`` is a copy outside the
       image and has none.
   * - ``/workspace/shirudo``
     - The checkout, as an overlay over the read-only host checkout at
       ``/mnt/shirudo-src``. Writes stay in the VM.
   * - ``/mnt/shirudo-bundle``
     - The bundle: signed upatch fixtures in ``fixtures/``, image
       fixtures in ``verity/``.
   * - ``/mnt/shirudo-out``
     - The result share, ``build/test-vm/vms/<name>/result/`` on the
       host.
   * - ``/etc/shirudo-test-vm.env``
     - The environment the target tests run with.

.. _testing-by-hand:

Run a target test by hand
~~~~~~~~~~~~~~~~~~~~~~~~~

1. On the interactive VM, change to the tests:

   .. code-block:: console

      target# cd /workspace/shirudo/testing

2. Set the environment a family run sets:

   .. code-block:: console

      target# . /etc/shirudo-test-vm.env

3. Run one test, or all target tests of a family. The ``image`` tests
   need the result directories that ``run-target-tests.sh`` sets, so
   run that family through the script:

   .. code-block:: console

      target# sh functional/<family>/<test>.sh
      target# ./run-target-tests.sh <family>

The interactive VM differs from a family's VM. It starts the
map-export, keepalive and package timers, and it keeps whatever the
tests you ran in it before loaded or left in sealed state. Run the
family with ``make -C testing functional/<family>`` for the verdict CI
gives.

Read the VM logs
~~~~~~~~~~~~~~~~

Each VM keeps its state under ``build/test-vm/vms/<name>/``. A family
VM is named ``test-<family>-<suffix>``, or ``<name>-<family>`` when you
set ``VM_NAME``.

.. list-table::
   :header-rows: 1
   :widths: 36 64

   * - File
     - Contents
   * - ``console.log``
     - The guest's serial console.
   * - ``qemu.log``
     - QEMU's own output.
   * - ``result/guest.log``
     - What the guest preparation and the tests printed.
   * - ``result/failed-tests``, ``result/failed-suites``
     - The test cases and scripts that failed.

A run that passed keeps its logs and drops its disk images. A run that
failed keeps its disks too, copies its logs to
``build/test-vm/logs/<name>/`` and prints where they are. Its guest
overlay holds an ephemeral signing key, so do not share the state
directory.

.. _local-dev-stack:

Run a local development stack
-----------------------------

From the checkout root, run the following commands in any order:

.. code-block:: console

   $ make oci
   $ make telemetry
   $ make vm

``make oci`` starts a persistent TLS OCI registry on
``127.0.0.1:15444``. ``make telemetry`` starts the OTLP collector on
``https://127.0.0.1:14319`` and ClickHouse on
``http://127.0.0.1:18124``. Both targets are idempotent. They use the same
container helpers as the end-to-end tests, which use separate ports and
storage.

``make stack-up`` is shorthand for ``make oci telemetry``. Start the VM
with ``make vm``.

Each of the three writes ``build/test-vm/stack/env``, and ``make
stack-up`` ends with a ``Shell:`` line that names it. A shell that reads
the file, ``. build/test-vm/stack/env``, has the checkout's ``shirudo``
and ``shirudo-build`` on ``PATH``, the bundle's operator key directory
in ``KEYS``, the stack's CA in ``BPM_OCI_CA_FILE``, the tree the VM
follows in ``TREE`` and the stack's ClickHouse client in
``CLICKHOUSE_CLIENT``, as the commands of :doc:`/start/guides/index`
use them.

``make telemetry`` and ``make stack-up`` first build
``tools/quote-check/shirudo-quote-check``, as ``make quote-check`` does,
and turn that ClickHouse into a keepalive backend with it: they install
the checker as ``tpm_quote_check`` and load the schema of
:src:`tools/backend/`, and the collector runs
:src:`testing/vm/otelcol-stack.yaml`, which writes every log record into
``otel.otel_logs`` as well, where the backend reads the keepalives. The
VM then shows in ``shirudo.node_status``, and
:doc:`/operate/backend/xtop` reads them:

.. code-block:: console

   $ make stack-up
   $ make vm
   $ make xtop

``make xtop`` builds :src:`tools/xtop/` and runs it with
``CLICKHOUSE_URL`` set to the stack's ClickHouse, unless the environment
names another.
Once ``make vm`` has made a bundle, it also gives xtop the bundle's
operator keys, the checkout's ``shirudo`` and tree ingest job, the
stack's CA and its ClickHouse client, so that ``c`` in its shields view
creates a tree in the stack's registry; ``shirudo/local-tree`` is the
one the VMs follow.

Every ``make vm`` acts as the builder of :doc:`/operate/run/attest`:
before the guest first boots, :src:`testing/vm/tpm-builder.sh` creates
its attestation and endorsement keys in the fresh vTPM, and writes
``enroll.json`` in its state directory, naming the node by the VM's name,
which is also its host name, and the ``version_id`` of the bundle's
shirudo, the build the VM boots, in ``shirudo-build`` beside it.
``make vm-enroll`` gathers the ``enroll.json`` of every VM under
``build/test-vm/vms/`` into ``build/test-vm/enroll.json`` and loads it
into the stack's backend with one ``enroll-put``, so that the VMs read
``enrolled``, then allows their builds with
:src:`tools/put-shirudo-build`, so that check 3 does not fail them as
``(not expected)``. It prints the file and each command before it runs
it:

.. code-block:: console

   $ make vm-enroll
   $ cat build/test-vm/enroll.json
   {"source": "test-vm", "nodes": [
    {"ak_name": "000b…", "ek_name": "000b…", "node_id": "interactive-Xa3k9q"},
    {"ak_name": "000b…", "ek_name": "000b…", "node_id": "interactive-pL2m7c"}
   ]}
   $ CLICKHOUSE_CLIENT='docker exec -i shirudo-dev-clickhouse clickhouse-client' tools/backend/jobs/enroll-put build/test-vm/enroll.json
   enroll-put: 000b… (ek_name 000b…, node_id interactive-Xa3k9q): already enrolled
   enroll-put: 000b… (ek_name 000b…, node_id interactive-pL2m7c): enrolled
   enroll-put: loaded bindings: 2
   $ CLICKHOUSE_CLIENT='docker exec -i shirudo-dev-clickhouse clickhouse-client' tools/put-shirudo-build --note 'test-vm build' 6e52d48e…
   put-shirudo-build: 6e52d48e…: allowed

A VM enrolled before, and a build allowed before, are loaded again,
which changes nothing, so run it
after each ``make vm``, before the VM's first keepalive or after. A VM
stopped but not removed with ``make vm-clean`` keeps its state directory
and is enrolled too. ``VM_NAME=<name>`` enrolls that VM alone, from its
own ``enroll.json``.

Each ``make vm`` runs the prepared runtime image, and names it in the
guest's ``/etc/os-release`` as the image ``test-vm``, at a version of the
first 12 hex digits of the SHA-256 of the runtime image key, which it
records in ``image`` in its state directory. ``make vm-sbom`` gives the
stack's backend the SBOM of every image the VMs run, so that xtop's SBOM
view lists what they install and the advisories against it.
:src:`testing/vm/runtime-sbom.sh` reads the dpkg database of the runtime
image with ``guestfish``, without booting it, has ``trivy rootfs`` write
a CycloneDX SBOM of it, and keeps it beside the image, so that every run
stores the same bytes. The target then stores each SBOM with
:doc:`/operate/backend/sbom-put` in ``build/test-vm/stack/sbom/``, loads
the store with :doc:`/operate/backend/sbom-scan`, and refreshes
``node_vulns``, which would otherwise show the findings only at its next
refresh, up to 5 minutes later, printing each command before it runs
it:

.. code-block:: console

   $ make vm-sbom
   $ tools/backend/jobs/sbom-put --store file://build/test-vm/stack/sbom --image-id test-vm --image-version 2db4c1808e8a build/test-vm/cache/runtime/rootfs-….cdx.json
   sbom-put: test-vm/2db4c1808e8a/-: stored, sha256 7596…, components: 692
   $ CLICKHOUSE_CLIENT='docker exec -i shirudo-dev-clickhouse clickhouse-client' tools/backend/jobs/sbom-scan --store file://build/test-vm/stack/sbom
   sbom-scan: test-vm/2db4c1808e8a/-: ok, components: 692, findings: 2680
   sbom-scan: loaded images: 1, findings: 2680
   $ docker exec -i shirudo-dev-clickhouse clickhouse-client --query 'SYSTEM REFRESH VIEW shirudo.node_vulns_mv; SYSTEM WAIT VIEW shirudo.node_vulns_mv'

It needs ``trivy`` and its advisory database on the host, which the scan
never updates: run ``trivy image --download-db-only`` first and whenever
you want newer advisories. Run it again to rescan; an image already
stored is left as it is. ``VM_NAME=<name>`` loads that VM's image alone.

``make shields`` publishes every shield of :src:`upatches/`, the packages
whose Beefile has an ``[upatches.tree]`` entry, to the stack's registry
under ``oci://127.0.0.1:15444/shields``, so that xtop's shields view
lists them as available. It runs :src:`tools/put-shields` with the VM
bundle's operator key and the ``shirudo`` and ``shirudo-build`` of the
checkout, then :doc:`/operate/backend/shields-put`, printing each
command before it runs it:

.. code-block:: console

   $ make shields
   $ tools/put-shields --version 1.0.1 --keys-dir /tmp/shirudo-test-vm-private-1000/operator-keys/keys --catalog build/test-vm/stack/shields.json --new-index oci://127.0.0.1:15444/shields
   put-shields: pushed oci://127.0.0.1:15444/shields/cve-2025-71093-e1000-tbi-detector:1.0.1 sha256:1fdb…
   shirudo bpm tree append oci://127.0.0.1:15444/shields/cve-2025-71093-e1000-tbi-detector:1.0.1 --package-digest sha256:1fdb… oci://<registry>/<tree> --tree-id <tree-id>
   …
   $ CLICKHOUSE_CLIENT='docker exec -i shirudo-dev-clickhouse clickhouse-client' tools/backend/jobs/shields-put build/test-vm/stack/shields.json
   shields-put: oci://127.0.0.1:15444/shields/cve-2025-71093-e1000-tbi-detector:1.0.1 cve-2025-71093-e1000-tbi-detector (CVE-2025-71093)
   …
   shields-put: loaded shields: 3

``SHIELDS`` publishes other shields instead: Beefiles, and directories
in which every ``Beefile`` and ``*.bee`` with an ``[upatches.tree]``
entry is one, relative to the checkout root unless absolute. Each is
built where it is, with the ``vmlinux.h`` beside it:

.. code-block:: console

   $ make shields SHIELDS="upatches/kernel-cve/cve-2026-63984-rpl-detector.bee $HOME/my-shields"

Each run pushes the next version, ``1.0.<n>``, counted in
``build/test-vm/stack/shields-run``, since the index takes a version
once and a new build is new content; the count goes with the registry at
``make stack-down``. The first run starts the namespace's index. It needs
what the other targets make and says which to run when one is missing:
the operator key of a bundle from ``make vm``, the binaries from
``make`` and ``make shirudo-build``, and the stack with its backend
from ``make stack-up``. A stack started before
``shirudo.shield_catalog`` was added lacks that table until ``make
telemetry`` loads the schema again. Appending a shield
to ``shirudo/local-tree`` with the command it prints and that key
delivers it to the VMs.

``make -C testing telemetry`` does not build the checker. Without it,
it starts the telemetry stack alone and says so. A stack started that
way keeps its collector: run ``make stack-down``, which also removes the
stack's data, before ``make telemetry`` to add the backend.

``make vm`` prepares a stable CA even when neither service is running.
After initialization, it activates the signed ``config-local-stack``
image. That image points telemetry at ``https://10.0.2.2:14319`` and the
BPM tree at ``oci://10.0.2.2:15444/shirudo/local-tree``, reference
``stable``. The guest also forwards its own ``127.0.0.1:15444`` to
``10.0.2.2:15444``, with ``systemd-socket-proxyd``: the host publishes at
``127.0.0.1:15444``, a tree operation names its package by the address
it was appended through, and the registry's certificate covers both.
Drop-ins make ``shirudo-bpm-tree-sync.timer`` fire every 10 seconds
there and ``shirudo-keepalive.timer`` 10 seconds after each keepalive,
where a target's wait a minute, so that an operation appended to the
tree reaches the VM, and the VM's record of it the backend, at once. The
backend still refreshes its node history and status every minute. The
existing timers retry exports and tree sync when services
are unavailable; starting the containers later needs no VM reboot.
The registry starts empty. Publish a signed tree at that reference using
the VM bundle's operator key under ``TEST_VM_HOST_PRIVATE_DIR`` to load
upatches. Keepalives can reach the collector before any upatch is loaded.
The VM's node labels include ``role=local``.

The public CA and service data live under ``build/test-vm/stack/``;
collector JSON is ``out/otlp.json`` there. Server private keys live outside
the checkout in a directory under ``/tmp`` named for the checkout's hash.
Normal and sudo invocations use the same trust material. The guest
receives only the public CA. ``make stack-down`` removes the service
containers and network, then ``build/test-vm/stack/`` and the private
keys: the registry's and ClickHouse's data, the collector JSON and the
CA. The next ``make stack-up`` starts empty, with a new CA, which a VM
booted before does not trust: boot the VMs again after it. It does not
stop the VMs; use ``make vm-stop`` for that.

``make -C testing vm`` uses the same defaults. Set ``LOCAL_STACK=0`` to
boot a VM without the local-stack configuration and use the explicit
endpoint settings described above instead.
:doc:`/contribute/code/develop-locally` does that, with a plain HTTP
registry and collector it starts itself, to take one package from its
source to the target.

Run the end-to-end tests
------------------------

``make -C testing end2end`` runs ``t9001`` on the host, then
:src:`testing/end2end/host.sh` runs the test with an operator VM and the
target nodes: node A, which runs the target tests, node B beside it, and
a fresh edge node after node A (see :ref:`testing-two-nodes`). The
registry, the collectors and ClickHouse run in Docker containers pinned
by digest, and the registry and collectors use a throwaway CA. Figure 1
shows the run in order.

.. figure:: /images/contribute-end2end-run.svg
   :alt: Ten phases in order, one lane each for the host, the
         containers, the operator VM, node A, node B, the fresh edge node,
         the second pair and the lone nodes. 1: t9001 on the host, then the containers
         start. 2: the operator VM publishes, the host loads the example
         tree. 3: node A runs its tests while node B boots. 4: the
         operator verifies node A and stops. 5: the edge node boots while
         the host runs check-otlp and checks node B. 6: t9109, t9110 and
         t9112 on the host. 7: the registry starts again empty and the
         second pair boots. 8: t9111 on the host. 9, on x86-64 only: the
         registry starts again empty, a third fresh edge node boots and
         t9113 runs on the host. 10: the registry starts again empty, a
         fourth fresh edge node boots and t9114 runs on the host, then
         teardown.

   Figure 1. The end-to-end run in order, not to scale. Tinted bars run
   tests.

#. ``t9001`` runs on the host. ``host.sh`` then starts the registry, an
   OpenTelemetry Collector and ClickHouse, and the keepalive backend's
   own collector and ClickHouse.
#. The operator VM boots and, once it is ready, runs
   :src:`testing/end2end/operator.sh` over SSH: it builds ``kernel-obs``
   into a package with ``bpm build``, against the headers and
   ``vmlinux.h`` of the package, pushes it with ``bpm push``, appends it
   to a signed upatch tree with ``bpm tree append``, does the same with
   ``e2e-java``, a Java agent it compiles from
   :src:`testing/end2end/java-agent/Agent.java` with ``javac``, and
   picks the nonce the targets attest with. The host publishes the keepalive backend's
   example tree and loads it with the tree ingest job.
#. Node A boots, activates a signed config that points at the tree and
   the collector, and its units pull, verify, load and export. A JVM
   that a user manager of node A starts after the sync picks up
   ``JAVA_TOOL_OPTIONS`` from ``environment.d`` and runs the agent from
   its sealed jar; the runtime image carries a JRE for it. Its
   tests, ``t91??``, run over SSH from the host, which writes what they
   print to ``result/guest.log`` as a family's VM does. Node B boots
   beside it.
#. The host hands node A's TPM evidence to the operator, which verifies
   it with ``attest verify`` and checks that its records name both
   packages and the last tree operation it published. The operator VM then
   stops.
#. The fresh edge node boots in node A's place. Meanwhile the host
   checks that the collector holds the package's records, and checks
   node B.
#. ``t9109``, ``t9110`` and ``t9112`` run on the host against the fresh
   edge node and node B.
#. Both nodes stop, the registry starts again without a volume, and a
   second fresh edge node and node B boot.
#. ``t9111`` runs on the host against the second pair, which then
   stops.
#. On x86-64, the registry starts again without a volume and a third
   fresh edge node boots alone; ``t9113`` runs on the host against it
   (:ref:`testing-shield`).
#. The registry starts again without a volume and a fourth fresh edge
   node boots alone; ``t9114`` runs on the host against it
   (:ref:`testing-sandbox`). Then the nodes and the containers stop.

The operator VM boots from the runtime image with clang 23 and the build
dependencies of the operator package added, which the runner prepares
once and caches beside it. The VM has no TPM, boots without the shirudo
kernel arguments, and is the only VM that sees the signing key. The host
keeps the key it logs in to it with and the VM's disk, which holds the
guest's own key, outside the checkout, in
``/tmp/shirudo-test-vm-private-<uid>/end2end-operator/``: a VM's keys
and disk lie in its state directory, which the target VMs read through
their share of the checkout. The operator VM builds the operator package
from the files git sees in the checkout and installs it. The operator VM
and node A name the registry ``registry.test``, at QEMU's address for
the host, so the tree names it as node A reaches it. The host's own
build and the operator key it keeps still play the operator for the
keepalive backend's example tree and for ``t9109`` to ``t9114``, which
run on the host.

To check the collector, :src:`testing/end2end/check-otlp.py` relies on
the earlier ``kernel-obs`` tests, which export each map snapshot as
local JSON and OTLP from one read. It compares the snapshots with the
collector's JSON output and queries the ClickHouse log and sum metric
tables to check that both collector exports hold the same data. The
comparison uses event times relative to each map's interval start and
ignores the metric export time, which the two decoder calls sample
independently.

The kernel observability scenarios share fixture setup, load reports and
unload operations through ``testing/end2end/kernel-obs-lib.sh``. Their
Python assertions use ``snapshots.py`` to read and validate map snapshots;
``kernel_obs_checks.py`` holds the scenario checks called by the shell
tests.

.. code-block:: console

   $ make -C testing end2end

The host side writes to ``build/test-vm/end2end/``. The VMs are named
``end2end-<pid>-operator`` and ``end2end-<pid>-end2end``, or
``<name>-operator`` and ``<name>-end2end`` with ``VM_NAME=<name>``; the
operator's package build log is in its ``result/operator-build.log`` and
what it published and verified in its ``result/end2end/``. While the run lasts,
``make -C testing vm-ssh VM_NAME=<name>`` opens a shell on either VM.
The guests reach the registry and collector through QEMU's address for
the host. ClickHouse is available to the collector on the test's Docker
network.

``t9107`` runs the backend of :src:`tools/backend/`
(:doc:`/operate/backend/index`), so the tier needs
``tools/quote-check/shirudo-quote-check``, which
``make -C testing end2end`` builds first; ``host.sh``, run without it,
stops before it starts anything. ``host.sh`` starts a ClickHouse of the
backend's own on ``http://127.0.0.1:18125``, with the backend's schema
and ``shirudo-quote-check`` as ``tpm_quote_check``, and a collector with
the backend's configuration on ``https://127.0.0.1:14320``. It publishes
the example tree of :src:`testing/fixtures/keepalive/` signed with the
operator key and loads it with the backend's tree ingest job, which runs
``bpm tree show``. In the guest, ``t9107`` sends the example keepalives
with their recorded quotes through that collector and queries
ClickHouse, both through QEMU's address for the host. After node A,
``host.sh`` runs ``t9109`` to ``t9114`` against the same backend, see
:ref:`testing-pipeline`, :ref:`testing-history`,
:ref:`testing-activation`, :ref:`testing-walk`, :ref:`testing-shield`
and :ref:`testing-sandbox`. ``host.sh`` writes
the example tree's digest to ``build/test-vm/end2end/backend-tree.digest``
when it publishes the tree, and removes it when the backend's tree
ingest job does not load the tree and when ``host.sh`` stops. Without
that file, as in a run of the family without ``host.sh``,
:src:`testing/run-target-tests.sh` leaves
``t9107`` out with ``not run without a keepalive backend`` rather than
failing the family on its skip.

.. _testing-two-nodes:

The nodes
~~~~~~~~~

The tier boots up to five targets, at most two at once, each with its
own software TPM and so its own attestation key. Figure 1 shows when
each runs. Node A is the family's VM, named ``<name>-end2end``, and runs
the target tests in number order. Node B is ``<name>-end2end-b``, the
fresh edge node ``<name>-end2end-edge``, and the second pair
``<name>-2-end2end-edge`` and ``<name>-2-end2end-b``. All but node A boot
with ``make -C testing vm-node-end2end``, ``END2END_NODE=b`` or
``edge``: the runner's node mode prepares a node as it prepares node A,
activates the config image of its role, runs no tests, starts no timers
and leaves it running until ``host.sh`` stops it. Before the guest boots,
node mode acts as the builder of :doc:`/operate/run/attest`:
:src:`testing/vm/tpm-builder.sh` creates the attestation key and the
endorsement key in the node's fresh vTPM state, with the tpm2-tools
commands that page gives, and writes their names to ``tpm-names`` and to
``enroll.json``, the file :doc:`/operate/backend/enroll-put` loads, in the
VM's state directory. As the vTPM's maker, it also writes an
endorsement certificate for the endorsement key to the ECC index of the
TCG profile, ``0x01C0000A``, signed by a CA of its own whose key it
throws away, and leaves the CA's certificate in ``ek-ca.pem`` beside the
names. ``host.sh`` copies both files beside the node's SSH key and
verifies node B's evidence against those names, never against the names
the evidence carries, and checks that node A's key fails. Each takes its role from a signed
config image, as ``t9105`` configures node A:

.. list-table::
   :header-rows: 1
   :widths: 22 26 52

   * - Image
     - Labels
     - Points at
   * - ``config-end2end``
     - ``role=edge``
     - The tree ``shirudo/end2end-tree`` and the test's collector. Node
       A activates it in ``t9105``, and the ``kernel-obs``, ``e2e-java``
       and ``cve-2026-31431-alg-splice-block`` operations select
       ``role=edge``.
   * - ``config-edge``
     - ``role=edge``
     - The tree ``shirudo/pipeline-tree`` on the test's registry and the
       keepalive backend's collector. The fresh edge node activates it
       while it is prepared.
   * - ``config-core``
     - ``role=core``
     - The same as ``config-edge``. Node B activates it while it is
       prepared.

``t9109`` needs a node that has run nothing else. By the time it runs,
node A has loaded ``kernel-obs`` and ``policy-exec-graph``, counted
denied execs, and followed ``shirudo/end2end-tree``, none of which a fleet
node has, and its register and eventlog keep all of it. So the fresh edge
node takes node A's place rather than node A moving to the pipeline
tree. Booting it once node A and the operator VM have stopped keeps two
guests at most.

``t9111`` needs nodes that have followed no tree, and both nodes of
``t9109`` and ``t9110`` hold the eleven operations of
``shirudo/pipeline-tree`` and their upatches by then. So ``host.sh``
stops them and boots a second pair with the same config images, and it
starts the registry again without a volume, so that it holds no tree
and ``shirudo/pipeline-tree`` begins anew. The registry keeps nothing
else that a later step needs, and the second pair needs no config image
of its own. The pair boots once the first has stopped, so two guests
still run at most; their boot costs the tier two more boots.

All nodes declare an image: :src:`testing/vm/files/end2end.os-release`,
``IMAGE_ID=fleet-os`` and ``IMAGE_VERSION=end2end-1``, is added to their
``/etc/os-release``. None binds the image as ``verified``. Their root is
the stock cloud image in a writable overlay, not a dm-verity image, and
their kernel command line names no ``roothash=`` or ``usrhash=``, so
``image_root`` is ``null`` and the keepalive backend binds every node as
``declared``. Giving a node a root hash would mean building its root as a
verity image; the backend's own tests cover ``verified`` and
``root_mismatch`` with rows they insert.

In phase 5 of Figure 1, ``host.sh`` checks node B: its evidence
verifies against the names its builder recorded, it loaded no upatch
while it was prepared, its attestation key differs from node A's and
its labels are ``role=core``. Before phase 6 it checks that the fresh
edge node is labelled ``role=edge``, and that
the keepalive body each node printed while it was prepared, in
``result/keepalive.json`` of its state directory, names the image above
and no root. It checks the labels of the second pair the same way.

A test reaches node B and the fresh edge node as root over SSH through
:src:`testing/end2end/node-lib.sh`, by the names ``b`` and ``edge``,
which name the second pair once it has booted.
``node_wait`` waits for a node to be prepared and fails when it did not
boot; ``node_sh`` runs a command line in its shell, with the test's
standard input and output:

.. code-block:: sh

   . ./end2end/node-lib.sh
   node_wait b || test_skip_all "node B did not boot"
   node_sh b /usr/local/bin/shirudo-runtime status --keepalive >"$W/node-b.json"
   node_sh b cat /var/lib/shirudo/bpm/upatch-tree/state.json
   node_sh b "cat >/etc/shirudo/end2end-ca.pem" <"$E2E/ca.pem"

``host.sh`` records each node's SSH port and key in
``build/test-vm/end2end/node-b/`` and ``node-edge/``, which node A reads
through the read-only checkout; on the host, ``NODES_DIR`` names that
directory and ``NODES_HOST`` is ``127.0.0.1``. The nodes reach the
registry and the collectors through QEMU's address for the host, as node
A does, and have the checkout at ``/workspace/shirudo`` too. A tree at
``127.0.0.1:15443`` names its packages there, so a test that syncs a node
starts ``end2end/tcp_forward.py`` in it, detached from the SSH
session:

.. code-block:: sh

   node_sh b "cd /workspace/shirudo/testing &&
              setsid -f python3 end2end/tcp_forward.py 127.0.0.1:15443 \
                     10.0.2.2:15443 /tmp/forward-ready </dev/null >/dev/null 2>&1"

The other nodes have 2 CPUs and ``TEST_VM_NODE_MEMORY``, ``2G`` by
default; node A and the operator VM keep ``TEST_VM_CPUS`` and
``TEST_VM_MEMORY``. With the defaults the guests take 10 GiB of host
memory at most, while the operator VM, node A and node B run, and the
registry, the two collectors and the two ClickHouse servers come on top. ``host.sh`` prints each node's memory use, and their
boot logs are ``build/test-vm/end2end/node-b.log`` and
``node-edge.log``, and ``node-b-2.log`` and ``node-edge-2.log`` for the
second pair.

.. _testing-pipeline:

The full chain
~~~~~~~~~~~~~~

``t9109`` runs the whole keepalive pipeline on real data, with no
fixture at a seam between two stages. ``host.sh`` runs it on the host as
root, after node A, with ``E2E``, the backend directory, the operator key
and the nodes' directory in its environment; its output is
``build/test-vm/end2end/t9109.log``. It:

#. empties the keepalive backend that ``t9107`` used and loads its
   schema again;
#. builds ``xfs-fix`` 1.0.0 and 1.1.0 from
   :src:`testing/fixtures/pipeline/xfs-fix/`, whose Beefile names
   ``fixes = ["EXAMPLE-0101"]`` and selects ``role=edge``, and appends
   add 1.0.0, delete 1.0.0 and add 1.1.0 to ``shirudo/pipeline-tree``;
#. loads the publication with the backend's tree ingest job;
#. syncs the fresh edge node, which applies all three operations, and
   node B, which passes over all three, with ``shirudo-bpm-tree-sync``,
   and sends two keepalives from each a few seconds apart with
   ``shirudo-keepalive``;
#. writes the SBOM store of the nodes' image, and one image for each
   other state of an SBOM, and runs the backend's sbom-scan job with the
   stub ``trivy`` of the fixtures, which prints one ``openssl`` finding;
#. checks that node B's records carry the attestation key its builder
   recorded, and enrolls that key from the builder's ``enroll.json`` with
   :doc:`/operate/backend/enroll-put`, as an operator does, and checks
   the endorsement key's name it recorded;
#. seeds the kernel advisory of the fixtures, whose range holds every test
   kernel, and the nodes' build, and refreshes ``node_status`` and
   ``node_vulns``.

It then checks the tree, the stored records and their quotes, node B
``enrolled`` and the edge node ``untrusted`` in ``nodes`` and
``node_status``, ``node_status`` with the masks ``VA==`` and ``qA==``, each node's
``state.json``, ``outcomes``, ``tree-eventlog`` and loaded set against
the backend's rows, the state of every SBOM, and the exposure of each
node: the kernel advisory ``shielded`` by ``xfs-fix`` on the edge node and
``shield_excludes_node`` on node B, and the ``openssl`` finding
``exposed_no_shield`` on both. A record replayed through the collector
with one byte of its body changed lands in ``rejected`` as
``body_mismatch`` and changes no row of ``node_status``.

``t9109`` takes nothing from :src:`testing/fixtures/keepalive/`.
:src:`testing/end2end/pipeline_checks.py` recomputes the roots, the mask,
the loaded set and each quote's qualifying data from the formats' own
definitions.

.. _testing-history:

The history over segments
~~~~~~~~~~~~~~~~~~~~~~~~~

``t9110`` checks the backend's history of each node, ``node_ops`` and
``node_sets``, on a tree longer than the keepalive window. The bundle
builds every guest target with a window of 7 operations, a walk of 4 and
a join of 6 (``TREE_LIMIT_CFLAGS``), so a tree of 11 operations is enough.
``host.sh`` runs it after ``t9109``, against the same nodes and backend,
and its output is ``build/test-vm/end2end/t9110.log``. It continues
``t9109``'s tree, whose first segment holds operations 1 to 3, the add of
``xfs-fix`` 1.1.0 at seq 3 with ``fixes`` included, and needs both nodes
at seq 3 of it. It:

#. empties the keepalive backend, loads its schema again and sets
   ``window`` in ``shirudo.settings`` to 7;
#. builds ``hist-pad``, a copy of ``xfs-fix`` that selects every node,
   and appends add and delete of it in turn with ``--segment-ops 2``, as
   operations 4 and 5, 6 and 7, then 8 to 11, which seal four segments;
#. after each step loads the tree with the ingest job and syncs the
   nodes. The edge node sends a keepalive each time, so the backend sees
   it from seq 1. Node B syncs to seq 7, walking back one segment, and
   sends nothing until seq 11, so the backend first sees it with a
   window that starts at seq 4.

It then checks that ``bpm tree show --walk`` and ``tree_pubs`` hold the
five segments with their bases, ``segment-<k>`` tags and
``history_root``, and ``tree_ops`` all 11 operations; that each node's
newest record, its ``status --keepalive`` body and its ``outcomes`` agree
on ``base_seq`` 4, ``base_root`` and the mask; that ``node_ops`` holds
the edge node from seq 1 and node B from a gap row at seq 4, with the
roots of their ``outcomes``; that both nodes are ``healthy``, the edge
node's ``base_root`` verified and node B's log reading ``base unverified
(gap)`` and ``set unverified (gap)``; and that ``node_vulns`` still reads
the kernel advisory ``shielded`` by ``xfs-fix`` at seq 3, below the
window, on the edge node and ``unknown`` on node B, as threat U20 of
:doc:`/security/threat-model` says.

.. _testing-activation:

The enrollment by activation
~~~~~~~~~~~~~~~~~~~~~~~~~~~~

``t9112`` enrolls the edge node the way the first method of
:doc:`/operate/run/attest` does, through credential activation, where
``t9109`` enrolls node B from its builder's records. ``host.sh`` runs it
after ``t9110``, against the same nodes and backend, and its output is
``build/test-vm/end2end/t9112.log``. It:

#. checks that the backend holds the edge node's key ``untrusted``;
#. collects evidence from the edge node with a fresh nonce, and checks
   that it names the attestation key of the node's keepalives and
   carries an ECC endorsement certificate;
#. makes a challenge with ``--ek-ca`` set to node B's ``ek-ca.pem``,
   which refuses with ``FAIL  endorsement certificate: chains to``, and
   then with the edge node's own, which passes and prints the credential;
#. hands the challenge to node B, which refuses it as made for another
   attestation key;
#. has the edge node answer it with a second nonce, and verifies the
   answer with both names and ``--expect-credential``, which passes with
   the credential and fails with another;
#. inserts the key into ``shirudo.nodes`` as ``enrolled``, and checks
   that ``node_status`` then reads the edge node ``enrolled`` and node B,
   whose enrollment of ``t9109`` went with the schema ``t9110`` loaded
   again, still ``untrusted``.

.. _testing-walk:

The backward walk
~~~~~~~~~~~~~~~~~

``t9111`` shows a node's walk back over a sealed segment on real data:
the publisher seals it, a node behind it follows its signed digest back
and applies forwards, and the backend sees one tree. ``host.sh`` runs it
last, after ``t9112``, against the second pair, a fresh edge node and a
fresh node B, and the same backend, and its output is ``build/test-vm/end2end/t9111.log``. The
tree's five operations fit in the walk, join and keepalive window of the
bundle's targets. It:

#. checks that neither node has tree state and that the registry holds
   no tree, empties the keepalive backend, loads its schema again and
   sets ``window`` to 7;
#. builds ``xfs-fix`` 1.0.0 and 1.1.0 and ``net-guard`` from
   :src:`testing/fixtures/pipeline/net-guard/`, which selects no label,
   so that node B applies something;
#. appends, with ``--segment-ops 2`` and the tree id ``segments``, add
   ``xfs-fix`` 1.0.0 for ``role=edge``, which node B alone syncs, then add
   ``net-guard``, delete ``xfs-fix`` 1.0.0 and add ``xfs-fix`` 1.1.0,
   which seal segment 1 at generation 2 as ``segment-1``;
#. syncs the edge node, which has ``last_seq`` 0, and node B, at seq 1,
   one after the other. Each fetches ``stable``, segment 2, then segment
   1 by its digest, and applies forwards to seq 4;
#. loads the tree with the ingest job and sends a keepalive from each
   node;
#. appends delete ``net-guard``, which seals segment 2 as ``segment-2``,
   syncs both nodes, which fetch ``stable`` and the manifest of the
   ``net-guard`` package the delete names, which ``bpm tree append``
   keeps in the tree's repository, but no sealed segment, and sends
   keepalives again.

The registry's access log (``stack_oci_log`` of
:src:`testing/vm/stack-lib.sh`) is how it sees each fetch: the test
writes a mark there before and after each sync, a request for a manifest
that does not exist, and reads the requests for the tree's repository
between them. It checks that each walk fetches segment 1 by its digest
after ``stable`` and never by its ``segment-1`` tag, and that no sync
after seq 5 fetches a sealed segment. It checks that each segment's
``base`` names the manifest its tag names and the ``history_root`` the
test folds from the published digests; that each node's ``outcomes``,
``tree-eventlog`` and ``projection_root`` follow from the published
operations and its role, with the masks ``VQ==`` and ``mg==`` at seq 4
and ``VUA=`` and ``mkA=`` at seq 5, the same ``history_root`` on every
line of both, ``segment_base_seq`` 2 and then 4, the ``tree_op`` events
of its attested eventlog and its loaded upatches; that each keepalive
covers all five operations from ``base_seq`` 0; and that ``tree_pubs``
holds the three segments, ``tree_ops`` the five operations and
``node_ops`` each node from seq 1, with no contradiction marked, and
both nodes are ``healthy`` with ``4 chain: pass``, ``5 head: pass, seq 5
of 5`` and ``6 set: pass``. :src:`testing/end2end/pipeline-lib.sh` holds
what ``t9109`` to ``t9114`` do to the nodes, the registry and
ClickHouse.

.. _testing-shield:

A shield rolled out and taken back
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

``t9113`` follows one shield from its publication to a node and back, as
an operator rolls a fix out for an advisory against a platform and takes
it back once the platform is fixed. The shield is ``java-base64`` of
:src:`upatches/java-base64/`, a Java agent, whose selector names
``x86_64``, so ``host.sh`` runs the test on x86-64 alone: against
a third fresh edge node, which has followed no tree, a registry that
holds none, and the same backend. Its output is
``build/test-vm/end2end/t9113.log``. The host has no JDK to rely on, so
the operator VM builds the agent's jar and ``badDecoder.jar`` of
:src:`upatches/test/` while it publishes, and ``host.sh`` copies both to
``build/test-vm/end2end/shield/``. The test:

#. checks that the node has no tree state and that the registry holds
   neither the tree nor an index of shields, and empties the keepalive
   backend;
#. runs ``badDecoder.jar`` in the node with
   :src:`testing/end2end/guarded-jvm.sh`, which starts the node's user
   manager again and the JVM as a service of it, the way a JVM gets its
   agents from ``environment.d``: the JDK refuses the input itself, exit
   status 1;
#. publishes the shield with :src:`tools/put-shields`, from a copy of
   the package without its ``build.sh``, so that the jar of the operator
   VM is the one signed, loads the catalog with
   :doc:`/operate/backend/shields-put`, and checks its row in
   ``shield_catalog``;
#. creates ``shirudo/pipeline-tree`` with ``bpm tree append`` of the
   shield by the reference and manifest digest ``put-shields`` printed,
   which is what xtop runs to create a tree, and loads it with the
   ingest job;
#. syncs the node, which reaches seq 1 with one ``tree_op`` event,
   installs the package's jar as ``/run/shirudo-java/java-base64.jar``
   and names it in
   ``/run/environment.d/shirudo.conf``, and runs ``badDecoder.jar``
   again: the guard refuses the input, exit status 0;
#. sends a keepalive and checks ``5 head: pass, seq 1 of 1`` and ``6
   set: pass, 1 loaded`` in the node's status;
#. appends the shield again with ``--op delete``, loads the tree, syncs
   the node, which reaches seq 2, replaces the jar with one whose agent
   does nothing and takes it out of ``shirudo.conf``, and runs
   ``badDecoder.jar`` a third time, which the JDK refuses again;
#. sends a keepalive and checks ``seq 2 of 2`` and ``0 loaded``.

It does not check that the node is ``healthy``: a user manager tries
``bpf()`` as it starts, which shirudo refuses and counts, and check 3
fails a node whose tamper counters rose since its first record.

.. _testing-sandbox:

An application sandboxed and released
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

``t9114`` takes the ``app-sandbox`` upatch of :src:`upatches/app-sandbox/`
through the whole pipeline, from its sources to a node that enforces it
and back. ``host.sh`` runs it last, on every architecture, against a
fourth fresh edge node, a registry that holds no tree, and the same
backend. Its output is ``build/test-vm/end2end/t9114.log``. The package
it publishes is the shipped one with ``probe.Beefile`` as its Beefile
and the rules of :src:`testing/fixtures/app-sandbox/`, whose one
sandbox, ``probe``,
labels a file of the test: a copy of the node's ``python3`` at
``/tmp/shirudo-app-sandbox/app``. It may execute the files labeled
``probe-helpers`` beside it, which the Beefile names by the pattern
``helper*``, reach the loopback networks, and not create, rename or
write ``*.php``. That copy runs
:src:`testing/end2end/app_sandbox_probe.py`, which tries 28 operations
and prints which of them the kernel denied. The test:

#. checks that the node has no tree state and that the registry holds
   neither the tree nor an index, and empties the keepalive backend;
#. copies the application, two programs it may execute, ``helper-a``
   and ``helper-b``, and one it may not, ``other``, to the node, with a
   symbolic link ``helper-link`` to the last, and runs the probe:
   nothing is denied;
#. builds the package as it ships and reads the rules of its two
   sandboxes back with ``bpm info data``, and checks that ``bpm build``
   fails for rules that name a sandbox the Beefile has no policy for;
#. publishes the package with :src:`tools/put-shields`, which builds it
   and pushes it to the ``sandboxes`` namespace, and loads the catalog
   with :doc:`/operate/backend/shields-put`;
#. creates ``shirudo/pipeline-tree`` with ``bpm tree append`` of the
   package by the reference and manifest digest ``put-shields`` printed,
   reads it back with ``bpm tree show`` and loads it with the ingest
   job;
#. syncs the node, which reaches seq 1, pins the upatch and labels the
   application with policy bit ``0x1`` and both programs the pattern
   matches with ``0x2``, and not ``other``, though the link to it
   matches too;
#. runs the probe in the application: 17 operations are denied, the
   other program by its name and by the link, the connections and
   datagrams to addresses outside the loopback networks, a raw socket
   and each way to create, rename, write or truncate a ``.php`` file,
   and 11 are allowed, among them both helpers, the loopback and reading
   a ``.php`` file;
#. runs the probe with the node's own ``python3``, which no policy
   labels: nothing is denied;
#. sends a keepalive and checks ``5 head: pass, seq 1 of 1`` and ``6
   set: pass, 1 loaded`` in the node's status;
#. appends the package again with ``--op delete``, loads the tree and
   syncs the node, which reaches seq 2 and removes the pins while the
   label stays, and runs the probe in the application a third time:
   nothing is denied;
#. sends a keepalive and checks ``seq 2 of 2`` and ``0 loaded``.

Like ``t9113``, it does not check that the node is ``healthy``.

Select test scripts
~~~~~~~~~~~~~~~~~~~

Pass ``-t <regex>`` to either runner to select test filenames with a
POSIX extended regular expression. The match includes the ``.sh`` suffix
but not the directory. All TAP cases in a selected script run.

.. code-block:: console

   $ testing/run-tests.sh -t '^t100[67]-' functional/build
   target# testing/run-target-tests.sh -t '^t310[12]-' upatch

With make, set ``TEST_FILTER``; it is passed into test VMs as well:

.. code-block:: console

   $ make -C testing functional/build VM=0 TEST_FILTER='^t100[67]-'

An empty filter selects everything; invalid expressions fail with status
2. ``-t`` overrides ``TEST_FILTER``. For unit tests, the filter selects
suite executable names. Filtering preserves order and does not add
prerequisite scripts or skip the normal build and VM setup.

.. _testing-backend:

Run the backend tests
---------------------

The SQL tests of the backend start a ClickHouse container with docker
or podman, at the image :src:`testing/vm/stack-lib.sh` pins, install
:src:`tools/backend/test/stub-quote-check.sh` as ``tpm_quote_check``,
and run every ``test/<name>.sql`` against a freshly loaded schema,
comparing what it prints with ``test/<name>.expected``:

.. code-block:: console

   $ make -C tools/backend tests

``tools/backend/test/run.sh <name>...`` runs only the tests named. The
runner loads the schema as an installation does,
``sql/apply-retention.sh`` included. A test that needs other settings
in place when that script runs puts them in ``test/<name>.setup.sql``,
and so does a test whose script needs rows to read.

A test that has a ``test/<name>.sh`` runs that script before its SQL,
with ``CLICKHOUSE_CLIENT`` set to the client of the test's server, and
what the script prints comes first in ``test/<name>.expected``. The
tests of ``jobs/tree-ingest`` run the job this way, on
``test/tree-show-1.1.0.json``, a ``bpm tree show`` output built from
:src:`testing/fixtures/keepalive/tree-1.1.0.json` with a made-up
manifest digest, and on ``test/tree-show-walk.json``, a ``bpm tree show
--walk`` output of the same three operations and two more in three
segments of two, two and one operation, at generations 2, 4 and 5. Its
manifest digests and the artifacts of operations 4 and 5 are made up.
Its operation digests and history roots are computed from them with
shirudo's formulas. ``test/stub-shirudo.sh`` stands in for ``shirudo``.
The tests need ``python3`` on the host.

The tests of ``jobs/sbom-scan`` run the job the same way, on the store
``test/sbom-store``, which holds an image in every state and objects out
of place, with ``test/stub-trivy.sh`` in place of Trivy and
``test/stub-aws.sh`` in place of ``aws``. The stub matches nothing: it
prints the report in ``test/trivy/`` named by the SHA-256 of the SBOM it
is given. ``test/sbom-put`` stores two of those SBOMs with
``jobs/sbom-put`` into a ``file://`` store and through the same AWS stub
into an ``s3://`` one, runs ``--scan`` on the first, and checks what it
refuses. ``test/labels-put`` loads label sets with ``jobs/labels-put``
by ``node_id``, by ``ak_name`` and by ``config_root``, replaces and
clears some, checks the union each node reads and the conflicts the job
reports, and checks what it refuses. A script that exits with status 77 skips its test and says
why. ``test/sbom-scan-trivy`` is skipped unless ``trivy`` is on the host
and ``SBOM_TRIVY_CACHE`` names a Trivy cache directory with a database,
since its findings would change with every database CI could fetch.
With them it runs the job with Trivy and checks what does not depend on
the database.

The stub quote checker verifies nothing. It reads the checker's rows and
prints the checker's answers, steered by fields that only look like
base64: ``attest`` is ``<reset_count>/<clock>/<body_sha256>``, ``sig`` is
``good`` or anything else for ``bad_signature``, and ``ak`` is any text.
With ``SHIRUDO_QUOTE_CHECK=<path>`` the runner installs that program
instead. It has to run inside the container, so it needs the libraries
it links there. A test named ``<name>-stub`` feeds quotes in the stub's
form and is skipped then.

.. _testing-xtop:

Run the xtop tests
------------------

:src:`tools/xtop/` is a Bun program. Its tests need ``bun`` on the host
and no ClickHouse: they feed its row mapping, roll-up and client rows
shaped as ``tools/backend/test/xtop-nodes.expected``,
``xtop-shields.expected`` and ``xtop-sbom.expected`` have them.

.. code-block:: console

   $ make -C tools/xtop tests

The target installs the locked packages, type-checks the program with
``tsc`` and runs ``bun test``. The queries themselves are checked against
the schema by the backend tests ``xtop-nodes``, ``xtop-shields`` and
``xtop-sbom``, which run the queries of :src:`tools/xtop/sql/` from their
``.sh`` scripts over the rows of ``test/xtop-nodes.setup.sql``, which the
other two ``.setup.sql`` link to.

Write a test
------------

Put a test in the lowest tier that can show the change works:

.. list-table::
   :header-rows: 1
   :widths: 40 60

   * - The change touches
     - The test goes in
   * - A function in ``util/<m>.c``
     - ``testing/unit/<m>.c``
   * - A command, a mechanism or an attack on one
     - The family that owns it, as an operator test if it needs no root,
       kernel or TPM, otherwise as a target test
   * - A whole delivery path
     - :src:`testing/end2end/`
   * - A parser of input from outside the host
     - A fuzz target in :src:`testing/fuzz/`, besides the functional test
   * - A script in :src:`.github/scripts/`
     - :src:`testing/ci-checks/`

Write a unit test
~~~~~~~~~~~~~~~~~

``testing/unit/<m>.c`` calls the functions of ``util/<m>.c`` and checks
them with the macros of ``unit.h``: ``EXPECT_*`` records a failure and
continues, ``ASSERT_*`` ends the case. List every case in the table,
which ends with an empty entry:

.. code-block:: c

   static void decode_refuses_non_hex(void)
   {
           __u8 out[1];

           EXPECT_EQ(hex_decode("zz", out, 1), -EINVAL);
   }

   static const struct unit_case cases[] = {
           UNIT_CASE(decode_refuses_non_hex),
           {}
   };

   UNIT_SUITE(hex, cases);

A case left out of the table is an unused static function, which fails
the build. Each case runs in a child process with a 60-second limit, so
a crash, a sanitizer report or a hang fails that case alone.
``unit_skip()`` skips a case with a reason. The suite links the util
objects from an archive and needs no build rule of its own. A suite for
code outside :src:`util/`, as ``quote_check`` is for
:src:`tools/quote-check/row.c`, names the object it links in
``UNIT_OBJS`` in :src:`Makefile.shirudo`.

Write a shell test
~~~~~~~~~~~~~~~~~~

1. Create ``testing/functional/<family>/t<F><K><NN>-<what>.sh`` with the
   next free number.

2. Start it from :src:`testing/` and source the harness. An operator test
   sources ``test-lib.sh``:

   .. code-block:: sh

      #!/bin/sh
      # SPDX-License-Identifier: BSD-2-Clause
      # Copyright (c) 2026 Authors of shirudo
      #
      # t<F>0<NN> -- <what the test shows>.

      cd "$(dirname "$0")/../.."
      . ./test-lib.sh

      SHIRUDO=${SHIRUDO:-../shirudo}
      [ -x "$SHIRUDO" ] || test_skip_all "shirudo not built"

      WORK=$(mktemp -d)
      trap 'rm -rf "$WORK"' EXIT

      test_expect_success '<what this case shows>' '
              "$SHIRUDO" version >"$WORK/out"
      '

      test_done

   A target test sources ``integration-lib.sh`` instead and calls
   ``target_guard``, which requires root, ``$SHIRUDO_BIN`` and an
   attached LSM:

   .. code-block:: sh

      cd "$(dirname "$0")/../.."
      . ./integration-lib.sh
      target_guard

      require_loaded shirudo-test-basic ||
              test_skip_all "cannot load the basic fixture"

3. Run the family and check that the test ran and passed:

   .. code-block:: console

      $ make -C testing functional/<family>

A target test finds loaded only what its family loaded, because each
family boots a VM of its own. ``require_loaded <fixture>`` loads a
signed fixture from the bundle unless it is loaded. State under
``/var/lib/shirudo`` is sealed, so a test cannot remove it, and the
tests of a family see what the earlier ones left there.

``test-lib.sh`` runs under ``set -eu``. Guard every step of an ``EXIT``
trap with ``|| true``, or the first failing step ends the cleanup and
the script fails although every case passed.

Add a fixture or a helper
~~~~~~~~~~~~~~~~~~~~~~~~~

- A target test loads BPF only from signed fixtures. Put the source in
  ``testing/fixtures/<name>.bpf.c`` and add a line
  ``build_fixture <name>.bpf.c <fixture> "$FIXTURE_WORK/trusted"`` to
  :src:`testing/vm/build-bundle-payload.sh`. The bundle build signs it
  outside the guest, which finds it as
  ``$SHIRUDO_TEST_FIXTURES_DIR/<fixture>.upatch``.
- A compiled helper goes in ``testing/helper/<name>.c`` with a build
  rule in :src:`Makefile.shirudo` and an entry in ``TEST_HELPERS``. A
  helper that a target test runs also goes in the list of helpers that
  :src:`testing/vm/build-bundle-payload.sh` copies into the bundle. A Python
  helper needs none of this.
- The keepalive bodies in :src:`testing/fixtures/keepalive/` carry real
  quotes in ``quotes.tsv``: per row the body's file name, then the
  ``attest``, ``sig``, ``ak`` and ``body_sha256`` columns of
  ``shirudo-quote-check``, so ``cut -f2-`` feeds the checker. A change
  to a node body fails ``t4006`` until
  :src:`testing/helper/capture-keepalive-quotes.sh` rebuilds the file.
  It quotes each body with ``test-keepalive-quote`` under the libtpms
  simulator, as ``status --otel`` quotes its own, with one TPM state
  for node A and another for node B; it needs no root and no VM, only
  ``make -C testing test-helpers`` with libtpms installed. Each run
  starts from fresh TPM states, so both the quotes and the two
  attestation keys change; a state directory named as its second
  argument keeps the keys.
- A fuzz target goes in ``testing/fuzz/fuzz-<name>.c`` with a seed
  corpus in ``testing/fuzz/corpus/<name>/`` and a rule in
  :src:`Makefile.shirudo` that names the sources it links.

Next steps
----------

- :doc:`/contribute/testing/test-coverage` for what each family covers and what
  no test covers
- :doc:`/upatches/test/testing` to test a upatch on a target
- :doc:`/contribute/code/contributing` before you send the change
