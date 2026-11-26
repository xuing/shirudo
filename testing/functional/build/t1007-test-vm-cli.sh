#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Authors of shirudo

cd "$(dirname "$0")/../.."
. ./test-lib.sh

RUNNER=vm/run.sh
WORK=$(mktemp -d)
# A test run boots one family; the checks below stop before it boots.
TEST_VM_SUITE=upatch
export TEST_VM_SUITE
trap 'rm -rf "$WORK"' EXIT

test_expect_success 'test-vm rejects a missing local kernel before boot' '
	! TEST_VM_WORK_DIR="$WORK/missing" \
		TEST_VM_KERNEL="$WORK/no-bzImage" "$RUNNER" \
		>"$WORK/missing.out" 2>&1 &&
	grep -q "kernel image not found" "$WORK/missing.out"
'

test_expect_success 'register protocols run only in an isolated pre-init test VM' '
	! TEST_VM_SUITE=register VM_MODE=test TEST_VM_INITRD=0 \
		TEST_VM_WORK_DIR="$WORK/register" TEST_VM_KERNEL="$WORK/no-bzImage" \
		"$RUNNER" >"$WORK/register.out" 2>&1 &&
	grep -q "kernel image not found" "$WORK/register.out" &&
	! TEST_VM_SUITE=register VM_MODE=interactive TEST_VM_INITRD=0 \
		"$RUNNER" >"$WORK/register-interactive.out" 2>&1 &&
	grep -q "register suite requires test mode" "$WORK/register-interactive.out" &&
	! TEST_VM_SUITE=register VM_MODE=test TEST_VM_INITRD=1 \
		"$RUNNER" >"$WORK/register-initrd.out" 2>&1 &&
	grep -q "register suite requires test mode" "$WORK/register-initrd.out"
'

test_expect_success 'node mode boots only a core or edge node of the end2end suite' '
	! VM_MODE=node TEST_VM_WORK_DIR="$WORK/node" \
		"$RUNNER" >"$WORK/node-upatch.out" 2>&1 &&
	grep -q "node mode boots a node of the end2end suite only" \
		"$WORK/node-upatch.out" &&
	! TEST_VM_SUITE=end2end VM_MODE=node TEST_VM_NODE_ROLE=gateway \
		TEST_VM_WORK_DIR="$WORK/node" "$RUNNER" \
		>"$WORK/node-role.out" 2>&1 &&
	grep -q "TEST_VM_NODE_ROLE must be .core. or .edge." "$WORK/node-role.out" &&
	! TEST_VM_SUITE=end2end VM_MODE=node TEST_VM_NODE_ROLE=edge \
		TEST_VM_WORK_DIR="$WORK/node" \
		TEST_VM_KERNEL="$WORK/no-bzImage" "$RUNNER" \
		>"$WORK/node-end2end.out" 2>&1 &&
	grep -q "kernel image not found" "$WORK/node-end2end.out" &&
	grep -Fq "\$(call run-target-vm,end2end,\$(if \$(VM_NAME),\$(VM_NAME)-end2end-\$(END2END_NODE)),1,node)" \
		../testing/Makefile &&
	grep -Fq "TEST_VM_NODE_ROLE=\$(if \$(filter edge,\$(END2END_NODE)),edge,core)" \
		../testing/Makefile &&
	grep -Fq "export TEST_VM_NODE_ROLE=" vm/run.sh &&
	grep -Fq "\"\$REPO_ROOT/testing/vm/tpm-builder.sh\" \"\$RUN_DIR/tpm\" \"\$RUN_DIR/tpm-names\"" \
		vm/run.sh &&
	grep -Fq "\"\$RUN_DIR/ek-ca.pem\"" vm/run.sh &&
	grep -Fq "tpm2_createprimary:tpm2-tools:tpm2-tools" vm/run.sh &&
	grep -Fq "if [[ \"\$VM_MODE\" == node ]]" vm/guest.sh &&
	grep -Fq "image update \"/var/lib/shirudo/images/config-\${TEST_VM_NODE_ROLE}\"" \
		vm/guest.sh
'

test_expect_success 'test-vm requires a SHA-256 for a remote kernel' '
	! TEST_VM_WORK_DIR="$WORK/no-sha" \
		TEST_VM_KERNEL_URL=https://example.invalid/bzImage "$RUNNER" \
		>"$WORK/no-sha.out" 2>&1 &&
	grep -q "requires a 64-character TEST_VM_KERNEL_SHA256" \
		"$WORK/no-sha.out"
'

test_expect_success 'test-vm rejects conflicting kernel selectors' '
	! TEST_VM_WORK_DIR="$WORK/conflict" \
		TEST_VM_KERNEL="$WORK/bzImage" \
		TEST_VM_KERNEL_URL=https://example.invalid/bzImage \
		TEST_VM_KERNEL_SHA256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
		"$RUNNER" >"$WORK/conflict.out" 2>&1 &&
	grep -q "TEST_VM_KERNEL and TEST_VM_KERNEL_URL are mutually exclusive" \
		"$WORK/conflict.out"
'

test_expect_success 'test-vm prints an install command for missing dependencies' '
	mkdir "$WORK/fake-bin" &&
	ln -s /bin/bash "$WORK/fake-bin/bash" &&
	ln -s /usr/bin/dirname "$WORK/fake-bin/dirname" &&
	for command_name in curl sha256sum awk qemu-system-x86_64 qemu-img \
		swtpm timeout tee dracut lsinitrd file
	do
		ln -s /bin/true "$WORK/fake-bin/$command_name" || return 1
	done &&
	printf kernel >"$WORK/bzImage" &&
	! PATH="$WORK/fake-bin" TEST_VM_ARCH=x86_64 TEST_VM_HOST_PKG=apt \
		TEST_VM_WORK_DIR="$WORK/missing-dependency" \
		TEST_VM_KERNEL="$WORK/bzImage" "$RUNNER" \
		>"$WORK/missing-dependency.out" 2>&1 &&
	grep -q "missing host commands: cloud-localds" \
		"$WORK/missing-dependency.out" &&
	grep -q "sudo apt-get install -y --no-install-recommends cloud-image-utils" \
		"$WORK/missing-dependency.out"
'

test_expect_success 'test-vm requires the QEMU emulator of the host architecture' '
	mkdir "$WORK/arm-bin" &&
	ln -s /bin/bash "$WORK/arm-bin/bash" &&
	ln -s /usr/bin/dirname "$WORK/arm-bin/dirname" &&
	for command_name in curl sha256sum awk qemu-system-x86_64 qemu-img \
		swtpm timeout tee dracut lsinitrd file
	do
		ln -s /bin/true "$WORK/arm-bin/$command_name" || return 1
	done &&
	printf kernel >"$WORK/Image" &&
	! PATH="$WORK/arm-bin" TEST_VM_ARCH=aarch64 TEST_VM_HOST_PKG=apt \
		TEST_VM_WORK_DIR="$WORK/missing-arm-qemu" \
		TEST_VM_KERNEL="$WORK/Image" "$RUNNER" \
		>"$WORK/missing-arm-qemu.out" 2>&1 &&
	grep -q "missing host commands: qemu-system-aarch64" \
		"$WORK/missing-arm-qemu.out" &&
	grep -q "qemu-system-arm" "$WORK/missing-arm-qemu.out"
'

test_expect_success 'test-vm prints dnf package names on a Fedora or RHEL host' '
	! PATH="$WORK/fake-bin" TEST_VM_ARCH=x86_64 TEST_VM_HOST_PKG=dnf \
		TEST_VM_WORK_DIR="$WORK/missing-dependency-dnf" \
		TEST_VM_KERNEL="$WORK/bzImage" "$RUNNER" \
		>"$WORK/missing-dependency-dnf.out" 2>&1 &&
	grep -q "sudo dnf install -y xorriso" "$WORK/missing-dependency-dnf.out" &&
	grep -q "openssh-clients" "$WORK/missing-dependency-dnf.out" &&
	! grep -q "apt-get" "$WORK/missing-dependency-dnf.out" &&
	! PATH="$WORK/arm-bin" TEST_VM_ARCH=aarch64 TEST_VM_HOST_PKG=dnf \
		TEST_VM_WORK_DIR="$WORK/missing-arm-qemu-dnf" \
		TEST_VM_KERNEL="$WORK/Image" "$RUNNER" \
		>"$WORK/missing-arm-qemu-dnf.out" 2>&1 &&
	grep -q "qemu-system-aarch64-core" "$WORK/missing-arm-qemu-dnf.out"
'

test_expect_success 'TEST_VM_QEMU names another emulator' '
	mkdir "$WORK/kvm-bin" &&
	ln -s /bin/bash "$WORK/kvm-bin/bash" &&
	ln -s /usr/bin/dirname "$WORK/kvm-bin/dirname" &&
	for command_name in curl sha256sum awk qemu-kvm qemu-img swtpm \
		cloud-localds timeout tee flock ssh-keygen ss dracut lsinitrd file
	do
		ln -s /bin/true "$WORK/kvm-bin/$command_name" || return 1
	done &&
	! PATH="$WORK/kvm-bin" TEST_VM_ARCH=x86_64 \
		TEST_VM_WORK_DIR="$WORK/no-qemu" \
		TEST_VM_KERNEL="$WORK/bzImage" "$RUNNER" \
		>"$WORK/no-qemu.out" 2>&1 &&
	grep -q "missing host commands: qemu-system-x86_64" "$WORK/no-qemu.out" &&
	! PATH="$WORK/kvm-bin" TEST_VM_ARCH=x86_64 TEST_VM_QEMU=qemu-kvm \
		TEST_VM_WORK_DIR="$WORK/qemu-kvm" \
		TEST_VM_KERNEL="$WORK/bzImage" "$RUNNER" \
		>"$WORK/qemu-kvm.out" 2>&1 &&
	! grep -q "missing host commands" "$WORK/qemu-kvm.out" &&
	grep -q "host VM bundle is missing" "$WORK/qemu-kvm.out"
'

test_expect_success 'test-vm writes the cloud-init seed with an ISO writer' '
	sed -n "/^seed_tool()/,/^}/p;/^make_seed()/,/^}/p" "$RUNNER" \
		>"$WORK/seed.sh" &&
	for writer in genisoimage xorriso
	do
		rm -rf "$WORK/iso-bin" &&
		mkdir "$WORK/iso-bin" &&
		printf "%s\n" "#!/bin/sh" "printf \"%s\\n\" \"\$@\" >\"\$SEED\"" \
			>"$WORK/iso-bin/$writer" &&
		chmod +x "$WORK/iso-bin/$writer" &&
		PATH="$WORK/iso-bin" SEED="$WORK/seed-$writer" \
			USER_DATA=/r/user-data META_DATA=/r/meta-data \
			NETWORK_CONFIG=/r/network-config /bin/bash -c \
			". \"$WORK/seed.sh\"; make_seed" &&
		grep -qx cidata "$WORK/seed-$writer" &&
		grep -qx /r/user-data "$WORK/seed-$writer" &&
		grep -qx /r/meta-data "$WORK/seed-$writer" &&
		grep -qx /r/network-config "$WORK/seed-$writer" || return 1
	done &&
	grep -qx -- "-as" "$WORK/seed-xorriso" &&
	! grep -qx -- "-as" "$WORK/seed-genisoimage"
'

test_expect_success 'an ISO writer stands in for cloud-localds' '
	rm "$WORK/kvm-bin/cloud-localds" &&
	ln -s /bin/true "$WORK/kvm-bin/genisoimage" &&
	! PATH="$WORK/kvm-bin" TEST_VM_ARCH=x86_64 TEST_VM_QEMU=qemu-kvm \
		TEST_VM_WORK_DIR="$WORK/iso-seed" \
		TEST_VM_KERNEL="$WORK/bzImage" "$RUNNER" \
		>"$WORK/iso-seed.out" 2>&1 &&
	! grep -q "missing host commands" "$WORK/iso-seed.out" &&
	grep -q "host VM bundle is missing" "$WORK/iso-seed.out"
'

test_expect_success 'the host package manager is detected from os-release' '
	sed "s|/etc/os-release|$WORK/os-release|g" vm/arch.sh \
		>"$WORK/arch-os.sh" &&
	host_pkg() {
		printf "%s\n" "$@" >"$WORK/os-release" &&
		(unset TEST_VM_HOST_PKG; . "$WORK/arch-os.sh"; echo "$TEST_VM_HOST_PKG")
	} &&
	test "$(host_pkg ID=fedora)" = dnf &&
	test "$(host_pkg ID=centos "ID_LIKE=\"rhel fedora\"")" = dnf &&
	test "$(host_pkg ID=rocky "ID_LIKE=\"rhel centos fedora\"")" = dnf &&
	test "$(host_pkg ID=ubuntu ID_LIKE=debian)" = apt &&
	test "$(host_pkg ID=debian)" = apt &&
	(
		TEST_VM_HOST_PKG=dnf &&
		. vm/arch.sh &&
		test "$TEST_VM_HOST_PKG_FORMAT" = rpm &&
		test "$(test_vm_install_cmd a b)" = "sudo dnf install -y a b"
	)
'

test_expect_success 'the bundle and runtime scripts print hints for the host package manager' '
	mkdir "$WORK/bundle-bin" &&
	ln -s /usr/bin/dirname "$WORK/bundle-bin/dirname" &&
	ln -s /usr/bin/id "$WORK/bundle-bin/id" &&
	ln -s /usr/bin/uname "$WORK/bundle-bin/uname" &&
	for command_name in flock curl sha256sum awk qemu-img
	do
		ln -s /bin/true "$WORK/bundle-bin/$command_name" || return 1
	done &&
	! PATH="$WORK/bundle-bin" TEST_VM_HOST_PKG=dnf \
		TEST_VM_WORK_DIR="$WORK/bundle-dnf" /bin/bash \
		vm/build-bundle.sh >"$WORK/bundle-dnf.out" 2>&1 &&
	grep -q "virt-customize (install with: sudo dnf install -y guestfs-tools)" \
		"$WORK/bundle-dnf.out" &&
	printf rootfs >"$WORK/hint-rootfs" &&
	! PATH="$WORK/bundle-bin" TEST_VM_HOST_PKG=dnf /bin/bash \
		vm/prepare-runtime.sh --rootfs "$WORK/hint-rootfs" \
		--cache-dir "$WORK/hint-cache" \
		--package-file vm/runtime-packages \
		--runtime-key hint --key-output "$WORK/hint-key" \
		>"$WORK/runtime-dnf.out" 2>&1 &&
	grep -q "virt-customize is required; install it with: sudo dnf install -y guestfs-tools" \
		"$WORK/runtime-dnf.out"
'

test_expect_success 'the bundle wants a DHCP client for the appliance on a Debian host' '
	mkdir "$WORK/dhcp-bin" &&
	ln -s /usr/bin/dirname "$WORK/dhcp-bin/dirname" &&
	ln -s /usr/bin/id "$WORK/dhcp-bin/id" &&
	ln -s /usr/bin/uname "$WORK/dhcp-bin/uname" &&
	for command_name in flock curl sha256sum awk qemu-img virt-customize \
		openssl gzip depmod
	do
		ln -s /bin/true "$WORK/dhcp-bin/$command_name" || return 1
	done &&
	! PATH="$WORK/dhcp-bin" TEST_VM_HOST_PKG=apt \
		TEST_VM_WORK_DIR="$WORK/bundle-dhcp" /bin/bash \
		vm/build-bundle.sh >"$WORK/bundle-dhcp.out" 2>&1 &&
	grep -q "missing host command: dhclient (install with: sudo apt-get install -y --no-install-recommends isc-dhcp-client)" \
		"$WORK/bundle-dhcp.out"
'

test_expect_success 'the runtime image is built with the direct libguestfs backend and the VM emulator' '
	mkdir -p "$WORK/gf-bin" &&
	printf "%s\n" "#!/bin/sh" "exit 0" >"$WORK/gf-bin/emulator" &&
	printf "%s\n" "#!/bin/sh" \
		"echo \"\$LIBGUESTFS_BACKEND \${LIBGUESTFS_HV-unset}\" >\"\$GF_OUT\"" \
		>"$WORK/gf-bin/virt-customize" &&
	printf "%s\n" "#!/bin/sh" \
		"[ \"\$1\" = create ] || exit 0" \
		"for a; do last=\$a; done; : >\"\$last\"" >"$WORK/gf-bin/qemu-img" &&
	chmod +x "$WORK/gf-bin/emulator" "$WORK/gf-bin/virt-customize" \
		"$WORK/gf-bin/qemu-img" &&
	printf rootfs >"$WORK/gf-rootfs" &&
	guestfs_env() {
		rm -rf "$WORK/gf-cache" &&
		env "$@" PATH="$WORK/gf-bin:$PATH" GF_OUT="$WORK/gf-out" \
			TMPDIR="$WORK" LIBGUESTFS_CACHEDIR="$WORK/gf-cache" \
			vm/prepare-runtime.sh \
			--rootfs "$WORK/gf-rootfs" --cache-dir "$WORK/gf-cache/img" \
			--package-file vm/runtime-packages \
			--runtime-key gf --key-output "$WORK/gf-cache/key" \
			>/dev/null 2>&1 &&
		cat "$WORK/gf-out"
	} &&
	test "$(guestfs_env TEST_VM_QEMU="$WORK/gf-bin/emulator")" = \
		"direct $WORK/gf-bin/emulator" &&
	test "$(guestfs_env TEST_VM_QEMU="$WORK/gf-bin/emulator" \
		LIBGUESTFS_BACKEND=libvirt LIBGUESTFS_HV=/chosen/qemu)" = \
		"libvirt /chosen/qemu" &&
	test "$(guestfs_env TEST_VM_QEMU="$WORK/gf-bin/none")" = "direct unset"
'

# Stand-ins for the tools vm/prepare-runtime.sh calls; every command it
# runs is recorded, so the tests below read what it would have done.
mkdir -p "$WORK/dns-bin" "$WORK/dns-cache"
printf "%s\n" "#!/bin/sh" \
	"printf \"%s\\n\" \"\$@\" >\"\$GF_ARGS\"" \
	"for a in \"\$@\"; do case \$a in" \
	"*:/root/shirudo-nameservers) cp \"\${a%%:/root/shirudo-nameservers}\" \"\$GF_NS\" ;;" \
	"esac; done" >"$WORK/dns-bin/virt-customize"
printf "%s\n" "#!/bin/sh" \
	"if [ \"\$1\" = create ]; then for a in \"\$@\"; do last=\$a; done; : >\"\$last\"; fi" \
	>"$WORK/dns-bin/qemu-img"
chmod +x "$WORK/dns-bin/virt-customize" "$WORK/dns-bin/qemu-img"
printf rootfs >"$WORK/dns-rootfs"
printf "%s\n" "search example.com" "nameserver 127.0.0.53" \
	"nameserver 2001:db8::53" "nameserver ::1" \
	"nameserver fe80::1%eth0" "nameserver 192.0.2.53" \
	>"$WORK/dns-resolv.conf"

# Run vm/prepare-runtime.sh against stand-ins for the tools it needs:
# run_dns RESOLV_CONF [VAR=value...].
run_dns() {
	resolv=$1
	shift
	rm -f "$WORK/dns-cache/img/dns-test.qcow2" &&
	env -u http_proxy -u HTTP_PROXY -u https_proxy -u HTTPS_PROXY \
		-u TEST_VM_APT_PROXY "$@" \
		PATH="$WORK/dns-bin:$PATH" TEST_VM_ARCH=x86_64 TMPDIR="$WORK" \
		GF_ARGS="$WORK/dns-args" GF_NS="$WORK/dns-ns" \
		LIBGUESTFS_CACHEDIR="$WORK/dns-cache" \
		TEST_VM_RESOLV_CONF="$resolv" \
		vm/prepare-runtime.sh \
		--rootfs "$WORK/dns-rootfs" --cache-dir "$WORK/dns-cache/img" \
		--package-file vm/runtime-packages \
		--runtime-key dns-test --key-output "$WORK/dns-cache/key" \
		>"$WORK/dns-run.out" 2>&1
}

test_expect_success 'the runtime image gives the appliance the host resolvers in the apt command' '
	run_dns "$WORK/dns-resolv.conf" &&
	printf "%s\n" "nameserver 2001:db8::53" "nameserver 192.0.2.53" \
		>"$WORK/dns-expect" &&
	cmp "$WORK/dns-expect" "$WORK/dns-ns" &&
	! grep -qx -- "--install" "$WORK/dns-args" &&
	grep -q "cat /root/shirudo-nameservers >>/etc/resolv.conf" "$WORK/dns-args" &&
	grep -q "apt-get \$apt_opts update" "$WORK/dns-args" &&
	grep -q "apt-get \$apt_opts install ca-certificates default-jre-headless e2fsprogs keyutils" "$WORK/dns-args" &&
	grep -q "ripgrep rsync" "$WORK/dns-args" &&
	run_dns "$WORK/no-such-resolv.conf" &&
	! test -s "$WORK/dns-ns" &&
	! grep -q "Acquire::http::Proxy" "$WORK/dns-args"
'

test_expect_success 'the runtime image passes the caller proxy to apt in the appliance' '
	run_dns "$WORK/dns-resolv.conf" http_proxy=http://proxy.example:8080 &&
	grep -q "Acquire::http::Proxy=http://proxy.example:8080" "$WORK/dns-args" &&
	grep -q "Acquire::https::Proxy=http://proxy.example:8080" "$WORK/dns-args" &&
	run_dns "$WORK/dns-resolv.conf" http_proxy=http://a.example:1 \
		https_proxy=http://b.example:2 &&
	grep -q "Acquire::http::Proxy=http://a.example:1" "$WORK/dns-args" &&
	grep -q "Acquire::https::Proxy=http://b.example:2" "$WORK/dns-args" &&
	run_dns "$WORK/dns-resolv.conf" http_proxy=http://a.example:1 \
		TEST_VM_APT_PROXY=http://override.example:3 &&
	grep -q "Acquire::http::Proxy=http://override.example:3" "$WORK/dns-args" &&
	! grep -q "a.example" "$WORK/dns-args" &&
	! run_dns "$WORK/dns-resolv.conf" "http_proxy=http://x;touch /tmp/pwned" &&
	! run_dns "$WORK/dns-resolv.conf" "TEST_VM_APT_PROXY=ftp://x.example" &&
	grep -q "plain http" "$WORK/dns-run.out"
'

test_expect_success 'a failed runtime image shows what apt could not fetch' '
	mkdir -p "$WORK/aptfail-bin" &&
	printf "%s\n" "#!/bin/sh" \
		"echo \"Err:1 http://archive.ubuntu.com/ubuntu resolute InRelease\"" \
		"echo \"  Temporary failure resolving archive.ubuntu.com\"" \
		"echo \"E: Unable to locate package ripgrep\"" \
		"exit 1" >"$WORK/aptfail-bin/virt-customize" &&
	chmod +x "$WORK/aptfail-bin/virt-customize" &&
	! env PATH="$WORK/aptfail-bin:$WORK/dns-bin:$PATH" TMPDIR="$WORK" \
		LIBGUESTFS_CACHEDIR="$WORK/aptfail-cache" \
		vm/prepare-runtime.sh \
		--rootfs "$WORK/dns-rootfs" --cache-dir "$WORK/aptfail-cache/img" \
		--package-file vm/runtime-packages \
		--runtime-key aptfail --key-output "$WORK/aptfail-cache/key" \
		>"$WORK/aptfail.out" 2>&1 &&
	grep -q "apt could not fetch" "$WORK/aptfail.out" &&
	grep -q "Temporary failure resolving archive.ubuntu.com" "$WORK/aptfail.out"
'

test_expect_success 'as root the runtime image is built without passt' '
	mkdir -p "$WORK/passt-bin" &&
	printf "%s\n" "#!/bin/sh" "exit 0" >"$WORK/passt-bin/passt" &&
	printf "%s\n" "#!/bin/sh" \
		"passt --help >/dev/null 2>&1; echo \$? >\"\$GF_OUT\"" \
		>"$WORK/passt-bin/virt-customize" &&
	chmod +x "$WORK/passt-bin/passt" "$WORK/passt-bin/virt-customize" &&
	env PATH="$WORK/passt-bin:$WORK/dns-bin:$PATH" GF_OUT="$WORK/passt-out" \
		TMPDIR="$WORK" LIBGUESTFS_CACHEDIR="$WORK/passt-cache" \
		vm/prepare-runtime.sh \
		--rootfs "$WORK/dns-rootfs" --cache-dir "$WORK/passt-cache/img" \
		--package-file vm/runtime-packages \
		--runtime-key passt --key-output "$WORK/passt-cache/key" \
		>/dev/null 2>&1 &&
	if [ "$(id -u)" = 0 ]; then
		test "$(cat "$WORK/passt-out")" = 127
	else
		test "$(cat "$WORK/passt-out")" = 0
	fi &&
	! ls -a "$WORK/passt-cache/img" | grep -q no-passt
'

test_expect_success 'the kernel package format follows the host package manager' '
	printf "print:\n\t@echo \$(PACKAGE_FORMAT)\n" >"$WORK/print.mk" &&
	format() {
		make -s -C .. -f testing/Makefile -f "$WORK/print.mk" print "$@"
	} &&
	test "$(TEST_VM_HOST_PKG=dnf format)" = rpm &&
	test "$(TEST_VM_HOST_PKG=apt format)" = deb &&
	test "$(TEST_VM_HOST_PKG=dnf format PACKAGE_FORMAT=deb)" = deb
'

test_expect_success 'test-vm boots arm64 on the virt machine with PCI disks' '
	grep -q "virt,gic-version=host" "$RUNNER" &&
	grep -q "virtio-blk-pci,drive=rootdisk" "$RUNNER" &&
	grep -q "tpm-tis-device,tpmdev=tpm0" "$RUNNER" &&
	! grep -q "ttyS0" "$RUNNER"
'

test_expect_success 'test-vm reads the release of an arm64 image from its module tree' '
	sed -n "/^kernel_release_of()/,/^}/p" "$RUNNER" >"$WORK/release.sh" &&
	mkdir -p "$WORK/art/lib/modules/7.9.9-test" &&
	printf image >"$WORK/art/Image" &&
	release() {
		KERNEL_ARTIFACT_DIR=$1 bash -c \
			". \"$WORK/release.sh\"; kernel_release_of \"$WORK/art/Image\""
	} &&
	test "$(release "$WORK/art")" = 7.9.9-test &&
	! release "" >/dev/null 2>&1 &&
	mkdir "$WORK/art/lib/modules/7.9.9-other" &&
	! release "$WORK/art" >/dev/null 2>&1
'

test_expect_success 'test-vm selects the root partition without an initramfs' '
	grep -q "root=/dev/vda1 rootwait rw" "$RUNNER" &&
	! grep -q "root=LABEL=cloudimg-rootfs" "$RUNNER"
'

test_expect_success 'test-vm guest uses prebuilt target fixtures' '
	grep -q "SHIRUDO_TEST_FIXTURES_DIR" vm/guest.sh &&
	grep -q "run-target-tests.sh" vm/guest.sh &&
	! grep -q "SHIRUDO_BUILD_BIN=" vm/guest.sh &&
	grep -q "prepared Ubuntu runtime image" vm/guest.sh &&
	! grep -q "apt-get install" vm/guest.sh &&
	test -x run-target-tests.sh &&
	test -x functional/upatch/t3101-target-fixtures.sh &&
	! grep -q "libluajit-5.1-dev" vm/guest.sh
'

test_expect_success 'the Ubuntu image and packages are those of the host architecture' '
	(
		TEST_VM_ARCH=x86_64 &&
		. vm/arch.sh &&
		test "$TEST_VM_ARCH_DEB" = amd64 &&
		test "$TEST_VM_ARCH_MIRROR" = https://archive.ubuntu.com/ubuntu
	) &&
	(
		TEST_VM_ARCH=aarch64 &&
		. vm/arch.sh &&
		test "$TEST_VM_ARCH_DEB" = arm64 &&
		test "$TEST_VM_ARCH_MIRROR" = https://ports.ubuntu.com/ubuntu-ports
	) &&
	! grep -q "amd64" vm/run.sh vm/build-bundle.sh &&
	! grep -q "x86_64\|archive.ubuntu.com" vm/build-bundle.sh
'

test_expect_success 'test-vm imports the host-built payload' '
	grep -q "TEST_VM_BUNDLE_DIR" ../testing/Makefile &&
	grep -q "test-vm-bundle" ../testing/Makefile &&
	grep -q "vm/build-bundle.sh" ../testing/Makefile &&
	grep -q "vm/prepare-runtime.sh" ../testing/Makefile &&
	grep -q "virt-customize" vm/build-bundle.sh &&
	grep -q "mount_tag=shirudo-bundle" vm/run.sh &&
	grep -q "importing host-built shirudo payload" \
		vm/guest.sh &&
	grep -q "mountpoint -q /run/shirudo/runtime" vm/guest.sh &&
	! grep -q "vmlinux.h" vm/guest.sh &&
	! grep -q "shirudo-build" vm/guest.sh &&
	! grep -Fq "make \"\${BPF_MAKE_ARGS[@]}\" check" \
		vm/guest.sh &&
	grep -Fq "LIBBPF_VENDOR    := vendor/libbpf" ../Makefile.shirudo &&
	grep -Fq "\$(LIBBPF_A)" ../Makefile.shirudo &&
	grep -Fq "VMLINUX_GEN      := tools/gen-vmlinux-h/gen-vmlinux-h" \
		../Makefile.shirudo
'
	test_expect_success 'test-vm bundle stamp controls incremental rebuilds' '
	grep -q "TEST_VM_BUNDLE_STAMP" ../testing/Makefile &&
	grep -q "TEST_VM_BUNDLE_INPUTS" ../testing/Makefile &&
	grep -q "bundle_is_current" vm/build-bundle.sh &&
	grep -Fq "touch -d \"@\$STAMP_TIME\" \"\$STAMP_FILE\"" vm/build-bundle.sh &&
	make -s -C .. -f testing/Makefile \
		--eval "bundle-inputs: ; @echo \$(TEST_VM_BUNDLE_INPUTS)" \
		bundle-inputs >"$WORK/bundle-inputs.out" &&
	grep -q "/util/upatch\.c" "$WORK/bundle-inputs.out" &&
	! grep -q "/util/version_id\.c" "$WORK/bundle-inputs.out" &&
	grep -q "flock 9" ../testing/Makefile &&
	grep -q "bundle_dir.lock" ../testing/Makefile &&
	! grep -Fq "rm -rf \"\$\$bundle_dir.lock\"" ../testing/Makefile &&
	grep -Fq "\$\$bundle_dir" ../testing/Makefile
'

test_expect_success 'the bundle builds in the build container unless BUILD_CONTAINER=0' '
	image=$(../testing/container/run.sh --image) &&
	expr "$image" : "shirudo-build:[0-9a-f]\{16\}$" >/dev/null &&
	! CONTAINER=/bin/false ../testing/container/run.sh -v relative -- true \
		>"$WORK/container-v.out" 2>&1 &&
	grep -q -- "-v takes an absolute directory" "$WORK/container-v.out" &&
	! CONTAINER=/bin/false ../testing/container/run.sh \
		>"$WORK/container-none.out" 2>&1 &&
	grep -q "no command to run" "$WORK/container-none.out" &&
	make -n -C .. -f testing/Makefile test-vm-bundle \
		TEST_VM_WORK_DIR="$WORK/container-bundle" \
		>"$WORK/container-make.out" 2>&1 &&
	grep -q "BUILD_CONTAINER=\"1\"" "$WORK/container-make.out" &&
	grep -q "testing/container/Containerfile" "$WORK/container-make.out" &&
	! grep -q "/config\.mk" "$WORK/container-make.out" &&
	make -n -C .. -f testing/Makefile test-vm-bundle BUILD_CONTAINER=0 \
		TEST_VM_WORK_DIR="$WORK/host-bundle" >"$WORK/host-make.out" 2>&1 &&
	grep -q "BUILD_CONTAINER=\"0\"" "$WORK/host-make.out" &&
	grep -q "/config\.mk" "$WORK/host-make.out" &&
	grep -q "build-bundle-payload.sh\" --from-copy" vm/build-bundle.sh &&
	grep -q "list-source.sh" vm/build-bundle.sh vm/run.sh &&
	! grep -q "ls-files" vm/build-bundle-payload.sh vm/guest.sh &&
	if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
		vm/list-source.sh "$WORK/source-files" &&
		tr "\\0" "\\n" <"$WORK/source-files" >"$WORK/source-list" &&
		grep -qx "testing/vm/list-source.sh" "$WORK/source-list" &&
		! grep -q "^build/" "$WORK/source-list"
	fi
'

	test_expect_success 'test-vm summary records failed test names' '
	grep -q "print_test_summary" vm/run.sh &&
	grep -q "exit \"\$FINAL_STATUS\"" vm/run.sh &&
	grep -q "failed tests:" vm/run.sh &&
	grep -q "VM_VERBOSE" ../testing/Makefile &&
	grep -q "summary_log" vm/run.sh &&
	grep -q "print_quiet_progress" vm/run.sh &&
	grep -q "stream_verbose_console" vm/run.sh &&
	grep -q "qemu.log\\\" 2>&1 &" vm/run.sh &&
	grep -q "SHIRUDO_TEST_FAILURES_FILE" vm/guest.sh &&
	grep -q "SHIRUDO_TEST_SUITE_FAILURES_FILE" vm/guest.sh &&
	grep -q "SHIRUDO_TEST_FAILURES_FILE" ../testing/test-lib.sh &&
	grep -q "SHIRUDO_TEST_SUITE_FAILURES_FILE" ../testing/run-tests.sh
'

test_expect_success 'test harness records a failed test title' '
	printf "%s\n" \
		"#!/bin/sh" \
		". \"\$PWD/test-lib.sh\"" \
		"test_expect_success \"synthetic failure\" \"false\"" \
		"test_done" >"$WORK/failing-suite.sh" &&
	! SHIRUDO_TEST_FAILURES_FILE="$WORK/failed-tests" \
		sh "$WORK/failing-suite.sh" >"$WORK/failing-suite.out" 2>&1 &&
	grep -Fq "test	$WORK/failing-suite.sh	synthetic failure" \
		"$WORK/failed-tests"
'

test_expect_success 'make -C testing vm and test-vm share named mode support' '
	grep -q "^[[:space:]]*vm:" ../testing/Makefile &&
	grep -q "VM_MODE=interactive" ../testing/Makefile &&
	grep -Fq "VM_MODE=\$(or \$(4),\$(if \$(filter \$(1),\$(VM_SERVE_SUITES)),serve,test))" \
		../testing/Makefile &&
	grep -Fq "VMS_DIR=\"\${VM_ROOT}/vms\"" vm/run.sh &&
	grep -Fq "mktemp -d \"\${VMS_DIR}/\${VM_MODE}\${VM_SUITE:+-\$VM_SUITE}-XXXXXX\"" \
		vm/run.sh &&
	grep -q "VM_TENANT" vm/run.sh &&
	grep -q "while :; do sleep 3600; done" vm/run.sh
'

test_expect_success 'serve mode runs the end-to-end target tests over SSH' '
	grep -q "^VM_SERVE_SUITES := end2end\$" ../testing/Makefile &&
	! VM_MODE=other "$RUNNER" >"$WORK/mode.out" 2>&1 &&
	grep -q "VM_MODE must be .interactive., .serve., .test. or .node." \
		"$WORK/mode.out" &&
	! VM_MODE=serve TEST_VM_SUITE= "$RUNNER" >"$WORK/serve-suite.out" 2>&1 &&
	grep -q "serve mode requires TEST_VM_SUITE" "$WORK/serve-suite.out" &&
	! TEST_VM_SUITE=register VM_MODE=serve TEST_VM_INITRD=0 \
		"$RUNNER" >"$WORK/serve-register.out" 2>&1 &&
	grep -q "register suite requires test mode" "$WORK/serve-register.out" &&
	grep -q "} >/etc/shirudo-test-vm.env" vm/guest.sh &&
	grep -Fq ". /etc/shirudo-test-vm.env && exec ./run-target-tests.sh \$VM_SUITE" \
		vm/run.sh &&
	grep -Fq "while [ ! -e /mnt/shirudo-out/host-done ]" vm/run.sh &&
	grep -Fq ": >\"\$RUN_DIR/result/host-done\"" vm/run.sh
'

test_expect_success 'an operator VM serves without a TPM and alone gets the key' '
	mkdir -p "$WORK/operator-keys" &&
	! TEST_VM_ROLE=other "$RUNNER" >"$WORK/role.out" 2>&1 &&
	grep -q "TEST_VM_ROLE must be .target. or .operator." "$WORK/role.out" &&
	! TEST_VM_ROLE=operator VM_MODE=test TEST_VM_INITRD=0 \
		"$RUNNER" >"$WORK/operator-mode.out" 2>&1 &&
	grep -q "an operator VM runs in serve mode" "$WORK/operator-mode.out" &&
	! TEST_VM_ROLE=operator VM_MODE=serve TEST_VM_INITRD=0 \
		TEST_VM_SERVE_COMMAND=/bin/true \
		TEST_VM_OPERATOR_KEYS="$WORK/operator-keys" \
		"$RUNNER" >"$WORK/operator-keys.out" 2>&1 &&
	grep -q "TEST_VM_OPERATOR_KEYS must name" "$WORK/operator-keys.out" &&
	! VM_MODE=serve TEST_VM_OPERATOR_KEYS="$WORK/operator-keys" \
		"$RUNNER" >"$WORK/target-keys.out" 2>&1 &&
	grep -q "only an operator VM gets TEST_VM_OPERATOR_KEYS" \
		"$WORK/target-keys.out" &&
	! VM_MODE=test TEST_VM_SERVE_COMMAND=/bin/true \
		"$RUNNER" >"$WORK/serve-command.out" 2>&1 &&
	grep -q "TEST_VM_SERVE_COMMAND must name a program, in serve mode" \
		"$WORK/serve-command.out" &&
	! VM_MODE=serve TEST_VM_PRIVATE_DIR="$PWD/private" \
		"$RUNNER" >"$WORK/private-repo.out" 2>&1 &&
	grep -q "TEST_VM_PRIVATE_DIR must name a new directory outside" \
		"$WORK/private-repo.out" &&
	mkdir "$WORK/private" &&
	! VM_MODE=serve TEST_VM_PRIVATE_DIR="$WORK/private" \
		"$RUNNER" >"$WORK/private-exists.out" 2>&1 &&
	grep -q "TEST_VM_PRIVATE_DIR must name a new directory outside" \
		"$WORK/private-exists.out" &&
	grep -q -- "-u TEST_VM_PRIVATE_DIR" vm/run.sh &&
	grep -Fq "SSH_KEY=\"\${PRIVATE_DIR:-\$SSH_DIR}/id_ed25519\"" vm/run.sh &&
	grep -Fq "OVERLAY=\"\${PRIVATE_DIR:-\$RUN_DIR}/rootfs.qcow2\"" vm/run.sh &&
	grep -Fq "OPERATOR_PRIVATE_DIR=\$HOST_PRIVATE_DIR/" end2end/host.sh &&
	grep -Fq "TEST_VM_PRIVATE_DIR=\"\$OPERATOR_PRIVATE_DIR\"" end2end/host.sh &&
	make -n -C .. -f testing/Makefile vm-operator-end2end VM_NAME=e2e-operator \
		TEST_VM_SERVE_COMMAND=/bin/true TEST_VM_WORK_DIR="$WORK/operator-vm" \
		TEST_VM_PRIVATE_DIR="$WORK/operator-private" \
		>"$WORK/operator-make.out" 2>&1 &&
	grep -q "TEST_VM_ROLE=operator" "$WORK/operator-make.out" &&
	grep -q "TEST_VM_OPERATOR_KEYS=.*/operator-keys/keys" "$WORK/operator-make.out" &&
	grep -Fq "TEST_VM_PRIVATE_DIR=\"$WORK/operator-private\"" \
		"$WORK/operator-make.out" &&
	make -n -C .. -f testing/Makefile vm-test-end2end VM_NAME=e2e \
		TEST_VM_WORK_DIR="$WORK/target-vm" >"$WORK/target-make.out" 2>&1 &&
	grep -q "VM_MODE=serve" "$WORK/target-make.out" &&
	! grep -q "TEST_VM_OPERATOR_KEYS\|TEST_VM_ROLE\|TEST_VM_PRIVATE_DIR" \
		"$WORK/target-make.out" &&
	grep -Fq "[[ \"\$VM_ROLE\" != target ]] || start_swtpm" vm/run.sh &&
	grep -q "mount_tag=shirudo-operator-keys" vm/run.sh &&
	grep -q "the operator VM has a TPM" vm/guest.sh &&
	grep -q "bindeb-pkg PKG_ROLES=operator" vm/guest.sh
'
test_expect_success 'test VMs require a CI kernel artifact' '
	grep -q "testing/kernel" ../testing/Makefile &&
	grep -q "^require-vm-kernel:" ../testing/Makefile &&
	! grep -q "build-kernel.sh\|KERNEL_CONFIG\|KERNEL_PATCHES" ../testing/Makefile &&
	grep -q "KERNEL_CI_ARTIFACT_DIR" ../.github/scripts/tests.sh &&
	grep -q "kernel-artifact.sh fetch" ../testing/Makefile &&
	id=$(vm/kernel-artifact.sh run-id) &&
	test "$(KERNEL_RUN_ID=12 vm/kernel-artifact.sh run-id)" = 12 &&
	test "$id" -gt 0 &&
	! KERNEL_RUN_ID=1x vm/kernel-artifact.sh run-id 2>/dev/null &&
	grep -q "select-test-kernel.sh" ../.github/workflows/tests.yml
'
test_expect_success 'prepared VM runtime includes ripgrep' '
	grep -qx "ripgrep" vm/runtime-packages &&
	grep -q "package_digest" vm/build-bundle.sh
'

test_expect_success 'named VM console and SSH access helpers are wired up' '
	grep -q "^vm-console:" ../testing/Makefile &&
	grep -q "^vm-ssh:" ../testing/Makefile &&
	grep -q "testing/vm/run.sh --console" ../testing/Makefile &&
	grep -q "testing/vm/run.sh --ssh" ../testing/Makefile &&
	grep -q "VM_SSH_COMMAND" vm/run.sh &&
	grep -q "TEST_VM_SSH_PORT" vm/run.sh &&
	grep -q "hostfwd=tcp:127.0.0.1" vm/run.sh &&
	grep -q "socket,id=console" vm/run.sh &&
	grep -q "logfile=.*console.log" vm/run.sh &&
	grep -q "TEST_VM_SSH_PUBLIC_KEY" vm/run.sh &&
	grep -q "serial-getty@\${TEST_VM_ARCH_CONSOLE}.service" vm/guest.sh &&
	grep -q "TEST_VM_SSH_PUBLIC_KEY" vm/guest.sh
'

test_expect_success 'VM console requires a named VM and SSH reports empty state' '
	! TEST_VM_WORK_DIR="$WORK/access-console" "$RUNNER" --console \
		>"$WORK/access-console.out" 2>&1 &&
	grep -q "VM_NAME is required for VM console/SSH access" \
		"$WORK/access-console.out" &&
	! TEST_VM_WORK_DIR="$WORK/access-ssh" "$RUNNER" --ssh \
		>"$WORK/access-ssh.out" 2>&1 &&
	grep -q "no saved VM states found" \
		"$WORK/access-ssh.out"
'

test_expect_success 'unnamed vm-ssh selects the newest saved VM state' '
	root="$WORK/latest-ssh" &&
	mkdir -p "$root/vms/older" "$root/vms/newer" &&
	printf "1000000000000000000\n" >"$root/vms/older/created-at" &&
	printf "2000000000000000000\n" >"$root/vms/newer/created-at" &&
	touch -t 203001010000 "$root/vms/older" &&
	! TEST_VM_WORK_DIR="$root" "$RUNNER" --ssh \
		>"$WORK/latest-ssh.out" 2>&1 &&
	grep -q "VM '\''newer'\'' is not running" "$WORK/latest-ssh.out"
'

test_expect_success 'explicit VM_NAME overrides unnamed vm-ssh selection' '
	root="$WORK/named-ssh" &&
	mkdir -p "$root/vms/older" "$root/vms/newer" &&
	printf "1000000000000000000\n" >"$root/vms/older/created-at" &&
	printf "2000000000000000000\n" >"$root/vms/newer/created-at" &&
	! VM_NAME=older TEST_VM_WORK_DIR="$root" "$RUNNER" --ssh \
		>"$WORK/named-ssh.out" 2>&1 &&
	grep -q "VM '\''older'\'' is not running" "$WORK/named-ssh.out"
'

test_expect_success 'VM bundle installs target units and interactive mode activates timers' '
	grep -q "DESTDIR=\"\$TMP_DIR/root\" install-target" \
		vm/build-bundle-payload.sh &&
	grep -q "systemd/\\*.timer" ../testing/Makefile &&
	grep -q "shirudo-map-export.timer" vm/guest.sh &&
	grep -q "shirudo-keepalive.timer" vm/guest.sh &&
	grep -q "shirudo-bpm-repo-update.service" vm/guest.sh &&
	grep -q "shirudo-bpm-repo-update.timer" vm/guest.sh &&
	grep -q "shirudo-bpm-tree-sync.service" vm/guest.sh &&
	grep -q "shirudo-bpm-tree-sync.timer" vm/guest.sh &&
	grep -q "OnUnitActiveSec=60s" ../systemd/shirudo-bpm-tree-sync.timer &&
	grep -q "Persistent=true" ../systemd/shirudo-bpm-tree-sync.timer &&
	grep -q "systemctl enable shirudo.service" vm/guest.sh &&
	grep -q "systemctl enable --now shirudo-map-export.timer" \
		vm/guest.sh &&
	grep -q "systemctl enable --now shirudo-keepalive.timer" \
		vm/guest.sh &&
	grep -q "systemctl enable --now shirudo-bpm-repo-update.timer" \
		vm/guest.sh &&
	grep -q "systemctl enable --now shirudo-bpm-tree-sync.timer" \
		vm/guest.sh &&
	grep -Fq "if [[ \"\$VM_MODE\" == interactive ]]" \
		vm/guest.sh
'

test_expect_success 'VM stop and cleanup use the VM runner paths' '
	grep -q "^vm-stop:" ../testing/Makefile &&
	grep -q "testing/vm/run.sh --stop" ../testing/Makefile &&
	grep -q "^vm-clean:" ../testing/Makefile &&
	grep -q "testing/vm/run.sh --clean" ../testing/Makefile &&
	grep -q "VM_NAME=\"\$(VM_NAME)\"" ../testing/Makefile &&
	grep -q "stop_pid_file" vm/run.sh &&
	grep -q "removed VM state and logs" vm/run.sh
'

test_expect_success 'named vm-stop preserves the selected VM state' '
	root="$WORK/named-stop" &&
	mkdir -p "$root/vms/one" "$root/logs/one" &&
	printf state >"$root/vms/one/sentinel" &&
	printf log >"$root/logs/one/sentinel" &&
	VM_NAME=one TEST_VM_WORK_DIR="$root" "$RUNNER" --stop &&
	test -e "$root/vms/one/sentinel" &&
	test -e "$root/logs/one/sentinel"
'

test_expect_success 'unnamed vm-stop stops all VMs and preserves state' '
	root="$WORK/all-stop" &&
	mkdir -p "$root/vms/one" "$root/vms/two" "$root/logs/one" \
		"$root/logs/two" &&
	printf state >"$root/vms/one/sentinel" &&
	printf state >"$root/vms/two/sentinel" &&
	printf log >"$root/logs/one/sentinel" &&
	printf log >"$root/logs/two/sentinel" &&
	TEST_VM_WORK_DIR="$root" "$RUNNER" --stop &&
	test -e "$root/vms/one/sentinel" &&
	test -e "$root/vms/two/sentinel" &&
	test -e "$root/logs/one/sentinel" &&
	test -e "$root/logs/two/sentinel"
'

test_expect_success 'named vm-clean removes only the selected VM' '
	root="$WORK/named-clean" &&
	mkdir -p "$root/vms/one" "$root/vms/two" "$root/logs/one" \
		"$root/logs/two" "$root/cache" &&
	printf state >"$root/vms/one/sentinel" &&
	printf state >"$root/vms/two/sentinel" &&
	printf log >"$root/logs/one/sentinel" &&
	printf log >"$root/logs/two/sentinel" &&
	VM_NAME=one TEST_VM_WORK_DIR="$root" "$RUNNER" --clean &&
	! test -e "$root/vms/one" &&
	! test -e "$root/logs/one" &&
	test -e "$root/vms/two/sentinel" &&
	test -e "$root/logs/two/sentinel" &&
	test -d "$root/cache"
'

test_expect_success 'test-vm supports secure and explicit insecure map-export modes' '
	grep -q "MAP_EXPORT_CA=\"\${TEST_VM_MAP_EXPORT_CA:-}\"" "$RUNNER" &&
	grep -q "MAP_EXPORT_INSECURE=false" "$RUNNER" &&
	grep -q "HTTPS map-export endpoints require TEST_VM_MAP_EXPORT_INSECURE=false" "$RUNNER" &&
	grep -q "HTTP map-export endpoints require TEST_VM_MAP_EXPORT_INSECURE=true" "$RUNNER" &&
	grep -q "TEST_VM_MAP_EXPORT_CA=\"\$(TEST_VM_MAP_EXPORT_CA)\"" ../testing/Makefile &&
	grep -q "export TEST_VM_MAP_EXPORT_ENDPOINT" "$RUNNER" &&
	grep -q "export TEST_VM_MAP_EXPORT_CA=/mnt/shirudo-otel/ca.pem" "$RUNNER" &&
	grep -q "mount_tag=shirudo-otel" "$RUNNER" &&
	grep -q "10.0.2.2 otel.test" vm/guest.sh &&
	grep -q "map_export.otel_endpoint = \$endpoint" vm/guest.sh &&
	grep -q "map_export.otel_insecure = \$insecure" vm/guest.sh &&
	grep -q "OTEL_EXPORTER_OTLP_CERTIFICATE=/etc/shirudo/otel/ca.pem" \
		vm/guest.sh &&
	grep -q "map_export.tenant_id = \$tenant_id" vm/guest.sh
'

test_expect_success 'test-vm rejects incomplete map-export bridge settings' '
	printf kernel >"$WORK/map-export-kernel" &&
	! TEST_VM_WORK_DIR="$WORK/incomplete-map-export" \
		TEST_VM_KERNEL="$WORK/map-export-kernel" \
		TEST_VM_MAP_EXPORT_ENDPOINT=http://otel.test:4318 \
		TEST_VM_MAP_EXPORT_INSECURE=true "$RUNNER" \
		>"$WORK/incomplete-map-export.out" 2>&1 &&
	grep -q "must be set together" "$WORK/incomplete-map-export.out"
'

test_expect_success 'test-vm accepts secure HTTPS export without insecure setting' '
	! TEST_VM_WORK_DIR="$WORK/secure-map-export" \
		TEST_VM_KERNEL="$WORK/map-export-kernel" \
		TEST_VM_MAP_EXPORT_ENDPOINT=https://otel.test:4318 \
		TEST_VM_MAP_EXPORT_TENANT_ID=tenant-test "$RUNNER" \
		>"$WORK/secure-map-export.out" 2>&1 &&
	! grep -q "must be exactly true" "$WORK/secure-map-export.out" &&
	! grep -q "must be true or false" "$WORK/secure-map-export.out"
'

test_expect_success 'test-vm rejects cleartext export without explicit insecure setting' '
	! TEST_VM_WORK_DIR="$WORK/cleartext-map-export" \
		TEST_VM_KERNEL="$WORK/map-export-kernel" \
		TEST_VM_MAP_EXPORT_ENDPOINT=http://otel.test:4318 \
		TEST_VM_MAP_EXPORT_TENANT_ID=tenant-test "$RUNNER" \
		>"$WORK/cleartext-map-export.out" 2>&1 &&
	grep -q "HTTP map-export endpoints require TEST_VM_MAP_EXPORT_INSECURE=true" \
		"$WORK/cleartext-map-export.out"
'

test_expect_success 'test-vm validates a custom OTEL CA file before boot' '
	! TEST_VM_WORK_DIR="$WORK/missing-map-export-ca" \
		TEST_VM_KERNEL="$WORK/map-export-kernel" \
		TEST_VM_MAP_EXPORT_ENDPOINT=https://otel.test:4318 \
		TEST_VM_MAP_EXPORT_TENANT_ID=tenant-test \
		TEST_VM_MAP_EXPORT_CA="$WORK/no-ca.pem" "$RUNNER" \
		>"$WORK/missing-map-export-ca.out" 2>&1 &&
	grep -q "TEST_VM_MAP_EXPORT_CA is not a readable regular file" \
		"$WORK/missing-map-export-ca.out"
'

test_expect_success 'test-vm passes an OCI CA into the guest trust store' '
	grep -q "TEST_VM_OCI_CA" ../testing/Makefile &&
	grep -q "OCI_CA=\"\${TEST_VM_OCI_CA:-}\"" "$RUNNER" &&
	grep -q "shirudo-oci" "$RUNNER" &&
	grep -q "export TEST_VM_OCI_CA=/mnt/shirudo-oci/ca.crt" "$RUNNER" &&
	grep -q "shirudo-oci-ca.crt" vm/guest.sh &&
	grep -q "update-ca-certificates" vm/guest.sh
'

test_expect_success 'test-vm validates a custom OCI CA file before boot' '
	! TEST_VM_WORK_DIR="$WORK/missing-oci-ca" \
		TEST_VM_KERNEL="$WORK/map-export-kernel" \
		TEST_VM_OCI_CA="$WORK/no-oci-ca.pem" "$RUNNER" \
		>"$WORK/missing-oci-ca.out" 2>&1 &&
	grep -q "TEST_VM_OCI_CA is not a readable, non-empty regular file" \
		"$WORK/missing-oci-ca.out"
'

test_expect_success 'test-vm hands off an interactive BPM tree configuration' '
	grep -q "TEST_VM_BPM_TREE_CONFIG" ../testing/Makefile &&
	grep -q "TEST_VM_BPM_TREE_CONFIG=\"\$(TEST_VM_BPM_TREE_CONFIG)\"" ../testing/Makefile &&
	grep -q "BPM_TREE_CONFIG=\"\${TEST_VM_BPM_TREE_CONFIG:-}\"" "$RUNNER" &&
	grep -q "validate_bpm_tree_config" "$RUNNER" &&
	grep -q "BPM_TREE_DIR=\"\${RUN_DIR}/bpm-tree\"" "$RUNNER" &&
	grep -q "install -m 0644 \"\$BPM_TREE_CONFIG\" \"\$BPM_TREE_DIR/upatch-tree.conf\"" "$RUNNER" &&
	grep -q "mount_tag=shirudo-bpm-tree" "$RUNNER" &&
	grep -q "export TEST_VM_BPM_TREE_INPUT=/mnt/shirudo-bpm-tree" "$RUNNER" &&
	grep -q "mount.*shirudo-bpm-tree /mnt/shirudo-bpm-tree" "$RUNNER" &&
	grep -q "credentials and private signing" "$RUNNER" &&
	grep -q "configure_bpm_tree" vm/guest.sh &&
	grep -Fq "[[ -z \"\$tree_input\" ]] && return 0" vm/guest.sh &&
	grep -q "local config_file=\"\${tree_input}/upatch-tree.conf\"" vm/guest.sh &&
	grep -q "temporary=\"\${target}.tmp.\$\$\"" vm/guest.sh &&
	grep -q "mv -f \"\$temporary\" \"\$target\"" vm/guest.sh &&
	grep -q "systemctl start shirudo-bpm-tree-sync.service" vm/guest.sh &&
	grep -q "systemctl enable --now shirudo-bpm-tree-sync.timer" vm/guest.sh &&
	test "$(grep -n "SHIRUDO_BIN.* init" vm/guest.sh | cut -d: -f1)" -lt \
		"$(grep -n "systemctl start shirudo-bpm-tree-sync.service" vm/guest.sh | cut -d: -f1)" &&
	test "$(grep -n "systemctl start shirudo-bpm-tree-sync.service" vm/guest.sh | cut -d: -f1)" -lt \
		"$(grep -n "systemctl enable --now shirudo-bpm-tree-sync.timer" vm/guest.sh | cut -d: -f1)"
'

test_expect_success 'test-vm validates BPM tree configuration mode and contents' '
	printf kernel >"$WORK/bpm-tree-kernel" &&
	! TEST_VM_WORK_DIR="$WORK/missing-bpm-tree" \
		VM_MODE=interactive TEST_VM_KERNEL="$WORK/bpm-tree-kernel" \
		TEST_VM_BPM_TREE_CONFIG="$WORK/no-bpm-tree.conf" "$RUNNER" \
		>"$WORK/missing-bpm-tree.out" 2>&1 &&
	grep -q "TEST_VM_BPM_TREE_CONFIG is not a readable, non-empty regular file" \
		"$WORK/missing-bpm-tree.out" &&
	: >"$WORK/empty-bpm-tree.conf" &&
	! TEST_VM_WORK_DIR="$WORK/empty-bpm-tree" \
		VM_MODE=interactive TEST_VM_KERNEL="$WORK/bpm-tree-kernel" \
		TEST_VM_BPM_TREE_CONFIG="$WORK/empty-bpm-tree.conf" "$RUNNER" \
		>"$WORK/empty-bpm-tree.out" 2>&1 &&
	grep -q "TEST_VM_BPM_TREE_CONFIG is not a readable, non-empty regular file" \
		"$WORK/empty-bpm-tree.out" &&
	printf 'tree config\n' >"$WORK/bpm-tree.conf" &&
	! TEST_VM_WORK_DIR="$WORK/test-bpm-tree" \
		VM_MODE=test TEST_VM_KERNEL="$WORK/bpm-tree-kernel" \
		TEST_VM_BPM_TREE_CONFIG="$WORK/bpm-tree.conf" "$RUNNER" \
		>"$WORK/test-bpm-tree.out" 2>&1 &&
	grep -q "TEST_VM_BPM_TREE_CONFIG is supported only for interactive make -C testing vm" \
		"$WORK/test-bpm-tree.out"
'

test_expect_success 'test-vm validates a custom package certificate before boot' '
	printf kernel >"$WORK/package-cert-kernel" &&
	! TEST_VM_WORK_DIR="$WORK/missing-package-cert" \
		VM_MODE=interactive \
		TEST_VM_KERNEL="$WORK/package-cert-kernel" \
		TEST_VM_PACKAGE_CERT="$WORK/no-package-cert.der" "$RUNNER" \
		>"$WORK/missing-package-cert.out" 2>&1 &&
	grep -q "TEST_VM_PACKAGE_CERT is not a readable, non-empty regular file" \
		"$WORK/missing-package-cert.out"
'

test_expect_success 'test-vm bootstraps a BPM OCI repository from the host' '
	grep -q "TEST_VM_BPM_OCI_REPOSITORY" ../testing/Makefile &&
	grep -q "TEST_VM_BPM_OCI_INDEX_CERT" ../testing/Makefile &&
	grep -q "BPM_OCI_REPOSITORY_RAW=\"\${TEST_VM_BPM_OCI_REPOSITORY:-}\"" \
		"$RUNNER" &&
	grep -q "export TEST_VM_BPM_OCI_SOURCE" "$RUNNER" &&
	grep -q "export TEST_VM_BPM_OCI_INPUT=/mnt/shirudo-bpm-oci" "$RUNNER" &&
	grep -q "registries.d/\${BPM_OCI_SOURCE}.conf" "$RUNNER" &&
	grep -q "keys/\${BPM_OCI_SOURCE}.pem" "$RUNNER" &&
	grep -q "repository.env" "$RUNNER" &&
	grep -q "mount_tag=shirudo-bpm-oci" "$RUNNER" &&
	grep -q "registry\.test" vm/guest.sh &&
	grep -q "install -m 0644.*staged_conf.*conf_file" \
		vm/guest.sh &&
	grep -q "install -m 0644.*staged_env.*repository_env" \
		vm/guest.sh
'

test_expect_success 'test-vm validates BPM OCI repository handoff as a pair' '
	printf kernel >"$WORK/bpm-oci-kernel" &&
	! TEST_VM_WORK_DIR="$WORK/missing-bpm-oci-cert" \
		TEST_VM_KERNEL="$WORK/bpm-oci-kernel" \
		TEST_VM_BPM_OCI_REPOSITORY=example=oci://registry.example.com \
		"$RUNNER" >"$WORK/missing-bpm-oci-cert.out" 2>&1 &&
	grep -q "TEST_VM_BPM_OCI_REPOSITORY and TEST_VM_BPM_OCI_INDEX_CERT must be set together" \
		"$WORK/missing-bpm-oci-cert.out" &&
	! TEST_VM_WORK_DIR="$WORK/missing-bpm-oci-repository" \
		TEST_VM_KERNEL="$WORK/bpm-oci-kernel" \
		TEST_VM_BPM_OCI_INDEX_CERT="$WORK/missing-index-cert.pem" \
		"$RUNNER" >"$WORK/missing-bpm-oci-repository.out" 2>&1 &&
	grep -q "TEST_VM_BPM_OCI_REPOSITORY and TEST_VM_BPM_OCI_INDEX_CERT must be set together" \
		"$WORK/missing-bpm-oci-repository.out"
'

test_expect_success 'make -C testing runs every tier in order' '
	grep -A4 "^all:$" ../testing/Makefile | sed -n "2,5s/.*\$(MAKE) //p" \
		>"$WORK/tiers" &&
	[ "$(tr "\n" " " <"$WORK/tiers")" = "unit ci-checks functional end2end " ] &&
	grep -q "^bundle: test-vm-bundle" ../testing/Makefile
'

test_expect_success 'the runners split the tests by number' '
	{ echo "dirs=\"ci-checks functional/* end2end\""
	  sed -n "/^operator_tests()/,/^}/p" run-tests.sh; echo operator_tests; } |
		sh >"$WORK/operator-tests" &&
	grep -q "^functional/upatch/t3001-" "$WORK/operator-tests" &&
	! grep -q "/t[0-9]1[0-9][0-9]-" "$WORK/operator-tests" &&
	families=$(make -s -C .. -f testing/Makefile help |
		sed -n "s/.*families: //p") &&
	[ "$families" = "build signing upatch upatch-many tpm image image-reboot labels tamperproof bpm bpm-pending bpm-segments otel" ] &&
	for d in functional/*/; do
		f=${d#functional/}
		case " $families " in *" ${f%/} "*) ;; *) return 1 ;; esac
	done &&
	! sh run-tests.sh nosuch >"$WORK/nosuch.out" 2>&1 &&
	grep -q "no tests nosuch" "$WORK/nosuch.out" &&
	test -e end2end/t9109-pipeline.sh &&
	test -e end2end/t9110-keepalive-history.sh &&
	test -e end2end/t9111-pipeline-segments.sh &&
	test -e end2end/t9112-activation.sh &&
	test -e end2end/t9113-shield-rollout.sh &&
	test -e end2end/t9114-app-sandbox.sh &&
	grep -Fqx "	end2end/t9109-pipeline.sh | end2end/t9110-keepalive-history.sh) continue ;;" \
		run-target-tests.sh &&
	grep -Fqx "	end2end/t9111-pipeline-segments.sh | end2end/t9112-activation.sh) continue ;;" \
		run-target-tests.sh &&
	grep -Fqx "host_test t9109-pipeline" end2end/host.sh &&
	grep -Fqx "host_test t9110-keepalive-history" end2end/host.sh &&
	grep -Fqx "	end2end/t9113-shield-rollout.sh | end2end/t9114-app-sandbox.sh) continue ;;" \
		run-target-tests.sh &&
	grep -Fqx "host_test t9111-pipeline-segments" end2end/host.sh &&
	grep -Fqx "host_test t9112-activation" end2end/host.sh &&
	grep -Fqx "	host_test t9113-shield-rollout" end2end/host.sh &&
	grep -Fqx "host_test t9114-app-sandbox" end2end/host.sh
'

test_expect_success 'test-vm rejects unknown policy modes before boot' '
	! TEST_VM_MODE=typo "$RUNNER" >"$WORK/policy-mode.out" 2>&1 &&
	grep -q "TEST_VM_MODE must be verity" "$WORK/policy-mode.out"
'

test_expect_success 'image VM requires initrd enrollment and complete guards' '
	! TEST_VM_MODE=verity TEST_VM_INITRD=0 "$RUNNER" \
		>"$WORK/image-initrd.out" 2>&1 &&
	grep -q "dm-verity requires TEST_VM_INITRD=1" "$WORK/image-initrd.out" &&
	! TEST_VM_MODE=verity TEST_VM_INITRD=1 TEST_VM_SKIP_SEAL=1 "$RUNNER" \
		>"$WORK/image-seal.out" 2>&1 &&
	grep -q "TEST_VM_SKIP_SEAL=0" "$WORK/image-seal.out"
'

test_expect_success 'test VM takes register or a test family' '
	! TEST_VM_MODE=verity TEST_VM_INITRD=1 TEST_VM_SUITE=all "$RUNNER" \
		>"$WORK/image-suite.out" 2>&1 &&
	grep -q "TEST_VM_SUITE must be register, end2end or a directory" \
		"$WORK/image-suite.out" &&
	! TEST_VM_MODE=verity TEST_VM_INITRD=1 TEST_VM_SUITE= "$RUNNER" \
		>"$WORK/image-suite.out" 2>&1 &&
	grep -q "test mode requires TEST_VM_SUITE" "$WORK/image-suite.out"
'

test_expect_success 'image target runner refuses missing fixture configuration' '
	! SHIRUDO_TEST_MODE=verity SHIRUDO_BIN=/bin/true \
		SHIRUDO_TEST_FIXTURES_DIR= SHIRUDO_TEST_KEY_FIXTURES= \
		sh ./run-target-tests.sh upatch >"$WORK/target-fixtures.out" 2>&1 &&
	grep -q "signed upatch fixtures are required" "$WORK/target-fixtures.out" &&
	! sh ./run-target-tests.sh nosuch >"$WORK/target-family.out" 2>&1 &&
	grep -q "no test family nosuch" "$WORK/target-family.out"
'

test_done
