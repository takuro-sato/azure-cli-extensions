export TAG ?= latest
export REGISTRY ?= cacidashboardaci.azurecr.io
export REPOSITORY ?= prebuilt-test-containers

all: build push
.PHONY: all build push build_networking run_networking run_stress_server_alpine build_stress_server_alpine run_stress_server_ubuntu build_stress_server_ubuntu build_stress_noserver run_stress_noserver_alpine run_stress_noserver_ubuntu build_info run_info build_ccf_verify_uvm run_ccf_verify_uvm killall

build_networking: networking.Dockerfile
	docker buildx build . -t $(REGISTRY)/$(REPOSITORY)/networking:$(TAG) -f networking.Dockerfile

build_stress_server_alpine: stress-tests-server-alpine.Dockerfile
	docker buildx build . -t $(REGISTRY)/$(REPOSITORY)/stress-tests-server-alpine:$(TAG) -f stress-tests-server-alpine.Dockerfile

build_stress_server_ubuntu: stress-tests-server-ubuntu.Dockerfile
	docker buildx build . -t $(REGISTRY)/$(REPOSITORY)/stress-tests-server-ubuntu:$(TAG) -f stress-tests-server-ubuntu.Dockerfile

build_stress_noserver: stress-tests-noserver.Dockerfile build_stress_server_alpine build_stress_server_ubuntu
	docker buildx build . -t $(REGISTRY)/$(REPOSITORY)/stress-tests-noserver-alpine:$(TAG) \
		-f stress-tests-noserver.Dockerfile \
		--build-arg BASE_IMAGE=$(REGISTRY)/$(REPOSITORY)/stress-tests-server-alpine:$(TAG)

	docker buildx build . -t $(REGISTRY)/$(REPOSITORY)/stress-tests-noserver-ubuntu:$(TAG) \
		-f stress-tests-noserver.Dockerfile \
		--build-arg BASE_IMAGE=$(REGISTRY)/$(REPOSITORY)/stress-tests-server-ubuntu:$(TAG)

build_info: info.Dockerfile info_check.sh check_entrypoint.sh
	docker buildx build . -t $(REGISTRY)/$(REPOSITORY)/info:$(TAG) -f info.Dockerfile

build_ccf_verify_uvm: ccf_verify_uvm.Dockerfile
	docker buildx build . -t $(REGISTRY)/$(REPOSITORY)/ccf_verify_uvm:$(TAG) -f ccf_verify_uvm.Dockerfile

build: build_networking build_stress_server_alpine build_stress_server_ubuntu build_stress_noserver build_info build_ccf_verify_uvm

push: build
	docker push $(REGISTRY)/$(REPOSITORY)/networking:$(TAG)
	docker push $(REGISTRY)/$(REPOSITORY)/stress-tests-server-alpine:$(TAG)
	docker push $(REGISTRY)/$(REPOSITORY)/stress-tests-server-ubuntu:$(TAG)
	docker push $(REGISTRY)/$(REPOSITORY)/stress-tests-noserver-alpine:$(TAG)
	docker push $(REGISTRY)/$(REPOSITORY)/stress-tests-noserver-ubuntu:$(TAG)
	docker push $(REGISTRY)/$(REPOSITORY)/info:$(TAG)
	docker push $(REGISTRY)/$(REPOSITORY)/ccf_verify_uvm:$(TAG)

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
