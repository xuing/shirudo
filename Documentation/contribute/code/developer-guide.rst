..
   SPDX-License-Identifier: BSD-2-Clause
   Copyright (c) 2026 Authors of shirudo

:page-type: How-to
:audience: shirudo contributors

Work from a checkout
====================

This page takes you from a clone of the repository to the operator
binary, the operator-only helper and the static target binary, shows
where the parts of the tree live and how to run the checks CI runs
before you send a change. :doc:`/contribute/testing/testing` covers the tests
and the test VM.

Before you begin
----------------

- A Linux host on x86-64, arm64 or riscv64. The test VM runs on x86-64
  and arm64 hosts only.
- A C compiler, GNU make, ``pkg-config``, ``python3``, and ``clang`` and
  ``llvm`` 23 with the BPF target, the release CI builds and tests with.
  :src:`.github/scripts/install-clang.sh` installs them on Debian, Ubuntu
  and Fedora.
- The development files that :src:`Makefile.config` probes for with
  ``pkg-config``:

  .. list-table::
     :header-rows: 1
     :widths: 40 60

     * - Module
       - Debian or Ubuntu package
     * - ``libcrypto >= 3.5``, ``libssl >= 3.5``
       - ``libssl-dev`` from OpenSSL 3.5 or newer
     * - ``tss2-esys >= 4.0``, ``tss2-tctildr``
       - ``libtss2-dev``
     * - ``libelf``
       - ``libelf-dev``
     * - ``zlib``
       - ``zlib1g-dev``
     * - ``libcurl >= 7.75``
       - ``libcurl4-openssl-dev``
     * - ``luajit``
       - ``libluajit-5.1-dev``

- The ``openssl`` command from OpenSSL 3.5 or newer. The build probe
  runs ``openssl list -public-key-algorithms`` and refuses a version
  without ML-DSA.
- The BTF of a kernel that has the signed-loader ABI, see
  :ref:`dev-vmlinux`.

The probe stops with ``shirudo: missing prerequisite:`` and an install
hint for each module it cannot find. It writes what it found to
``config.mk``, which ``make distclean`` removes.

.. _dev-openssl:

Install OpenSSL 3.5
-------------------

The build probe's hint names Ubuntu 26.04 and Fedora 43 as the first
releases that ship OpenSSL 3.5. Ubuntu 24.04 ships 3.0. On an older
distribution, build OpenSSL into a prefix of its own the way
:src:`.github/scripts/vm-toolchain.sh` does for CI:

1. Download and unpack the release:

   .. code-block:: console

      $ curl -fsSLO https://github.com/openssl/openssl/releases/download/openssl-3.5.9/openssl-3.5.9.tar.gz
      $ tar -xf openssl-3.5.9.tar.gz && cd openssl-3.5.9

   Compare the archive with the SHA-256 that ``vm-toolchain.sh`` pins
   before you build it.

2. Configure and install it under ``<prefix>``, a directory of your
   choice:

   .. code-block:: console

      $ ./Configure --prefix=<prefix> --openssldir=/etc/ssl --libdir=lib no-docs no-tests
      $ make -j"$(nproc)" && make install_sw

3. Put it first for every shell you build or test in:

   .. code-block:: console

      $ export PATH=<prefix>/bin:$PATH
      $ export PKG_CONFIG_PATH=<prefix>/lib/pkgconfig
      $ export LD_LIBRARY_PATH=<prefix>/lib

4. Verify that the command knows ML-DSA:

   .. code-block:: console

      $ openssl list -public-key-algorithms | grep -i ml-dsa

``sudo`` drops ``LD_LIBRARY_PATH`` and replaces ``PATH``. When you run
a make target as root, pass both on, as :src:`.github/scripts/tests.sh`
does:

.. code-block:: console

   $ sudo -E env PATH="$PATH" LD_LIBRARY_PATH="$LD_LIBRARY_PATH" make tests

.. _dev-vmlinux:

Select the kernel BTF
---------------------

The BPF objects that shirudo embeds compile against
``vendor/linux/vmlinux.h``. ``shirudo build`` run in the checkout root
uses the same header unless ``--vmlinux`` names another. The build
generates that header from BTF with :src:`tools/gen-vmlinux-h` and never
commits it. The embedded
admission program reads the signature verdict the kernel records in
``prog->aux->sig``, so the header must come from a kernel with the
signed-loader ABI. A header generated from the BTF of a kernel without
that ABI fails the BPF build.

The build takes the first of these sources:

.. list-table::
   :header-rows: 1
   :widths: 40 60

   * - Source
     - When
   * - ``BPF_VMLINUX_H=<path>``
     - Copies a prepared ``vmlinux.h``.
   * - ``BPF_VMLINUX_BTF=<path>``
     - Generates the header from a BTF file or an ELF file with a
       ``.BTF`` section.
   * - ``artifacts/bpf-next-kernel-debs/vmlinux.btf``
     - The BTF staged from the pinned CI kernel artifact.
   * - ``/sys/kernel/btf/vmlinux``
     - The running kernel.

``vendor/linux/.vmlinux-btf-source`` records the source used. When you
select another one, the next build regenerates the header.

1. Name the BTF of the kernel you build for:

   .. code-block:: console

      $ make BPF_VMLINUX_BTF=<path-to-btf>

2. Verify which source the header came from:

   .. code-block:: console

      $ cat vendor/linux/.vmlinux-btf-source

Build the operator binary
-------------------------

1. Build ``shirudo`` in the checkout root:

   .. code-block:: console

      $ make

2. Verify the build:

   .. code-block:: console

      $ ./shirudo version

The build compiles the vendored libbpf, generates ``vmlinux.h``,
compiles the userspace objects and the BPF objects under :src:`bpf/`,
embeds the BPF objects into ``util/loader.o`` and links. These make
variables change it:

.. list-table::
   :header-rows: 1
   :widths: 32 68

   * - Variable
     - Effect
   * - ``V=1``
     - Prints the full command lines.
   * - ``WERROR=0``
     - Lets a compiler newer than the tree finish the build. A warning
       fails every build by default, the BPF objects and the vendored
       libbpf included. Fix the warning instead of keeping this set.
   * - ``CC=clang``
     - Compiles the userspace objects with clang rather than ``cc``. CI
       builds with both compilers at the same flags and runs the unit
       tests against each, in the ``gcc`` and ``clang`` jobs of the
       ``Build`` workflow.
   * - ``SHIRUDO_DEBUG=0``
     - Leaves out ``-g``.
   * - ``SANITIZE=address,undefined``
     - Instruments the host binaries and the test helpers with ASan and
       UBSan. See :doc:`/contribute/testing/testing`.
   * - ``SANITIZE=thread``
     - Instruments them with TSan. See
       :doc:`/contribute/testing/testing`.
   * - ``SANITIZE=memory``
     - Instruments them with MSan, the vendored libbpf included, and
       wants the instrumented libraries
       :src:`.github/scripts/msan-deps.sh` builds. See
       :doc:`/contribute/testing/testing`.

Build the shirudo-build helper
------------------------------

The core binary never compiles or signs. ``shirudo build``, ``shirudo
image build``, ``shirudo image verify``, ``shirudo keys vouch`` and the
operator ``bpm`` subcommands (``build``, ``push``, ``tree append``,
``tree show`` and ``config update``) execute the separate ``shirudo-build`` helper, which
is the only binary that links the signer.

1. Build the helper:

   .. code-block:: console

      $ make shirudo-build

2. Point the core binary at it:

   .. code-block:: console

      $ export SHIRUDO_BUILD=$PWD/tools/shirudo-build/shirudo-build
      $ export PATH=$PWD:$PATH

3. Verify that the operator subcommands resolve. ``shirudo bpm --help``
   lists ``build`` and ``push`` only when the helper resolves:

   .. code-block:: console

      $ shirudo bpm --help

The core binary takes the helper from ``SHIRUDO_BUILD``, then from
``$(libexecdir)/shirudo/shirudo-build``, the path compiled in, then
from ``PATH``. Set ``SHIRUDO_BUILD`` rather than relying on ``PATH``:
an operator package installed on the same host provides the compiled-in
path, which takes precedence over ``PATH``.

``bpm build`` compiles with the package directory as its working
directory. To build a package with a checkout's ``vmlinux.h`` and BPF
headers, give the package directory ``vendor`` and ``bpf`` symbolic
links to the checkout's, as ``t7005`` does. An installed operator package
needs neither: ``shirudo-build`` falls back to the headers and
``vmlinux.h`` it installs, as the operator VM of the end-to-end test
builds ``kernel-obs``.

Build the target binary
-----------------------

The target binary is a fully static PIE. It links static archives of
OpenSSL, libcurl and tpm2-tss that ``make target-deps`` builds from
source, and the distribution's static ``libelf``, ``zlib``, ``zstd``
and LuaJIT archives.

1. Install the static archives and the tools the tpm2-tss build needs.
   CI installs ``autoconf``, ``autoconf-archive``, ``automake``,
   ``libtool``, ``libltdl-dev`` and ``libzstd-dev`` for this on Ubuntu.

2. Build the dependencies and the binary:

   .. code-block:: console

      $ make target

   ``make target`` runs ``make target-deps`` first. It builds OpenSSL
   3.5.9, libcurl 8.18.0 and tpm2-tss 4.2.0 under ``build/target-deps``
   and stages every archive in ``build/target-deps/lib``.

3. Verify that the result is a static PIE without an interpreter,
   shared dependencies or library search paths:

   .. code-block:: console

      $ sh .github/scripts/check-static-target.sh shirudo-target

To use dependencies built elsewhere, set ``TARGET_DEPS_PREBUILT=1`` and
point ``SHIRUDO_TARGET_PKG_CONFIG_PATH`` and
``SHIRUDO_TARGET_STATIC_LIBDIR`` at them. ``make target-deps-clean``
removes ``build/target-deps``.

Refresh the vendored libbpf
---------------------------

:src:`vendor/libbpf` holds libbpf, its BPF-side headers and the BPF UAPI
headers. No kernel tree is needed to build. Refresh the copy only when
a change needs a newer libbpf or UAPI:

.. code-block:: console

   $ make bpf-deps KERNEL_SRC=<kernel-tree>

``<kernel-tree>`` is a kernel checkout. Without ``KERNEL_SRC``,
:src:`tools/bpf-deps/bpf-deps.sh` makes a shallow clone of bpf-next.

The source revision is recorded in ``vendor/libbpf/COMMIT``. After
refreshing, reapply the local changes :src:`vendor/libbpf/README.md`
lists.

Other make targets
------------------

.. list-table::
   :header-rows: 1
   :widths: 40 60

   * - Command
     - Result
   * - ``make install``
     - Installs the operator binary and the bash completion under
       ``prefix``, ``/usr/local`` by default.
   * - ``make install-target``
     - Installs the static target binary as ``shirudo``, the units and
       timers, the dracut module and ``shirudo-gen-initrd``.
   * - ``make quote-check``
     - Builds ``tools/quote-check/shirudo-quote-check``, the program a
       telemetry backend runs on keepalive quotes, as a static PIE in
       either profile. The link needs the static archives of the C
       library and of ``libcrypto`` with those
       ``pkg-config --static --libs libcrypto`` names: on Ubuntu 26.04,
       ``libzstd-dev`` and ``libjitterentropy3-dev`` beside
       ``libssl-dev`` and ``zlib1g-dev``. CI installs them with
       :src:`.github/scripts/install-static-libcrypto-deps.sh`, which
       reads that list. Where the distribution ships no
       ``libcrypto.a``, as Fedora does not, ``make quote-check`` and
       ``make install-operator`` first build a static OpenSSL into
       ``build/quote-check-openssl`` with :src:`Makefile.target-deps`,
       which needs ``perl``, and compile the checker's objects against
       its headers under ``build/quote-check/``; the link then needs
       ``glibc-static``. ``QUOTE_CHECK_OPENSSL=<prefix>`` names another
       static OpenSSL. ``shirudo`` and ``shirudo-build`` still link the
       distribution's OpenSSL. ``make distclean`` removes that build. A
       ``SANITIZE=`` build links the checker against the shared
       libraries, because the sanitizer runtimes do not link
       statically. See :doc:`/reference/cli/quote-check`.
   * - ``make install-operator``
     - Installs the operator binary, the helper under
       ``$(libexecdir)/shirudo``, ``shirudo-quote-check``, the image
       scripts, ``vmlinux.h`` and the BPF headers.
   * - ``DESTDIR=<dir>``, ``prefix=<dir>``, ``bindir=<dir>``,
       ``libexecdir=<dir>``, ``systemdunitdir=<dir>``
     - Override the install paths. The unit and dracut directories are
       absolute by default and do not follow ``prefix``.
   * - ``make -C packaging bindeb-pkg``, ``binrpm-pkg``, ``bintar-pkg``
     - Build the distribution packages from ``make clean``.
       ``PKG_ROLES=operator`` builds the operator package alone. See
       :doc:`/start/install`.
   * - ``make docs``
     - Renders the documentation and serves it on
       ``http://127.0.0.1:8000``. Rebuilds on changes with ``fswatch`` or
       ``inotifywait``. See
       :doc:`/contribute/documentation/writing-docs`.
   * - ``make tags``, ``make cscope``
     - Index the C sources, untracked ones and the generated
       ``vendor/linux/vmlinux.h`` included, for an editor: ``tags`` with
       ctags, ``cscope.files`` and ``cscope.out`` with cscope.
   * - ``make clean``, ``make distclean``
     - Remove the build products, and with ``distclean`` also
       ``config.mk``, the target dependencies and the vendored libbpf
       build and the source indexes.
   * - ``make help``, ``make -C testing help``
     - List the targets.

Project layout
--------------

.. list-table::
   :header-rows: 1
   :widths: 30 70

   * - Path
     - Contents
   * - :src:`shirudo.c`
     - The command dispatch table.
   * - ``builtin-*.c``, :src:`builtin.h`
     - One file per top-level command: ``attest``, ``bpm``, ``build``,
       ``config``, ``genkey``, ``image``, ``init``, ``keys``,
       ``status``, ``upatch`` and ``version``.
   * - :src:`util/`
     - The userspace library both binaries link. :src:`util/sign.c` is
       linked into ``shirudo-build`` only.
   * - :src:`bpf/`
     - The embedded BPF programs: ``bpf2.c`` (admission, mount, image
       and device guards), ``seal.c`` (the seal) and ``unload.c`` (the
       signed unload directive).
   * - :src:`bpf/lib/`
     - The headers more than one BPF program includes: the LSM helpers
       and verity device records of ``bpf2.c`` and ``seal.c``, and,
       shared with upatches and userspace, decoders, identity,
       serializers, tamper and integrity counters and common helpers.
   * - :src:`include/shirudo/`
     - Integer types, string and number helpers, the ``.upatch``
       container layout, TPM types and the enforcement definitions
       shared between userspace and BPF.
   * - :src:`tools/shirudo-build/`
     - The operator-only helper: compile, sign, unload directives,
       image signing, ``keys vouch``, ``bpm build``, ``push``,
       ``tree append``, ``tree show`` and ``config update``.
   * - :src:`tools/quote-check/`
     - ``shirudo-quote-check``, a program of its own that checks
       keepalive quotes with the TPM parsers of :src:`util/tpm_wire.c`.
       No other binary links it.
   * - :src:`tools/gen-image/`
     - ``shirudo-gen-image``, ``shirudo-gen-runtime`` and
       ``shirudo-gen-verity``, which make the runtime and config images,
       their shared ``common.sh`` and the runtime unit templates.
   * - :src:`tools/gen-initrd/`
     - The dracut module, the initrd generator and the installer.
   * - :src:`tools/gen-vmlinux-h/`
     - The ``vmlinux.h`` generator.
   * - :src:`tools/bpf-deps/`
     - The script that refreshes :src:`vendor/libbpf`.
   * - :src:`tools/put-shields`
     - Builds every shield package under :src:`upatches/` and pushes it
       to one registry namespace and its index, see
       :doc:`/upatches/publish/publishing`.
   * - :src:`vendor/libbpf/`
     - Vendored libbpf and BPF UAPI headers.
   * - ``vendor/linux/``
     - The generated ``vmlinux.h``. Not tracked.
   * - :src:`testing/kernel/`
     - The upstream kernel pin, configuration, patches and build script
       used by CI. See :doc:`/internals/kernel-patches`.
   * - :src:`upatches/`
     - The shipped packages: ``kernel-obs`` with its Beefile, and the
       three ``kernel-cve`` detectors and the ``kernel-cve``
       mitigation, each with its own.
   * - :src:`systemd/`
     - Unit and timer templates for the target.
   * - :src:`completion/`
     - The bash completion. Command names come from
       ``shirudo --list-cmds``. Option lists are maintained by hand.
   * - :src:`packaging/`
     - The tar, deb and rpm packaging.
   * - :src:`testing/`
     - Unit, functional, end-to-end and fuzz tests, the test VM and
       their helpers. See :doc:`/contribute/testing/testing`.
   * - ``Documentation/``
     - This documentation.
   * - :src:`.github/`
     - The CI workflows and the scripts they run.
   * - ``Makefile``, :src:`Makefile.shirudo`, :src:`Makefile.config`,
       :src:`Makefile.target-deps`, :src:`Makefile.version`
     - The entry points, the build graph, the prerequisite probes, the
       target dependency build and version discovery.
   * - ``build/``, ``artifacts/``
     - Generated: build products, the test VM state and the test
       kernels. Not tracked.

``shirudo --list-cmds`` prints the top-level commands.

.. _run-ci-checks:

Run the CI checks locally
-------------------------

CI runs these scripts from :src:`.github/scripts/`. Each takes the
arguments of ``git rev-list``, such as ``origin/main..HEAD``, and checks
the commit at ``HEAD`` alone without them.

.. list-table::
   :header-rows: 1
   :widths: 34 66

   * - Script
     - Checks
   * - ``check-dco.sh <range>``
     - A one-line subject, a body beyond the tags and the author's
       ``Signed-off-by:``. See :doc:`/contribute/code/contributing`.
   * - ``check-style.sh <range>``
     - The kernel's ``checkpatch.pl`` in strict mode over the C each
       commit touches, at its default limit of 100 columns, and over its
       message, with the checks that have no meaning in userspace
       switched off, each listed in the script with its reason. It also
       refuses a block comment whose text starts on the ``/*`` line, the
       C library's integer names such as ``uint32_t``, ``unsigned int``
       and its kin in userspace, ``strtoul()``, ``atoi()``,
       ``strcpy()``, ``sprintf()`` and their kin outside the files the
       script names, and a subject longer than 75 characters. ``--diff``
       checks uncommitted changes, ``--files`` whole files and
       ``--types`` lists what stays enabled.
   * - ``check-spdx.sh``
     - The SPDX tag of every tracked source, in the kernel's form for its
       type: ``BSD-2-Clause`` for userspace and ``GPL-2.0 OR
       BSD-2-Clause`` for everything compiled into a BPF object, the
       headers it includes and the decoders a package ships. Takes no
       range.
   * - ``check-unused.sh``
     - An extern function of the userspace C that nothing calls: the
       compiler reports an unused ``static`` function, never an extern
       one. A call from a test counts. Takes no range.
   * - ``scan-build.sh <vmlinux-btf>``
     - The binary, the shirudo-build helper and the quote checker built
       under clang's static analyzer with its default checkers, failing
       on any finding: a NULL or uninitialized value used, memory leaked
       or used after its free, a store never read and more. It installs
       Debian testing's packages and clang 23's tools, so it runs in a
       throwaway container; on a host that has them,
       ``scan-build-23 --status-bugs --exclude vendor make ANALYZE=1``
       does the same. ``ANALYZE=1`` builds without ``_FORTIFY_SOURCE``
       and with ``-fno-inline``, whose absence would let glibc's
       wrappers hide from the analyzer which libc function a call
       makes. CI runs it as the ``scan-build`` job of the ``Build``
       workflow and keeps the HTML report of a failed run.
   * - ``check-sparse.sh``
     - ``make sparse``: sparse over the userspace sources the binaries
       are built from, failing on any warning. It finds a value moved
       between host order and ``__le32`` or ``__be32`` without
       ``cpu_to_le32()``, ``le32_to_cpu()`` or their kin from
       ``<shirudo/byteorder.h>``. Takes no range.
   * - ``check-coccinelle.sh [<rule>...]``
     - Every semantic patch in :src:`testing/coccinelle/`, or the rules
       named, over the C the project writes, failing on any match with
       its file, line, rule and message. Takes no range; see
       `Coccinelle rules`_.
   * - ``build-commits.sh <range>``
     - Builds every commit on its own: ``make``, ``make
       shirudo-build``, ``make quote-check`` and ``make -C testing
       test-helpers``. It
       refuses to start with uncommitted changes and checks out each
       commit in the working tree.
   * - ``install-clang.sh [<package>...]``
     - Installs clang and LLVM 23, from the distribution, Debian unstable
       or apt.llvm.org, and points ``clang``, ``llvm-strip``,
       ``llvm-objcopy`` and ``llvm-symbolizer`` in ``/usr/bin`` at them.
       Every CI job that compiles runs it. It installs packages as root,
       so run it only in a throwaway container or VM.
   * - ``build-debian.sh <btf>``
     - Installs Debian testing's compiler and libraries and clang 23
       from unstable, builds the
       binary and the helper with the BTF given, and runs the unit tests
       and ``check-operator-linkage.sh``. The ``Build`` workflow runs it
       in a ``debian:testing`` container on arm64 and riscv64. It
       installs packages as root, so run it only in a throwaway
       container.
   * - ``check-static-target.sh <binary>``
     - That a target binary is a static PIE.
   * - ``check-operator-linkage.sh <binary>...``
     - That each operator binary links no shared library but ``libc``,
       ``libcrypto``, ``libssl``, ``libcurl``, ``libtss2-esys``,
       ``libtss2-tctildr``, ``libelf``, ``libz``, ``libluajit-5.1`` and
       its own dynamic loader, in any version. CI runs it on the binaries
       the deb and rpm operator packages install. A ``SANITIZE`` build
       fails it, because it also links the sanitizer runtimes or, with
       clang, the libraries they need.
   * - ``check-runtime-image.sh <binary>``
     - That a runtime image of the default size of
       ``shirudo-gen-runtime`` holds the target binary, and how much
       space it leaves. When it fails, raise ``size=`` in
       :src:`tools/gen-image/shirudo-gen-runtime`.
   * - ``tests.sh setup|run [unit|functional|functional-ci-N|end2end]``
     - Prepares a CI runner as the VM host and runs ``make tests``, or
       one part of it: ``unit`` runs the unit and ``ci-checks`` tests,
       ``functional`` and ``end2end`` the tier of that name.
       ``functional-ci-N`` runs one of the four functional shards,
       where ``N`` is 1 through 4, two families' VMs at a time. The ``CI suite`` workflow runs
       the unit and script checks, functional shards, and end-to-end
       tests in parallel on x86-64.
       With ``VM=0``, setup uses the kernel CI artifact's BTF and installs
       only host test dependencies. The arm64 job uses this to run unit,
       ``ci-checks`` and host functional tests without target VMs.
       Meant for CI runners, which are discarded afterwards.
   * - ``proofs.sh install-cbmc|install-headers|install-lean``,
       ``proofs.sh list|run <k> <n>``
     - Installs the CBMC and the elan CI pins, each verified by its
       SHA-256, and Lean, all without root: CBMC into ``build/cbmc``,
       elan and the toolchain ``lean-toolchain`` names into
       ``ELAN_HOME``. Prints the directory to put on ``PATH``.
       ``install-headers`` installs with ``sudo`` on Ubuntu the headers
       of the libraries the CBMC harnesses include. ``run``
       runs the CBMC proofs of shard ``<k>`` of ``<n>`` as the ``CBMC``
       jobs of the ``Proofs`` workflow do, each alone under a memory and
       time cap, and ``list`` prints them. See
       :doc:`/contribute/testing/proofs`.

``check-style.sh`` fetches the kernel's ``checkpatch.pl`` at a pinned
tag into ``build/checkpatch/`` and verifies its SHA-256. It asks
kernel.org first and then its GitHub mirror, gives each ten seconds to
answer, and does not ask again a source that failed once. Set
``CHECKPATCH=<path>`` to use a kernel tree's
``scripts/checkpatch.pl`` instead, for example without network access.

Before you send a change, run what CI runs on a pull request:

1. Run the checks over your commits:

   .. code-block:: console

      $ .github/scripts/check-dco.sh origin/main..HEAD
      $ .github/scripts/check-style.sh origin/main..HEAD
      $ .github/scripts/check-spdx.sh
      $ .github/scripts/check-unused.sh
      $ .github/scripts/check-sparse.sh
      $ .github/scripts/check-coccinelle.sh
      $ .github/scripts/build-commits.sh origin/main..HEAD

2. Run clang's static analyzer, in a throwaway container with
   ``scan-build.sh`` or on a host that has clang 23's tools:

   .. code-block:: console

      $ scan-build-23 --status-bugs --exclude vendor make ANALYZE=1

3. Run the tests the change touches, and ``make tests`` before you
   send. When the change touches memory handling or binary formats, run
   ``make tests VM=0 SANITIZE=address,undefined`` from a clean tree too,
   as CI does. See :doc:`/contribute/testing/testing`.

4. If you changed the documentation, check it and render it:

   .. code-block:: console

      $ .github/scripts/check-docs.sh
      $ make -C Documentation html

5. Verify that every script printed its summary line and exited 0, for
   example ``DCO: 3 commits checked`` and ``style: 3 commits checked``.

Coccinelle rules
----------------

Each semantic patch in :src:`testing/coccinelle/` describes a pattern
the tree is kept free of, and ``check-coccinelle.sh`` fails on any
match, in the ``Coccinelle`` job of the ``Lint`` workflow. The rules
cover the C the project writes, as ``check-style.sh`` takes it: not the
vendored libbpf, the BTF dumps or the generated headers. A rule that
can rewrite what it finds does so with ``-D patch``:

.. code-block:: console

   $ spatch -D patch --sp-file testing/coccinelle/zero_init.cocci \
         --in-place --include-headers util/json.c

.. list-table::
   :header-rows: 1
   :widths: 24 76

   * - Rule
     - Refuses
   * - ``array_size``
     - An element count divided out by hand rather than
       ``ARRAY_SIZE()``, in a macro too, which it rewrites, and an
       ``ARRAY_SIZE()`` defined outside ``<shirudo/misc.h>``, which it
       leaves to be removed.
   * - ``zero_init``
     - ``= {0}`` rather than ``= {}``. Rewrites.
   * - ``minmax``
     - A ternary that picks the smaller or larger of two values rather
       than ``min()`` or ``max()``. Rewrites.
   * - ``minmax_t``, ``minmax_cast``
     - ``min_t()`` or ``max_t()`` where ``min()`` or ``max()`` takes
       the values as they are, and a cast inside ``min()`` or
       ``max()``.
   * - ``ifnullfree``
     - A NULL test before a free function that takes NULL. Rewrites.
   * - ``void_cast``
     - A ``(void)`` cast, of a result or a variable. Rewrites.
   * - ``scrub``
     - A ``memset()`` of a local that nothing reads afterwards, which
       the compiler may drop, rather than ``memzero_explicit()``.
       Rewrites.
   * - ``scrub_missing``
     - A local filled with an activated credential, a KDF output or an
       ECDH shared value, or by ``hex_bytes()``, ``hex_decode()`` or
       ``getrandom()`` when named for a secret, that a return or function
       fallthrough leaves without a full-size ``memzero_explicit()``. It
       recognizes output passed by address.
   * - ``sensitive_scrub``
     - A local of a struct with a member marked ``__sensitive`` that a
       return path leaves, once the function has used it, without
       a full-size ``memzero_explicit()`` of the whole struct or a
       ``__cleanup()`` function, and the address of a compound literal
       of such a struct.
       The structs come from the headers under :src:`include/`,
       :src:`util/` and :src:`tools/` and at the top of the tree.
   * - ``curl_slist_free``
     - A libcurl header list freed without first scrubbing its copied
       header strings with ``curl_slist_free_sensitive()``.
   * - ``secret_cmp``
     - ``memcmp()`` of a secret or what derives from one rather than
       ``memneq_explicit()``.
   * - ``digest_concat``
     - Two strings fed to a digest one after the other, each by its
       ``strlen()`` alone, with no terminator, length or delimiter
       between them to say where the first ends.
   * - ``openssl_ret``
     - A test of the truth of an OpenSSL function that returns 0 or a
       negative value on failure.
   * - ``overflow``
     - A sum or product tested for overflow by hand rather than with
       the helpers of ``<shirudo/overflow.h>``.
   * - ``ctype``
     - A ``char`` passed to a ``<ctype.h>`` function without a cast to
       ``__u8``. Rewrites.
   * - ``memnull``
     - A NULL passed to a memory or string function, and a
       ``memcpy()`` of overlapping buffers.
   * - ``sizeof_ptr``
     - The size of a pointer where the object it points to is meant,
       wherever it is taken, unless the pointer's own address goes to
       the same call.
   * - ``literal_len``
     - A length that does not match the string literal ``memcpy()``
       copies, with or without its terminator.
   * - ``literal_count``
     - A string literal compared or searched with ``memcmp()``,
       ``memchr()`` or their kin under a length written out as a number,
       where ``sizeof`` of the literal or a helper of
       ``<shirudo/string.h>`` takes it from the literal.
   * - ``literal_strscpy``
     - A string literal copied into an array with ``strscpy()``, where
       ``strscpy_literal()`` refuses at build time a literal the array
       cannot hold.
   * - ``read_unterminated``
     - A buffer that ``read()``, ``pread()``, ``recv()``, ``readlink()``
       or the ``getxattr()`` family filled, passed to ``strlen()``,
       ``strcmp()``, ``strchr()`` or their kin before anything
       terminated it: ``buf[n] = '\0'``, ``span_to_str()``, or an array
       zeroed where it is declared and read into for one byte less than
       its size.
   * - ``file_as_string``
     - The bytes ``read_file()``, ``read_fd()`` or a reader of a package
       member returned, passed to ``strstr()``, ``strtok_r()``,
       ``strlen()`` or their kin before any function took them with
       their length: such a function takes the file to end at its first
       NUL. ``span_to_str()`` on the buffer in place refuses one.
   * - ``option_by_hand``
     - A value compared with an option name, a literal that starts with
       ``-`` and is longer than one character, outside
       :src:`util/options.c`, which parses every command's options from
       its table, and the help and image gate code that looks for
       ``--help`` and the options an image refuses.
   * - ``test_after_use``
     - A pointer tested for NULL after its use.
   * - ``null_deref``
     - A pointer dereferenced in the branch of the test that found it
       NULL.
   * - ``alloc_unchecked``
     - An allocation used before it is checked.
   * - ``use_after_free``
     - Memory used or freed again after it was freed.
   * - ``uninit``
     - A local read after a ``goto`` jumped over its assignment.
   * - ``local_escape``
     - The address of a local array or variable, or of a member or element
       of one, stored in an object the caller passed in, in a member at
       any depth, an element or ``*out``, and left there on a path out,
       where it points into a dead frame; and the address of a local of a
       block left in a pointer declared outside it and read after the
       block ends.
   * - ``alloc_size``
     - An allocation sized for another type than its pointer, and a
       free of memory no allocator returned.
   * - ``double_test``, ``double_init``
     - A term tested twice, an ``if`` or a conditional whose branches
       are alike, an ``else if`` that tests what an ``if`` before it
       tested, and a member initialized twice.
   * - ``va_end``
     - A ``va_start()`` or ``va_copy()`` without a ``va_end()`` on a
       path out.
   * - ``fd_leak``
     - A descriptor left open on a path out once its open succeeded,
       where it is not returned, stored or handed to what closes it, a
       lock of ``eventlog_lock()`` or ``seal_lock()`` among them.
   * - ``cloexec``
     - A descriptor or stream opened without close-on-exec.
   * - ``name_after_fd``
     - A path passed to ``realpath()`` or ``readlink()`` in a function
       that holds a descriptor opened from the same path or passed in
       with it: the name is looked up again and can lead to another
       file than the descriptor.
   * - ``banned``
     - ``rand()``, ``strtok()``, ``usleep()``, ``signal()``,
       ``alloca()``, ``setjmp()``, the time and user database functions
       without ``_r`` and their kin, and ``abort()`` and ``assert()``
       outside :src:`testing/`.
   * - ``no_exec``
     - A function that runs a program, outside the operator helper, the
       command that hands work to it and the tests.
   * - ``anssi_misc``
     - A bitwise operator on a ``bool``, a comma that sequences
       statements, a backward ``goto``, a floating-point loop counter
       and a bare ``NULL`` passed to a variadic function, after the
       ANSSI rules for secure C.
   * - ``cert_misc``
     - A ``char`` array too short for the NUL of the literal it holds, a
       ``char`` that keeps what ``getc()`` returns, and ``getenv()``
       passed on unchecked, after the CERT C rules.
   * - ``getenv_null``
     - A ``getenv()`` result kept in a variable and read before a test
       that it is not ``NULL``, in its own condition or before it, where
       ``cert_misc`` refuses one passed on directly.
   * - ``strerror_negative``
     - ``strerror()`` of a variable that holds a negative error number:
       one assigned ``-errno`` or another negated value, or tested below
       0 by the ``if`` that holds the call.
   * - ``errno_clobber``
     - A cleanup call, such as ``close()``, between a failure and the
       read of its ``errno``, after CERT C ERR30-C.
   * - ``positive_errno``
     - A bare error number or ``errno`` returned or put in ``ret``,
       alone or as a branch of a conditional, where a negative error
       number belongs.
   * - ``double_close``
     - A descriptor passed to a call after it was closed, after CERT C
       FIO46-C.
   * - ``wrong_test``
     - A test for a negative value or ``NULL``, right after an
       assignment, of another variable than the one assigned.
   * - ``scaled_arith``
     - A ``sizeof`` added to a pointer to anything wider than a byte,
       after CERT C ARR39-C.
   * - ``fclose_unchecked``
     - ``fclose()`` of a stream opened for writing with its result
       ignored, after CERT C ERR33-C.
   * - ``dead_store``
     - A value stored in a local and stored over on every path, the
       error exits included, before anything reads it, after CERT C
       MSC12-C. Following every path of a long function can take
       minutes, so the rule gives up on a file after one; the check
       names each file it gave up on.
   * - ``stale_success``
     - A ``goto`` or ``break`` that leaves with what a call or a 0 stored
       in a return code declared with an error, ``int ret = -EACCES``,
       where the jump relies on that error. A function that stores a
       positive value in it answers yes or no, and its 0 is left alone.
   * - ``break_error``
     - An error stored before a ``break`` that the code after the loop
       does not test before it calls something other than a cleanup,
       and then stores over.
   * - ``sum_overwrite``
     - A sum stored in a total under a condition, between a value it had
       and an addition to it, where ``+=`` is likely meant.
   * - ``bpf_map_rmw``
     - ``++``, ``+=`` or ``|=`` through the value of a map that is not
       per-CPU, or through inode, socket or cgroup storage, which other
       CPUs update meanwhile.
   * - ``bpf_cas_unchecked``
     - A compare-and-swap whose result is dropped.
   * - ``bpf_check_then_insert``
     - A ``BPF_ANY`` update of a key after a lookup found it missing,
       which races with another CPU doing the same.
   * - ``bpf_publish``
     - ``WRITE_ONCE()`` of a pointer, which publishes what it points to
       without ordering the stores that filled it.
   * - ``bpf_user_double_fetch``
     - Two reads of the same user address, between which the memory can
       change.
   * - ``bpf_map_use_after_delete``
     - A map value read through the pointer a lookup returned after
       ``bpf_map_delete_elem()`` removed an entry of the same map, whose
       element another update can already have taken.

A new pattern worth refusing gets a rule: write it from scratch under
the BSD-2-Clause, or carry one from a project that offers it with a
BSD-2-Clause branch, keeping its SPDX and copyright lines and naming it
in ``check-spdx.sh``, as ``bpf_map_use_after_delete`` comes from
tetragon. Give it a header that says why the pattern is refused, fix the
tree in the commits before it, and add it to the table. A rule exists
only to run in CI. Where the tree gives it no match, add a case of what
it refuses to ``t0006-check-coccinelle``, which shows that it matches.
``check-coccinelle.sh`` runs a rule without the headers a file includes,
which keeps it fast but leaves the types they declare unknown. A rule
that needs them, as ``sizeof_ptr`` needs the type of a struct member,
names its include options on a ``#spatch`` line. A rule whose search can
run long names ``--timeout <seconds>`` there, as ``dead_store`` does: the
check then runs it one file at a time and names each file spatch gave up
on, rather than failing.

Every rule declares ``SEC`` an attribute, as the rules run over the BPF
sources too. Without that, Coccinelle takes a map defined as
``} name SEC(".maps");`` for a type, and no pattern matches a call that
takes the map's address, without an error; ``t0006`` checks that each
rule declares it. The ``bpf_`` rules also read the BPF sources
through :src:`testing/coccinelle/bpf.macros`, which tells Coccinelle what
``SEC()``, ``BPF_PROG()`` and the map definition macros mean. A file that
defines its own token-pasting macros, as
:src:`upatches/kernel-obs/obs_table.h` does, stays out of their reach.
Each matches a hazard that exists on every kernel. Per-CPU memory used
as scratch is a hazard only under some preemption models and program
types, which a rule cannot tell, so no rule refuses it.
:doc:`/upatches/write/memory-consistency/hazards` explains each hazard
and where it applies.

Next steps
----------

- :doc:`/contribute/code/develop-locally` to run both roles on one machine and
  change shirudo end to end
- :doc:`/contribute/testing/testing` to run and write tests
- :doc:`/contribute/code/contributing` for the commit message and the sign-off
- :doc:`/contribute/code/coding-style` for the C code
- :doc:`/reference/cli/index` for the commands
