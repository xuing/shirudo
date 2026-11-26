# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Authors of shirudo
#
# Test and VM targets. make -C testing runs every test, make -C
# testing <tier>[/<name>] one tier or part of it; make -C testing help
# lists the rest.

ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)
MAKEFLAGS += -rR --no-print-directory

ifeq ($(V),1)
  Q =
else
  Q = @
endif
export Q V
export TEST_FILTER

# make tests at the top exports the install paths, and dracut takes the
# prefix it finds in the environment for the initrd a test VM boots.
unexport prefix exec_prefix bindir libexecdir sharedir libdir mandir \
	completionsdir systemdunitdir dracutmodulesdir

root-path = $(if $(filter /%,$(1)),$(1),$(ROOT)/$(1))
# $(call test-vm-arch,NAME): the value testing/vm/arch.sh gives NAME.
test-vm-arch = $(shell TEST_VM_ARCH='$(TEST_VM_ARCH)'; \
	. $(ROOT)/testing/vm/arch.sh && printf '%s' "$$$(1)")

.DEFAULT_GOAL := all
.PHONY: all help clean unit ci-checks functional end2end backend build-host build-operator build-unit kernel-btf \
	test-helpers \
	fuzz afl bundle test-vm-bundle require-vm-kernel vm vm-console vm-ssh vm-enroll vm-sbom vm-stop vm-clean \
	vm-operator-end2end

PACKAGE_FORMAT ?= $(call test-vm-arch,TEST_VM_HOST_PKG_FORMAT)

TEST_VM_MODE ?= verity
ifneq ($(TEST_VM_MODE),verity)
  $(error TEST_VM_MODE must be verity)
endif
TEST_VM_INITRD ?= 1
TEST_VM_WORK_DIR ?= build/test-vm
override TEST_VM_WORK_DIR := $(call root-path,$(TEST_VM_WORK_DIR))
TEST_VM_HOST_PRIVATE_DIR ?= /tmp/shirudo-test-vm-private-$(shell id -u)
override TEST_VM_HOST_PRIVATE_DIR := $(call root-path,$(TEST_VM_HOST_PRIVATE_DIR))
TEST_VM_BUNDLE_DIR ?= $(TEST_VM_WORK_DIR)/host-bundle-$(VM_KERNEL_TAG)$(KERNEL_COMMIT_SUFFIX)-$(TEST_VM_MODE)
TEST_VM_RUNTIME_CACHE_DIR ?= $(TEST_VM_WORK_DIR)/cache/runtime
override TEST_VM_RUNTIME_CACHE_DIR := $(call root-path,$(TEST_VM_RUNTIME_CACHE_DIR))
TEST_VM_MAP_EXPORT_CA ?=
override TEST_VM_MAP_EXPORT_CA := $(if $(strip $(TEST_VM_MAP_EXPORT_CA)),$(call root-path,$(TEST_VM_MAP_EXPORT_CA)),)
TEST_VM_OCI_CA ?=
override TEST_VM_OCI_CA := $(if $(strip $(TEST_VM_OCI_CA)),$(call root-path,$(TEST_VM_OCI_CA)),)
TEST_VM_BPM_TREE_CONFIG ?=
override TEST_VM_BPM_TREE_CONFIG := $(if $(strip $(TEST_VM_BPM_TREE_CONFIG)),$(call root-path,$(TEST_VM_BPM_TREE_CONFIG)),)
TEST_VM_PACKAGE_CERT ?=
override TEST_VM_PACKAGE_CERT := $(if $(strip $(TEST_VM_PACKAGE_CERT)),$(call root-path,$(TEST_VM_PACKAGE_CERT)),)
TEST_VM_BPM_OCI_REPOSITORY ?=
TEST_VM_BPM_OCI_INDEX_REPOSITORY ?=
TEST_VM_BPM_OCI_INDEX_CERT ?=
override TEST_VM_BPM_OCI_INDEX_CERT := $(if $(strip $(TEST_VM_BPM_OCI_INDEX_CERT)),$(call root-path,$(TEST_VM_BPM_OCI_INDEX_CERT)),)
TEST_VM_CPUS ?= 4
TEST_VM_MEMORY ?= 4G
TEST_VM_DISK_SIZE ?= 30G
TEST_VM_UBUNTU_CODENAME ?= resolute
TEST_VM_VERBOSE ?= 0
# Test VMs use kernel artifacts built from testing/kernel.
VM_KERNEL ?= $(if $(strip $(KERNEL)),$(KERNEL),bpf-next)
VM_KERNEL_VERSION := $(patsubst v%,%,$(VM_KERNEL))
VM_KERNEL_MIN := 7.4
VM_KERNEL_IS_RELEASE := $(shell printf '%s\n' '$(VM_KERNEL_VERSION)' | \
                          grep -Ec '^[0-9]+\.[0-9]+(\.[0-9]+)?$$')
VM_KERNEL_OLDEST := $(firstword $(shell printf '%s\n' '$(VM_KERNEL_MIN)' \
                                '$(VM_KERNEL_VERSION)' | sort -V))
KERNEL_COMMIT ?=
KERNEL_COMMIT_SUFFIX := $(if $(strip $(KERNEL_COMMIT)),-$(KERNEL_COMMIT),)
ifeq ($(VM_KERNEL),bpf-next)
ifneq ($(strip $(KERNEL_COMMIT)),)
  $(error KERNEL_COMMIT is supported only for release VM kernels)
endif
  VM_KERNEL_TAG := bpf-next
  VM_KERNEL_ARTIFACT_DIR := $(ROOT)/artifacts/bpf-next-kernel-debs
else ifeq ($(VM_KERNEL_IS_RELEASE),1)
ifneq ($(VM_KERNEL_OLDEST),$(VM_KERNEL_MIN))
  $(error shirudo requires Linux v$(VM_KERNEL_MIN) or newer; KERNEL '$(VM_KERNEL)' is older)
endif
  VM_KERNEL_TAG := v$(VM_KERNEL_VERSION)
  VM_KERNEL_ARTIFACT_DIR := $(ROOT)/artifacts/linux-$(VM_KERNEL_TAG)$(KERNEL_COMMIT_SUFFIX)-kernel-debs
else
  $(error unsupported VM KERNEL '$(VM_KERNEL)'; choose bpf-next or a release such as $(VM_KERNEL_MIN))
endif
override TEST_VM_BUNDLE_DIR := $(call root-path,$(TEST_VM_BUNDLE_DIR))
VM_KERNEL_IMAGE_NAME := $(call test-vm-arch,TEST_VM_ARCH_KIMAGE)
VM_KERNEL_IMAGE := $(VM_KERNEL_ARTIFACT_DIR)/$(VM_KERNEL_IMAGE_NAME)
VM_KERNEL_STAMP := $(VM_KERNEL_ARTIFACT_DIR)/$(VM_KERNEL_IMAGE_NAME).sha256sum

TEST_VM_BUNDLE_STAMP := $(TEST_VM_BUNDLE_DIR)/.stamp
TEST_VM_BUNDLE_SOURCES := $(sort $(wildcard \
	$(ROOT)/*.c $(ROOT)/*.h $(ROOT)/include/shirudo/*.h \
	$(ROOT)/util/*.c $(ROOT)/util/*.h \
	$(ROOT)/bpf/*.c $(ROOT)/bpf/lib/*.h \
	$(ROOT)/tools/shirudo-build/*.c $(ROOT)/tools/shirudo-build/*.h \
	$(ROOT)/vendor/libbpf/bpf/*.c $(ROOT)/vendor/libbpf/bpf/*.h \
	$(ROOT)/vendor/libbpf/include/linux/*.h \
	$(ROOT)/vendor/libbpf/include/uapi/linux/*.h \
	$(ROOT)/vendor/libbpf/include/asm/*.h \
	$(ROOT)/testing/helper/*.c $(ROOT)/testing/helper/*.h $(ROOT)/testing/helper/*.py \
	$(ROOT)/testing/vm/bundle-images.sh $(ROOT)/testing/vm/image-fixtures.sh \
	$(ROOT)/tools/gen-image/shirudo-gen-* $(ROOT)/tools/gen-image/*.sh \
	$(ROOT)/tools/gen-image/*.in \
	$(ROOT)/testing/vm/files/* \
	$(ROOT)/testing/end2end/*.c $(ROOT)/completion/* $(ROOT)/systemd/*.in \
	$(ROOT)/systemd/*.timer $(ROOT)/testing/fixtures/*.c $(ROOT)/testing/fixtures/*.lua \
	$(ROOT)/testing/fixtures/*.conf $(ROOT)/testing/fixtures/*.sh \
	$(ROOT)/testing/fixtures/*.h \
	$(ROOT)/testing/fixtures/policy-labels/* \
	$(ROOT)/testing/fixtures/policy-exec-graph/* \
	$(ROOT)/testing/fixtures/segments/*/* \
	$(ROOT)/testing/fixtures/decoders/* \
	$(ROOT)/upatches/kernel-obs/*.c $(ROOT)/upatches/kernel-obs/*.h $(ROOT)/upatches/kernel-obs/*.list \
		$(ROOT)/upatches/kernel-obs/*.py $(ROOT)/upatches/kernel-obs/Beefile \
	$(ROOT)/upatches/kernel-obs/decoders/*))
# The host's util/version_id.c is no input: every build of the host's
# writes it, and the bundle's build writes its own.
TEST_VM_BUNDLE_SOURCES := $(filter-out $(ROOT)/util/version_id.c,$(TEST_VM_BUNDLE_SOURCES))
# The external kernel build replaces versioned package files. Track its stamp
# when present so a new artifact invalidates the bundle.
TEST_VM_BUNDLE_ARTIFACTS := $(wildcard $(VM_KERNEL_STAMP))
# The bundle builds in the build container unless BUILD_CONTAINER=0, so it
# depends on the image's inputs rather than on the host's configuration.
BUILD_CONTAINER ?= 1
TEST_VM_BUILD_ENV := $(if $(filter 0,$(BUILD_CONTAINER)),$(ROOT)/config.mk, \
	$(ROOT)/testing/container/Containerfile $(ROOT)/testing/container/packages \
	$(ROOT)/testing/container/run.sh $(ROOT)/.github/scripts/install-clang.sh \
	$(ROOT)/.github/scripts/install-static-libcrypto-deps.sh \
	$(ROOT)/testing/vm/list-source.sh)
TEST_VM_BUNDLE_INPUTS := $(sort \
	$(ROOT)/Makefile $(ROOT)/Makefile.config $(ROOT)/Makefile.shirudo $(ROOT)/Makefile.version \
	$(TEST_VM_BUILD_ENV) \
	$(ROOT)/Makefile.target-deps \
	$(ROOT)/testing/Makefile $(ROOT)/packaging/Makefile \
	$(ROOT)/vendor/libbpf/Makefile $(ROOT)/vendor/libbpf/COMMIT \
	$(ROOT)/Documentation/Makefile $(ROOT)/upatches/kernel-obs/Makefile \
	$(ROOT)/testing/vm/build-bundle.sh $(ROOT)/testing/vm/build-bundle-payload.sh \
	$(ROOT)/testing/vm/guest.sh \
	$(ROOT)/testing/vm/arch.sh \
	$(ROOT)/testing/vm/prepare-runtime.sh $(ROOT)/testing/vm/runtime-packages \
	$(TEST_VM_BUNDLE_SOURCES) $(TEST_VM_BUNDLE_ARTIFACTS) \
	$(if $(strip $(TEST_VM_PACKAGE_CERT)),$(TEST_VM_PACKAGE_CERT)))

# A bundle carries coverage/ when its target was built with COVERAGE=1,
# and one built the other way is built again.
COVERAGE ?= 0
TEST_VM_BUNDLE_COVERAGE := $(if $(wildcard $(TEST_VM_BUNDLE_DIR)/coverage),1,0)
TEST_VM_BUNDLE_REBUILD := $(if $(filter $(COVERAGE),$(TEST_VM_BUNDLE_COVERAGE)),,test-vm-bundle-rebuild)
.PHONY: test-vm-bundle-rebuild
test-vm-bundle-rebuild:

$(ROOT)/config.mk: $(ROOT)/Makefile.config
	+$(Q)$(MAKE) -C $(ROOT) config

# Read the bundle prerequisites after staging can create the kernel stamp.
test-vm-bundle: require-vm-kernel
	+$(Q)$(MAKE) -f "$(ROOT)/testing/Makefile" "$(TEST_VM_BUNDLE_STAMP)"

$(TEST_VM_BUNDLE_STAMP): $(TEST_VM_BUNDLE_INPUTS) $(TEST_VM_BUNDLE_REBUILD)
	$(Q)mkdir -p $(dir $(BUILD_LOCK))
	$(Q)TEST_VM_MODE="$(TEST_VM_MODE)" TEST_VM_INITRD="$(TEST_VM_INITRD)" \
		BUILD_CONTAINER="$(BUILD_CONTAINER)" COVERAGE="$(COVERAGE)" \
		TEST_VM_HOST_BUNDLE="$(abspath $(TEST_VM_BUNDLE_DIR))" \
		TEST_VM_WORK_DIR="$(abspath $(TEST_VM_WORK_DIR))" \
		TEST_VM_HOST_PRIVATE_DIR="$(abspath $(TEST_VM_HOST_PRIVATE_DIR))" \
		TEST_VM_RUNTIME_CACHE_DIR="$(abspath $(TEST_VM_RUNTIME_CACHE_DIR))" \
		TEST_VM_UBUNTU_CODENAME="$(TEST_VM_UBUNTU_CODENAME)" \
		TEST_VM_ROOTFS_URL="$(TEST_VM_ROOTFS_URL)" \
		TEST_VM_ROOTFS_SHA256="$(TEST_VM_ROOTFS_SHA256)" \
		TEST_VM_PACKAGE_CERT="$(TEST_VM_PACKAGE_CERT)" \
		TEST_VM_BUNDLE_STAMP="$(abspath $(TEST_VM_BUNDLE_STAMP))" \
		TEST_VM_BUNDLE_INPUTS="$(abspath $(TEST_VM_BUNDLE_INPUTS))" \
		BPF_VMLINUX_BTF="$(abspath $(VM_KERNEL_ARTIFACT_DIR)/vmlinux.btf)" \
		flock $(BUILD_LOCK) $(ROOT)/testing/vm/build-bundle.sh

# A bpf-next kernel that is not staged is downloaded, the run the CI suite
# pins; one that is staged is left as it is, whatever run it came from.
require-vm-kernel:
	$(Q)test -s "$(VM_KERNEL_IMAGE)" -a -s "$(VM_KERNEL_STAMP)" -a \
		-s "$(VM_KERNEL_ARTIFACT_DIR)/vmlinux.btf" -a \
		-s "$(VM_KERNEL_ARTIFACT_DIR)/kernel.config" -a \
		-d "$(VM_KERNEL_ARTIFACT_DIR)/lib/modules" || { \
		[ "$(VM_KERNEL)" = bpf-next ] && \
			$(ROOT)/testing/vm/kernel-artifact.sh fetch; \
	} || { \
		echo "kernel artifact is missing; use CI kernel packages in $(VM_KERNEL_ARTIFACT_DIR)" >&2; \
		exit 1; \
	}

LOCAL_STACK ?= 1

vm: require-vm-kernel test-vm-bundle
	$(Q)VM_MODE=interactive VM_NAME="$(VM_NAME)" VM_TENANT="$(VM_TENANT)" \
		TEST_VM_KERNEL="$(abspath $(VM_KERNEL_IMAGE))" \
		TEST_VM_KERNEL_ARTIFACT_DIR="$(abspath $(VM_KERNEL_ARTIFACT_DIR))" \
		TEST_VM_WORK_DIR="$(TEST_VM_WORK_DIR)" \
		TEST_VM_RUNTIME_CACHE_DIR="$(TEST_VM_RUNTIME_CACHE_DIR)" \
		TEST_VM_CPUS="$(TEST_VM_CPUS)" \
		TEST_VM_MEMORY="$(TEST_VM_MEMORY)" \
		TEST_VM_DISK_SIZE="$(TEST_VM_DISK_SIZE)" \
		TEST_VM_SSH_PORT="$(TEST_VM_SSH_PORT)" \
		TEST_VM_MAP_EXPORT_ENDPOINT="$(TEST_VM_MAP_EXPORT_ENDPOINT)" \
		TEST_VM_MAP_EXPORT_TENANT_ID="$(TEST_VM_MAP_EXPORT_TENANT_ID)" \
		TEST_VM_MAP_EXPORT_INSECURE="$(TEST_VM_MAP_EXPORT_INSECURE)" \
		TEST_VM_MAP_EXPORT_CA="$(TEST_VM_MAP_EXPORT_CA)" \
		TEST_VM_OCI_CA="$(TEST_VM_OCI_CA)" \
		TEST_VM_BPM_TREE_CONFIG="$(TEST_VM_BPM_TREE_CONFIG)" \
		TEST_VM_PACKAGE_CERT="$(TEST_VM_PACKAGE_CERT)" \
		TEST_VM_BPM_OCI_REPOSITORY="$(TEST_VM_BPM_OCI_REPOSITORY)" \
		TEST_VM_BPM_OCI_INDEX_REPOSITORY="$(TEST_VM_BPM_OCI_INDEX_REPOSITORY)" \
		TEST_VM_BPM_OCI_INDEX_CERT="$(TEST_VM_BPM_OCI_INDEX_CERT)" \
		TEST_VM_MODE="$(TEST_VM_MODE)" TEST_VM_INITRD="$(TEST_VM_INITRD)" \
		TEST_VM_HOST_BUNDLE="$(abspath $(TEST_VM_BUNDLE_DIR))" \
		$(if $(filter 0,$(LOCAL_STACK)),,$(ROOT)/testing/vm/stack.sh vm) $(ROOT)/testing/vm/run.sh
vm-console:
	$(Q)VM_NAME="$(VM_NAME)" \
		TEST_VM_WORK_DIR="$(TEST_VM_WORK_DIR)" $(ROOT)/testing/vm/run.sh --console

vm-ssh:
	$(Q)VM_NAME="$(VM_NAME)" \
		TEST_VM_WORK_DIR="$(TEST_VM_WORK_DIR)" $(ROOT)/testing/vm/run.sh --ssh

vm-enroll:
	$(Q)VM_NAME="$(VM_NAME)" \
		TEST_VM_WORK_DIR="$(TEST_VM_WORK_DIR)" $(ROOT)/testing/vm/run.sh --enroll

vm-sbom:
	$(Q)VM_NAME="$(VM_NAME)" \
		TEST_VM_WORK_DIR="$(TEST_VM_WORK_DIR)" $(ROOT)/testing/vm/run.sh --sbom

xtop:
	+$(Q)$(MAKE) -s -C $(ROOT)/tools/xtop
	$(Q)TEST_VM_HOST_PRIVATE_DIR="$(TEST_VM_HOST_PRIVATE_DIR)" $(ROOT)/testing/vm/stack.sh xtop

# SHIELDS names Beefiles and directories of them, relative to the checkout
# root unless absolute; without it, every shield under upatches/.
shields:
	$(Q)TEST_VM_HOST_PRIVATE_DIR="$(TEST_VM_HOST_PRIVATE_DIR)" $(ROOT)/testing/vm/stack.sh shields \
		$(foreach shield,$(SHIELDS),'$(call root-path,$(shield))')

define run-target-vm
VM_MODE=$(or $(4),$(if $(filter $(1),$(VM_SERVE_SUITES)),serve,test)) \
		TEST_VM_SUITE="$(1)" VM_VERBOSE="$(TEST_VM_VERBOSE)" VM_NAME="$(2)" VM_TENANT="$(VM_TENANT)" \
		TEST_VM_INITRD="$(3)" \
		TEST_VM_KERNEL="$(abspath $(VM_KERNEL_IMAGE))" \
		TEST_VM_KERNEL_ARTIFACT_DIR="$(abspath $(VM_KERNEL_ARTIFACT_DIR))" \
		TEST_VM_WORK_DIR="$(TEST_VM_WORK_DIR)" \
		TEST_VM_RUNTIME_CACHE_DIR="$(TEST_VM_RUNTIME_CACHE_DIR)" \
		TEST_VM_MAP_EXPORT_ENDPOINT="$(TEST_VM_MAP_EXPORT_ENDPOINT)" \
		TEST_VM_MAP_EXPORT_TENANT_ID="$(TEST_VM_MAP_EXPORT_TENANT_ID)" \
		TEST_VM_MAP_EXPORT_INSECURE="$(TEST_VM_MAP_EXPORT_INSECURE)" \
		TEST_VM_MAP_EXPORT_CA="$(TEST_VM_MAP_EXPORT_CA)" \
		TEST_VM_OCI_CA="$(TEST_VM_OCI_CA)" \
		TEST_VM_BPM_OCI_REPOSITORY="$(TEST_VM_BPM_OCI_REPOSITORY)" \
		TEST_VM_BPM_OCI_INDEX_REPOSITORY="$(TEST_VM_BPM_OCI_INDEX_REPOSITORY)" \
		TEST_VM_BPM_OCI_INDEX_CERT="$(TEST_VM_BPM_OCI_INDEX_CERT)" \
		TEST_VM_MODE="$(TEST_VM_MODE)" \
		TEST_VM_HOST_BUNDLE="$(abspath $(TEST_VM_BUNDLE_DIR))" \
		$(ROOT)/testing/vm/run.sh
endef

# The tiers: the unit tests, the tests of the scripts CI runs, the families
# of functional tests in number order, and the end-to-end tests. A test with
# a target number (t?1??) runs in a VM its family boots from the bundle, so
# no test finds what another family left behind; tpm boots a second VM
# before init, without the initrd, for the TPM register tests. VM=0 leaves
# out every test that boots a VM. BACKEND=0 leaves out the SQL tests of
# tools/backend, which need docker or podman and read no C.
VM ?= 1
BACKEND ?= 1
UNIT_SUITES := $(sort $(basename $(notdir $(filter-out %/unit.c, \
	$(wildcard $(ROOT)/testing/unit/*.c)))))
family-list = $(shell cd $(ROOT)/testing/functional && \
	ls */t[0-9]$(1)[0-9][0-9]-*.sh | \
	awk -F/ '{ print substr($$2, 2, 1), $$1 }' | sort -u | cut -d' ' -f2)
FAMILIES := $(call family-list,[0-9])
CI_BPM_FAMILIES := $(filter bpm bpm-%,$(FAMILIES))
VM_SUITES := $(call family-list,1) end2end
# The host runs the end-to-end VM's target tests over SSH, where it can act
# between them; the families' VMs run theirs themselves.
VM_SERVE_SUITES := end2end
vm-tests = $(if $(strip $(1)),$(if $(filter 0,$(VM)),:,\
	$(MAKE) $(addprefix vm-test-,$(1))),:)
.PHONY: functional-ci-1 functional-ci-2 functional-ci-3 functional-ci-4
.PHONY: $(addprefix unit/,$(UNIT_SUITES)) $(addprefix functional/,$(FAMILIES)) \
	$(addprefix vm-test-,register $(VM_SUITES)) vm-node-end2end

all:
	+$(Q)$(MAKE) unit
	+$(Q)$(MAKE) ci-checks
	+$(Q)$(MAKE) functional
	+$(Q)$(MAKE) end2end
	+$(Q)$(MAKE) backend

unit: build-unit
	$(Q)$(ROOT)/testing/run-tests.sh unit

backend:
	+$(Q)$(if $(filter 0,$(BACKEND)),:,$(MAKE) -C $(ROOT)/tools/backend tests)

$(addprefix unit/,$(UNIT_SUITES)): unit/%: build-unit
	$(Q)$(ROOT)/testing/run-tests.sh unit/$*

# The tests of the scripts under .github/scripts, which need no build.
ci-checks:
	$(Q)$(ROOT)/testing/run-tests.sh ci-checks

functional: build-operator
	$(Q)$(ROOT)/testing/run-tests.sh functional
	+$(Q)$(call vm-tests,$(filter-out end2end,$(VM_SUITES)))

$(addprefix functional/,$(FAMILIES)): functional/%: build-operator
	$(Q)$(ROOT)/testing/run-tests.sh functional/$*
	+$(Q)$(call vm-tests,$(filter $*,$(VM_SUITES)))

# Keep the slow upatch and tamperproof VMs on their own runners, the
# upatch VMs two, which tests.sh boots at once. The last shard also picks
# up new families outside BPM.
CI_UPATCH_FAMILIES := upatch upatch-many
functional-ci-1: $(addprefix functional/,$(CI_UPATCH_FAMILIES))
functional-ci-2: functional/tamperproof
functional-ci-3: $(addprefix functional/,$(CI_BPM_FAMILIES))
functional-ci-4: $(addprefix functional/,$(filter-out $(CI_UPATCH_FAMILIES) tamperproof $(CI_BPM_FAMILIES),$(FAMILIES)))

# The end-to-end test boots the operator VM, which builds the operator
# package and alone gets the signing key on its own disk; while it serves,
# host.sh has it publish kernel-obs, runs node A and has it verify what
# node A attests. The host's own build plays the operator for the keepalive
# backend and for the tests host.sh runs against the other nodes. The goals
# host.sh boots the VMs with build nothing: all VMs boot this bundle, and a
# rebuild between them, for an input changed meanwhile, would replace the
# key the operator signs with and the targets trust.
end2end: build-operator
	$(Q)$(ROOT)/testing/run-tests.sh end2end
	+$(Q)$(if $(filter 0,$(VM)),:,$(MAKE) test-vm-bundle && \
		TEST_VM_HOST_BUNDLE="$(abspath $(TEST_VM_BUNDLE_DIR))" \
		TEST_VM_HOST_PRIVATE_DIR="$(abspath $(TEST_VM_HOST_PRIVATE_DIR))" \
		MAKE="$(MAKE)" $(ROOT)/testing/end2end/host.sh)

vm-operator-end2end:
	$(Q)VM_MODE=serve TEST_VM_ROLE=operator TEST_VM_INITRD=0 \
		VM_VERBOSE="$(TEST_VM_VERBOSE)" VM_NAME="$(VM_NAME)" \
		TEST_VM_SERVE_COMMAND="$(TEST_VM_SERVE_COMMAND)" \
		TEST_VM_PRIVATE_DIR="$(TEST_VM_PRIVATE_DIR)" \
		TEST_VM_OPERATOR_KEYS="$(abspath $(TEST_VM_HOST_PRIVATE_DIR))/operator-keys/keys" \
		TEST_VM_KERNEL="$(abspath $(VM_KERNEL_IMAGE))" \
		TEST_VM_WORK_DIR="$(TEST_VM_WORK_DIR)" \
		TEST_VM_RUNTIME_CACHE_DIR="$(TEST_VM_RUNTIME_CACHE_DIR)" \
		TEST_VM_MODE="$(TEST_VM_MODE)" \
		TEST_VM_HOST_BUNDLE="$(abspath $(TEST_VM_BUNDLE_DIR))" \
		$(ROOT)/testing/vm/run.sh

vm-test-end2end:
	$(Q)$(call run-target-vm,end2end,$(if $(VM_NAME),$(VM_NAME)-end2end),1)

# A node of the end-to-end run that end2end/host.sh boots and stops,
# prepared like the suite's VM, but it runs no tests and stays up until it
# is stopped. END2END_NODE=b is node B, with the core role, beside the
# suite's VM; edge is a fresh node with the edge role, after it.
END2END_NODE ?= b
vm-node-end2end:
	$(Q)$(if $(filter-out b edge,$(END2END_NODE)),$(error END2END_NODE must be b or edge))
	$(Q)TEST_VM_NODE_ROLE=$(if $(filter edge,$(END2END_NODE)),edge,core) \
		$(call run-target-vm,end2end,$(if $(VM_NAME),$(VM_NAME)-end2end-$(END2END_NODE)),1,node)

vm-test-tpm: vm-test-register

$(addprefix vm-test-,register $(filter-out end2end,$(VM_SUITES))): \
		vm-test-%: require-vm-kernel test-vm-bundle
	$(Q)$(call run-target-vm,$*,$(if $(VM_NAME),$(VM_NAME)-$*),$(if $(filter register,$*),0,1))

vm-stop:
	$(Q)VM_NAME="$(VM_NAME)" \
		TEST_VM_WORK_DIR="$(TEST_VM_WORK_DIR)" $(ROOT)/testing/vm/run.sh --stop

vm-clean:
	$(Q)VM_NAME="$(VM_NAME)" \
		TEST_VM_WORK_DIR="$(TEST_VM_WORK_DIR)" $(ROOT)/testing/vm/run.sh --clean

# The operator build and the bundle build compile in the same tree, one at
# a time.
BUILD_LOCK := $(ROOT)/build/.testing-build.lock

build-operator: build-host
	+$(Q)flock $(BUILD_LOCK) $(MAKE) -C $(ROOT) shirudo-build
	+$(Q)flock $(BUILD_LOCK) $(MAKE) -C $(ROOT) quote-check
	+$(Q)flock $(BUILD_LOCK) $(MAKE) -C $(ROOT) -f Makefile.shirudo test-helpers

# The BPF objects are compiled against the BTF of the test kernel, which
# has the signed-loader types a host's own kernel seldom has. Without one
# staged, and without a BTF or a vmlinux.h the caller names, the pinned
# kernel is downloaded; where that fails the build takes the BTF of the
# running kernel, as it did.
kernel-btf:
	$(Q)[ -n "$(BPF_VMLINUX_BTF)$(BPF_VMLINUX_H)" ] || \
		[ -s "$(ROOT)/artifacts/bpf-next-kernel-debs/vmlinux.btf" ] || \
		VM="$(VM)" $(ROOT)/testing/vm/kernel-artifact.sh fetch || \
		echo "no kernel artifact: building against the BTF of the running kernel" >&2

build-host: | kernel-btf
	$(Q)mkdir -p $(dir $(BUILD_LOCK))
	+$(Q)flock $(BUILD_LOCK) $(MAKE) -C $(ROOT) all

build-unit: build-host
	+$(Q)flock $(BUILD_LOCK) $(MAKE) -C $(ROOT) -f Makefile.shirudo unit-tests

test-helpers: | kernel-btf
	+$(Q)$(MAKE) -C $(ROOT) config
	+$(Q)$(MAKE) -C $(ROOT) -f Makefile.shirudo test-helpers

# The parsers of input from outside the host under libFuzzer, each target
# for FUZZ_SECONDS on its seed corpus and, with FUZZ_CORPUS=<dir>, on what
# earlier runs kept there; FUZZERS names the targets to run, all of them
# without it. Needs clang with its fuzzer runtime.
FUZZ_SECONDS ?= 60
FUZZERS ?=

fuzz: | kernel-btf
	+$(Q)$(MAKE) -C $(ROOT) config
	+$(Q)$(MAKE) -C $(ROOT) -f Makefile.shirudo fuzz-targets
	$(Q)sh $(ROOT)/testing/fuzz/run.sh $(FUZZ_SECONDS) $(FUZZERS)

# The same targets under AFL++, AFL_SECONDS each, FUZZERS and FUZZ_CORPUS
# as above. Each is built twice with AFL_CC, the second time logging its
# comparisons, which afl-fuzz -c runs beside the first to find the magic
# values and checksums the parsers compare input with. Needs AFL++ built
# for the clang the targets take, as .github/scripts/afl-deps.sh builds it.
AFL_CC ?= afl-clang-fast
AFL_SECONDS ?= 600

afl: | kernel-btf
	+$(Q)$(MAKE) -C $(ROOT) config
	+$(Q)$(MAKE) -C $(ROOT) -f Makefile.shirudo fuzz-targets \
		FUZZ_CC=$(AFL_CC) FUZZ_OUT=build/fuzz-afl
	+$(Q)AFL_LLVM_CMPLOG=1 $(MAKE) -C $(ROOT) -f Makefile.shirudo \
		fuzz-targets FUZZ_CC=$(AFL_CC) FUZZ_OUT=build/fuzz-afl-cmplog
	$(Q)sh $(ROOT)/testing/fuzz/afl.sh $(AFL_SECONDS) $(FUZZERS)

bundle: test-vm-bundle

help:
	@printf '%s\n' \
	  'Testing targets (make tests at the top runs the first):' \
	  '  make -C testing                         every test' \
	  '  make -C testing unit[/<suite>]          suites: $(UNIT_SUITES)' \
	  '  make -C testing ci-checks               the scripts CI runs' \
	  '  make -C testing functional[/<family>]   families: $(FAMILIES)' \
	  '  make -C testing functional-ci-<1-4>    one CI functional shard' \
	  '  make -C testing end2end' \
	  '  make -C testing backend                 the SQL tests of tools/backend' \
	  '  TEST_FILTER=<regex> selects test filenames (empty runs everything).' \
	  '  VM=0 leaves out the tests that boot a VM, which need root;' \
	  '  make -j boots several at once.' \
	  '  BACKEND=0 leaves out the backend tests, which need docker or podman.' \
	  '  make -C testing fuzz [FUZZ_SECONDS=60] [FUZZ_CORPUS=<dir>] [FUZZERS=<target>...]' \
	  '  make -C testing afl [AFL_SECONDS=600] [FUZZ_CORPUS=<dir>] [FUZZERS=<target>...]' \
	  '  make -C testing vm, vm-console, vm-ssh, vm-enroll, vm-sbom, vm-stop, or vm-clean' \
	  '  VM_KERNEL=bpf-next (default) selects the pinned CI kernel artifact,' \
	  '  fetched when artifacts/bpf-next-kernel-debs has none' \
	  '  make -C testing bundle or test-helpers' \
	  '  make -C testing stack-up, oci, telemetry, xtop or stack-down' \
	  '  make -C testing clean'

clean:
	$(Q)set -eu; \
		bundle_dir="$(abspath $(TEST_VM_BUNDLE_DIR))"; \
		mkdir -p "$$(dirname "$$bundle_dir")"; \
		exec 9>"$$bundle_dir.lock"; \
		flock 9; \
		rm -rf "$$bundle_dir" "$$bundle_dir.operator" \
			"$(abspath $(TEST_VM_HOST_PRIVATE_DIR))/operator-keys" \
			$(ROOT)/build/test-vm/end2end

.PHONY: oci telemetry stack-up stack-down xtop shields
stack-up: oci telemetry
	$(Q)TEST_VM_HOST_PRIVATE_DIR="$(TEST_VM_HOST_PRIVATE_DIR)" $(ROOT)/testing/vm/stack.sh env

oci telemetry:
	$(Q)TEST_VM_HOST_PRIVATE_DIR="$(TEST_VM_HOST_PRIVATE_DIR)" $(ROOT)/testing/vm/stack.sh $@
stack-down:
	$(Q)TEST_VM_HOST_PRIVATE_DIR="$(TEST_VM_HOST_PRIVATE_DIR)" $(ROOT)/testing/vm/stack.sh down
