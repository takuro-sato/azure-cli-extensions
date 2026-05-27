export TAG ?= latest
export REGISTRY ?= cacidashboardaci.azurecr.io
export REPOSITORY ?= prebuilt-test-containers

# Single platform per Make invocation. Re-run this Makefile on each architecture
# (e.g. linux/amd64 on x86_64, linux/arm64 on an ARM machine) to build a
# multi-arch image:
#
#   make push IMAGE_PLATFORM=linux/amd64   # on x86_64 → pushes :TAG-linux-amd64
#   make push IMAGE_PLATFORM=linux/arm64   # on arm64  → pushes :TAG-linux-arm64
#
# The `push` rule pushes arch-specific tags and then calls `merge_manifests`,
# which uses `docker buildx imagetools create` to produce the canonical :TAG.
IMAGE_PLATFORM ?= linux/amd64
PLATFORM_TAG := $(subst /,-,$(IMAGE_PLATFORM))

all: build login push_arch merge_manifests
.PHONY: all build login push push_arch merge_manifests build_networking run_networking run_stress_server_alpine build_stress_server_alpine run_stress_server_ubuntu build_stress_server_ubuntu build_stress_noserver run_stress_noserver_alpine run_stress_noserver_ubuntu build_info run_info build_ccf_verify_uvm run_ccf_verify_uvm killall

login:
	az acr login --name $(REGISTRY)

# --- build rules ------------------------------------------------------------
# All builds use --load to make the resulting (single-platform) image available
# in the local docker daemon under the unsuffixed :TAG. That keeps the local
# `run_*` targets working and lets later builds reference earlier ones as a
# base image without an extra push round-trip.

BUILD = docker buildx build --platform $(IMAGE_PLATFORM) --load .

build_networking: networking.Dockerfile
	$(BUILD) -t $(REGISTRY)/$(REPOSITORY)/networking:$(TAG) -f networking.Dockerfile

build_stress_server_alpine: stress-tests-server-alpine.Dockerfile
	$(BUILD) -t $(REGISTRY)/$(REPOSITORY)/stress-tests-server-alpine:$(TAG) -f stress-tests-server-alpine.Dockerfile

build_stress_server_ubuntu: stress-tests-server-ubuntu.Dockerfile
	$(BUILD) -t $(REGISTRY)/$(REPOSITORY)/stress-tests-server-ubuntu:$(TAG) -f stress-tests-server-ubuntu.Dockerfile

build_stress_noserver: stress-tests-noserver.Dockerfile build_stress_server_alpine build_stress_server_ubuntu
	$(BUILD) -t $(REGISTRY)/$(REPOSITORY)/stress-tests-noserver-alpine:$(TAG) \
		-f stress-tests-noserver.Dockerfile \
		--build-arg BASE_IMAGE=$(REGISTRY)/$(REPOSITORY)/stress-tests-server-alpine:$(TAG)

	$(BUILD) -t $(REGISTRY)/$(REPOSITORY)/stress-tests-noserver-ubuntu:$(TAG) \
		-f stress-tests-noserver.Dockerfile \
		--build-arg BASE_IMAGE=$(REGISTRY)/$(REPOSITORY)/stress-tests-server-ubuntu:$(TAG)

build_info: info.Dockerfile info_check.sh check_entrypoint.sh
	$(BUILD) -t $(REGISTRY)/$(REPOSITORY)/info:$(TAG) -f info.Dockerfile

build_ccf_verify_uvm: ccf_verify_uvm.Dockerfile
ifeq ($(IMAGE_PLATFORM),linux/arm64)
	@echo "Skipping ccf_verify_uvm: Dockerfile downloads x86-only RPM (not supported on $(IMAGE_PLATFORM))"
else
	$(BUILD) -t $(REGISTRY)/$(REPOSITORY)/ccf_verify_uvm:$(TAG) -f ccf_verify_uvm.Dockerfile
endif

build: build_networking build_stress_server_alpine build_stress_server_ubuntu build_stress_noserver build_info build_ccf_verify_uvm

# --- push rule --------------------------------------------------------------
# For each image:
#   1. Re-tag the just-built local image with the arch suffix (e.g. -linux-amd64)
#      and push that single-platform tag to the registry.
#   2. `merge_manifests` combines available arch-specific tags into the
#      canonical :TAG using `docker buildx imagetools create`.

# x86-only images (skipped when building for ARM)
X86_ONLY_IMAGES = ccf_verify_uvm

IMAGES = \
	networking \
	stress-tests-server-alpine \
	stress-tests-server-ubuntu \
	stress-tests-noserver-alpine \
	stress-tests-noserver-ubuntu \
	info

ifeq ($(IMAGE_PLATFORM),linux/arm64)
IMAGES_TO_PUSH = $(filter-out $(X86_ONLY_IMAGES),$(IMAGES))
else
IMAGES_TO_PUSH = $(IMAGES) $(X86_ONLY_IMAGES)
endif

# Push arch-specific tags for all images (no manifest merge).
# Does NOT touch the canonical :TAG manifest — that is handled by the
# separate `merge-manifests` workflow once all platforms are built.
# Uses `set -e` so a tag/push failure for any image aborts immediately rather
# than being masked by a later successful push.
push_arch: build
	@set -e; for img in $(IMAGES_TO_PUSH); do \
		docker tag $(REGISTRY)/$(REPOSITORY)/$$img:$(TAG) $(REGISTRY)/$(REPOSITORY)/$$img:$(TAG)-$(PLATFORM_TAG); \
		docker push $(REGISTRY)/$(REPOSITORY)/$$img:$(TAG)-$(PLATFORM_TAG); \
	done

# Legacy alias so existing callers of `make push` keep working.
push: push_arch merge_manifests

# Merge per-platform arch-specific tags into a single multi-arch manifest.
# This checks remote tag availability first, so running on x86 without a local
# arm64 image is fine as long as the arm64 tag exists in the registry.
define merge_one
	@set -e; \
	target="$(REGISTRY)/$(REPOSITORY)/$(1):$(TAG)"; \
	amd64_ref="$(REGISTRY)/$(REPOSITORY)/$(1):$(TAG)-linux-amd64"; \
	arm64_ref="$(REGISTRY)/$(REPOSITORY)/$(1):$(TAG)-linux-arm64"; \
	refs=""; \
	if docker buildx imagetools inspect "$$amd64_ref" >/dev/null 2>&1; then \
		refs="$$refs $$amd64_ref"; \
	fi; \
	if docker buildx imagetools inspect "$$arm64_ref" >/dev/null 2>&1; then \
		refs="$$refs $$arm64_ref"; \
	fi; \
	if [ -z "$$refs" ]; then \
		echo "Skipping $$target: no platform tags found yet"; \
	else \
		echo "Merging$$refs -> $$target"; \
		docker buildx imagetools create -t "$$target" $$refs; \
	fi

endef
define merge_one_x86_only
	@set -e; \
	target="$(REGISTRY)/$(REPOSITORY)/$(1):$(TAG)"; \
	amd64_ref="$(REGISTRY)/$(REPOSITORY)/$(1):$(TAG)-linux-amd64"; \
	if docker buildx imagetools inspect "$$amd64_ref" >/dev/null 2>&1; then \
		echo "Merging $$amd64_ref -> $$target"; \
		docker buildx imagetools create -t "$$target" "$$amd64_ref"; \
	else \
		echo "Skipping $$target: missing $$amd64_ref"; \
	fi

endef

merge_manifests:
	$(foreach img,$(IMAGES),$(call merge_one,$(img)))
	$(foreach img,$(X86_ONLY_IMAGES),$(call merge_one_x86_only,$(img)))

# --- local run rules --------------------------------------------------------
# Note: these will only work when IMAGE_PLATFORM matches the host arch (the
# default), because --load loads a single-platform image into local docker.

run_networking: build_networking
	docker run --rm -i -p 80:80 $(REGISTRY)/$(REPOSITORY)/networking:$(TAG)

run_stress_server_alpine: build_stress_server_alpine
	docker run --rm -i -p 80:80 $(REGISTRY)/$(REPOSITORY)/stress-tests-server-alpine:$(TAG) bash workload_cpu.sh

run_stress_server_ubuntu: build_stress_server_ubuntu
	docker run --rm -i -p 80:80 $(REGISTRY)/$(REPOSITORY)/stress-tests-server-ubuntu:$(TAG) bash workload_cpu.sh

run_stress_noserver_alpine: build_stress_noserver
	docker run --rm -i -p 80:80 $(REGISTRY)/$(REPOSITORY)/stress-tests-noserver-alpine:$(TAG) bash workload_cpu.sh

run_stress_noserver_ubuntu: build_stress_noserver
	docker run --rm -i -p 80:80 $(REGISTRY)/$(REPOSITORY)/stress-tests-noserver-ubuntu:$(TAG) bash workload_cpu.sh

run_info: build_info
	docker run --rm --privileged -i $(REGISTRY)/$(REPOSITORY)/info:$(TAG)

run_ccf_verify_uvm: build_ccf_verify_uvm
	docker run --rm -i $(REGISTRY)/$(REPOSITORY)/ccf_verify_uvm:$(TAG)

killall:
	docker ps --format '{{ .ID }}' | xargs --no-run-if-empty docker stop -s KILL
