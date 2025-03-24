export TAG ?= latest
export REGISTRY ?= ghcr.io
export REPOSITORY ?= microsoft/confidential-aci-dashboard/test-containers

all: build push
.PHONY: all build push run_networking build_networking run_stress_server_alpine build_stress_server_alpine run_stress_server_ubuntu build_stress_server_ubuntu build_stress_noserver run_stress_noserver_alpine run_stress_noserver_ubuntu killall

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

build: build_networking build_stress_server_alpine build_stress_server_ubuntu build_stress_noserver

push: build
	docker push $(REGISTRY)/$(REPOSITORY)/networking:$(TAG)
	docker push $(REGISTRY)/$(REPOSITORY)/stress-tests-server-alpine:$(TAG)
	docker push $(REGISTRY)/$(REPOSITORY)/stress-tests-server-ubuntu:$(TAG)
	docker push $(REGISTRY)/$(REPOSITORY)/stress-tests-noserver-alpine:$(TAG)
	docker push $(REGISTRY)/$(REPOSITORY)/stress-tests-noserver-ubuntu:$(TAG)

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

killall:
	docker ps --format '{{ .ID }}' | xargs --no-run-if-empty docker stop -s KILL
