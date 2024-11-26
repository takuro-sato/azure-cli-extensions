#!/bin/bash

if [ -z "$REGISTRY" ]; then
  export REGISTRY=cacitesting.azurecr.io
fi
if [ -z "$REPO_BASE" ]; then
  export REPO_BASE=workload-sidecar-with-fragments
fi
export REPO=$REPO_BASE/primary
if [ -z "$TAG" ]; then
  export TAG=some-tag
fi
export IMAGE=$REGISTRY/$REPO:$TAG
echo Workload image: $IMAGE

export SIDECAR_REPO_A=$REPO_BASE/secondary-a
export SIDECAR_REPO_B=$REPO_BASE/secondary-b
export SIDECAR_TAG=$TAG
export SIDECAR_IMAGE_A=$REGISTRY/$SIDECAR_REPO_A:$SIDECAR_TAG
export SIDECAR_IMAGE_B=$REGISTRY/$SIDECAR_REPO_B:$SIDECAR_TAG
echo Sidecar image A: $SIDECAR_IMAGE_A
echo Sidecar image B: $SIDECAR_IMAGE_B

export FEED=$REGISTRY/$REPO_BASE

if [ -z "$DEPLOYMENT_NAME" ]; then
  export DEPLOYMENT_NAME=test-deployment
fi
if [ -z "$RESOURCE_GROUP" ]; then
  export RESOURCE_GROUP=c-aci-dashboard
fi
