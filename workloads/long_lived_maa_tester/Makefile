export REGISTRY ?= cacidashboardaci.azurecr.io
export REPOSITORY ?= maa-tester
export TAG ?= latest

all: login build_maa_tester push

.PHONY: all login build_maa_tester push

login:
	az acr login --name ${REGISTRY}

build_maa_tester: maa_tester.Dockerfile main.py ../../azure/MAA-endpoints.csv
	cp ../../azure/MAA-endpoints.csv MAA-endpoints.csv
	docker buildx build . -t $(REGISTRY)/$(REPOSITORY):$(TAG) -f maa_tester.Dockerfile

push:
	docker push $(REGISTRY)/$(REPOSITORY):$(TAG)
