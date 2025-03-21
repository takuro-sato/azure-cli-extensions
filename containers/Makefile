export TAG ?= latest
export REGISTRY ?= ghcr.io
export REPOSITORY ?= microsoft/confidential-aci-dashboard/test-containers

all: build push
.PHONY: all build push run build_networking

build_networking: networking.Dockerfile
	docker buildx build . -t $(REGISTRY)/$(REPOSITORY)/networking:$(TAG) -f networking.Dockerfile

build: build_networking

push: build
	docker push $(REGISTRY)/$(REPOSITORY)/networking:$(TAG)

run: build
	docker run --rm -i -p 80:80 $(REGISTRY)/networking:$(TAG)
