..
   SPDX-License-Identifier: BSD-2-Clause
   Copyright (c) 2026 Authors of shirudo

:page-type: Reference
:audience: shirudo contributors

Arch support
============

shirudo targets x86-64, arm64 and riscv64, and its code is written for
all three. The project is under heavy development, and the three are not
at the same stage yet: CI builds and tests x86-64, including tests that
boot the test VM. On arm64, CI runs host tests and the test VM runs
locally. No riscv64 target has booted shirudo so far. Some of the gaps
are in shirudo, others in the kernel. This page lists both for anyone
who wants to help close them.

Kernel facts on this page come from the bpf-next tree the test kernel
builds. A later kernel can differ.

Comparison
----------

.. list-table::
   :header-rows: 1
   :widths: 22 26 26 26

   * - Area
     - x86-64
     - arm64
     - riscv64
   * - CI
     - Every tier on every push
     - Unit tests, ``ci-checks``, and host functional tests (``VM=0``)
     - Unit tests under QEMU user emulation, after each push to ``main``
   * - Test VM
     - Boots on x86-64 hosts
     - Boots on arm64 hosts; ``t1007`` checks its settings without
       booting
     - None; :src:`testing/vm/arch.sh` refuses the architecture
   * - Packages
     - Built in CI
     - Not built in CI
     - Not built in CI
   * - Toolchain hardening beyond the common flags
     - Stack-clash protection, call-used register zeroing,
       ``-fcf-protection=full``
     - Stack-clash protection, call-used register zeroing,
       ``-mbranch-protection=standard``
     - None
   * - Kernel project patch set
     - Included in the external kernel build
     - Included in the external kernel build
     - Included in the external kernel build
   * - BPF trampolines (``lsm``, ``fentry``, ``fexit``, ``fmod_ret``)
     - As many programs per function as fit a 4 KB image: 57 ``fentry``
       or ``fexit`` programs, about 35 of the other two kinds
     - As many as fit a 4 KB image: about 33 ``lsm`` or ``fmod_ret``
       programs
     - As many as fit a 4 KB image, and only on a kernel built without
       ``CONFIG_CFI``
   * - ``fmod_ret`` on functions the kernel build tags
       (``CONFIG_BPF_FMODRET_SCAN``)
     - Yes
     - Yes
     - No, only on declared targets
   * - BPF arenas
     - Yes
     - Yes; atomic read-modify-write on arena memory needs the LSE
       atomics of ARMv8.1
     - Only on CPUs with the Zacas extension, on a kernel built with
       ``CONFIG_RISCV_ISA_ZACAS``
   * - BPF stack per program
     - 2 KiB
     - 2 KiB
     - 512 bytes
   * - BPF exceptions and private stacks
     - Yes; exceptions need the ORC unwinder
     - Yes
     - No
   * - ``kprobe`` at a function's entry
     - Through ftrace
     - Through a breakpoint
     - Through a breakpoint
   * - Example packages
     - ``kernel-obs`` and ``kernel-cve``
     - ``kernel-obs`` on CPUs with LSE atomics
     - ``kernel-obs`` on CPUs with Zacas, untested

x86-64
------

- Targets need upstream commit ``31ac959c915c``, which shirudo carried
  until bpf-next took it. Without it, a kernel whose functions can start
  at an odd address, such as one built with gcc 13 and
  ``CONFIG_CC_OPTIMIZE_FOR_SIZE=y``, can crash when a BPF trampoline is
  updated. :doc:`/operate/plan/system-requirements` says which
  kernels need it.
- The ``kernel-cve`` detectors define ``__TARGET_ARCH_x86`` for their
  ``kprobe`` programs and load on x86-64 only.

arm64
-----

- The arena tables of ``kernel-obs`` count and link their records with
  atomic fetch-and-add and compare-and-exchange on arena memory. The arm64
  JIT translates those only with the LSE atomics of ARMv8.1, so the
  package does not load on ARMv8.0 cores such as Cortex-A53 and
  Cortex-A72.
- A ``kprobe`` on a function's entry goes through a breakpoint exception
  rather than ftrace, because arm64 has no kprobes on ftrace.

riscv64
-------

- Nothing has booted a riscv64 target yet: there is no test VM, no CI
  run and no package. The build has riscv64 settings, but no one runs
  it.
- The toolchain hardening flags that x86-64 and arm64 get have no
  riscv64 counterpart in the build.
- All of shirudo's enforcement attaches through BPF trampolines. On
  riscv64 the kernel reaches a trampoline on a function that ftrace
  manages only through ftrace call ops, and it leaves call ops out of a
  kernel built with ``CONFIG_CFI``. Such a kernel refuses the attach
  with ``ENOTSUPP``, so ``init`` cannot bring enforcement up. This is a
  reading of the kernel source.
- The riscv64 JIT supports arenas only when the CPU has the Zacas
  extension and the kernel is built with ``CONFIG_RISCV_ISA_ZACAS``: the
  arena allocator needs a 128-bit compare-and-exchange, and so does
  compare-and-exchange on arena memory. ``kernel-obs`` and every other
  upatch with an arena need it.
- The riscv64 JIT keeps BPF programs to 512 bytes of stack, where x86-64
  and arm64 allow 2 KiB, and supports neither BPF exceptions nor private
  stacks. Whether shirudo's own programs and ``kernel-obs`` stay within
  512 bytes has not been checked.

Open work
---------

shirudo
~~~~~~~

- Boot the test VM on an arm64 CI runner.
- Add riscv64 to the test VM in :src:`testing/vm/arch.sh`, and boot a
  first riscv64 target with a TPM.
- Build the target binary and the packages for arm64 and riscv64 in CI.
- Check that every library the target links builds and runs on
  riscv64, LuaJIT included.
- Check the BPF stack use of shirudo's programs and of ``kernel-obs``
  against the 512 bytes of riscv64.
- Let ``kprobe`` upatches build for more than one architecture.
  ``shirudo build`` passes no ``__TARGET_ARCH_*`` define, so the source
  picks one, as the ``kernel-cve`` detectors pick x86-64.

Linux kernel
~~~~~~~~~~~~

- Get the remaining kernel changes upstream. The kernel project
  maintains them; :doc:`/internals/kernel-patches` describes each.
- riscv64: BPF trampolines on a kernel built with ``CONFIG_CFI``.
- riscv64: arenas on CPUs without Zacas.
- riscv64: large stacks, exceptions and private stacks in the BPF JIT.
- arm64: arena atomics on ARMv8.0 CPUs without LSE atomics.

Related
-------

- :doc:`/operate/plan/system-requirements`
- :doc:`/operate/plan/scalability`
- :doc:`/contribute/testing/test-coverage`
- :doc:`/internals/kernel-patches`
