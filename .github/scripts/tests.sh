#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Authors of shirudo
#
# .github/scripts/tests.sh -- run every test as make tests does on a
# developer's host. setup makes the runner the VM host: KVM, the VM's
# packages, the kernel CI artifact, and
# the OpenSSL 3.5 toolchain from vm-toolchain.sh. run builds and runs the
# unit, ci-checks, functional and end2end tests, each family of target tests
# in a VM of its own, or one part of them: unit runs the unit and
# ci-checks tests, functional and end2end the tier of that name.
# functional-ci-N runs shard N of the functional tests.
# With VM=0, setup installs only host test dependencies using the kernel
# CI artifact's BTF, and run leaves out target VMs. CI supplies this artifact
# built from testing/kernel.
#
#   .github/scripts/tests.sh setup|run [unit|functional|functional-ci-[1-4]|end2end]
#
# Runs as a user with passwordless sudo, from the checkout.

set -eu

cd "$(git rev-parse --show-toplevel)"

kernel=artifacts/bpf-next-kernel-debs

# What the job log alone does not show: refusals by AppArmor, the passt
# helper libguestfs networks its appliance through, and, for each guest
# that did not pass, what it and the suites in it printed.
diagnose() {
	echo '::group::Diagnostics'
	sudo dmesg | grep 'apparmor="DENIED"' | tail -n 20 || :
	sudo journalctl -b --no-pager -t passt | tail -n 20 || :
	for vm in build/test-vm/vms/*; do
		[ "$(cat "$vm/result/status" 2>/dev/null)" != 0 ] || continue
		for log in "$vm/result/guest.log" "$vm/console.log"; do
			[ -f "$log" ] || continue
			echo "== $log"
			cat "$log"
		done
	done
	echo '::endgroup::'
}

restore_workspace_ownership() {
	sudo chown -R "$(id -u):$(id -g)" .
}

# Setup and production runs leave root's files behind.
finish() {
	status=$?
	restore_workspace_ownership || status=$?
	[ "$status" -eq 0 ] || [ "${VM:-1}" = 0 ] || diagnose
	exit "$status"
}

setup() {
	if [ "${VM:-1}" != 0 ]; then
		sudo rm -rf /opt/ghc /usr/local/lib/android /usr/share/dotnet
	fi

	if [ -z "${KERNEL_CI_ARTIFACT_DIR:-}" ]; then
		echo 'KERNEL_CI_ARTIFACT_DIR must name the downloaded CI kernel artifact' >&2
		exit 1
	fi
	testing/vm/kernel-artifact.sh stage "$KERNEL_CI_ARTIFACT_DIR" || exit 1

	# spatch opens libpython3.X.so by that name for the Python of its
	# rules, and only the -dev package installs it.
	set -- rpm coccinelle libpython3-dev
	if [ "${COVERAGE:-0}" = 1 ]; then
		set -- "$@" lcov
	fi
	if [ "${VM:-1}" != 0 ]; then
		set -- "$@" autoconf autoconf-archive automake cloud-image-utils \
			dracut-core file isc-dhcp-client libguestfs-tools libltdl-dev \
			libtool libzstd-dev qemu-system-x86 qemu-utils swtpm \
			swtpm-tools tpm2-tools libtss2-tcti-swtpm0t64
	fi
	mkdir -p build
	sudo BPF_VMLINUX_BTF="$PWD/$kernel/vmlinux.btf" \
		.github/scripts/vm-toolchain.sh "$@"

	# t0003 runs the kernel's checkpatch.pl, which check-style.sh fetches
	# into build/checkpatch/ on its first run; without it t0003 skips.
	sh .github/scripts/check-style.sh --types >/dev/null ||
		echo '::warning::no checkpatch.pl fetched; t0003 skips'

	if [ "${VM:-1}" != 0 ]; then
		# /dev/kvm belongs to root on the runner.
		echo 'KERNEL=="kvm", GROUP="kvm", MODE="0666", OPTIONS+="static_node=kvm"' |
			sudo tee /etc/udev/rules.d/99-kvm.rules >/dev/null
		sudo udevadm control --reload-rules
		sudo udevadm trigger --name-match=kvm

		# Ubuntu's dracut 060 looks for systemd-pcrphase, which systemd 255
		# calls systemd-pcrextend, and so leaves out the PCR phase
		# measurement shirudo's initrd needs.
		if [ ! -e /usr/lib/systemd/systemd-pcrphase ]; then
			sudo ln -s systemd-pcrextend /usr/lib/systemd/systemd-pcrphase
		fi

		# libguestfs networks the appliance through passt. Ubuntu's AppArmor
		# profile for passt refuses the socket libguestfs asks for under
		# XDG_RUNTIME_DIR, and without that profile Ubuntu's restriction of
		# unprivileged user namespaces keeps passt from sandboxing itself.
		# The runner is discarded after the job, so lift both.
		apparmor=/sys/kernel/security/apparmor
		if sudo grep -q '^passt ' "$apparmor/profiles" 2>/dev/null; then
			printf passt | sudo tee "$apparmor/.remove" >/dev/null
		fi
		if [ -e /proc/sys/kernel/apparmor_restrict_unprivileged_userns ]; then
			sudo sysctl -q -w kernel.apparmor_restrict_unprivileged_userns=0
		fi
	fi
}

case "${1:-}" in
setup|run) ;;
*)
	echo "usage: $0 setup|run [unit|functional|functional-ci-[1-4]|end2end]" >&2
	exit 2
	;;
esac

case "${2:-}" in
'') goals=tests ;;
unit) goals='-C testing unit ci-checks' ;;
functional|end2end) goals="-C testing $2" ;;
# A shard boots two families' VMs at once, of 4 GB each on a runner of
# 16, and prints each family's output whole, once it is done.
functional-ci-[1-4]) goals="-C testing -k -j2 -Otarget $2" ;;
*)
	echo "usage: $0 setup|run [unit|functional|functional-ci-[1-4]|end2end]" >&2
	exit 2
	;;
esac

trap finish EXIT

restore_workspace_ownership

if [ "$1" = setup ]; then
	setup
	exit 0
fi

# shellcheck source=/dev/null
. build/vm-toolchain.env

export BPF_VMLINUX_BTF="$PWD/$kernel/vmlinux.btf"

# A guest that boots runs the suite in minutes; one that hangs, in
# emergency mode for instance, would otherwise hold the job for an hour.
export TEST_VM_TIMEOUT=900

sudo prlimit --pid "$$" --memlock=unlimited:unlimited

# sudo drops LD_LIBRARY_PATH even with -E and replaces PATH with its
# secure_path, and the OpenSSL 3.5 build needs both: for the openssl the
# config probes run and for every shirudo binary the tests run here.
# shellcheck disable=SC2086
sudo -E env PATH="$PATH" LD_LIBRARY_PATH="$LD_LIBRARY_PATH" \
	COVERAGE="${COVERAGE:-0}" SHIRUDO_SKIP_TREE_CHECKS="${SHIRUDO_SKIP_TREE_CHECKS:-0}" \
	make VM="${VM:-1}" $goals
