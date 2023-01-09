#!/bin/bash
build() {
  local SERVICE=$(echo "$1" | sed 's/^Dockerfile_\(.*\)$/\1/')
  local VERSION=$(cat "version_$SERVICE" | tr -d '\r\n')
  echo $REGISTRY/$PROJECT/$SERVICE:${VERSION:-build}

  docker pull $REGISTRY/$PROJECT/$SERVICE:latest || true
  docker build \
    --tag $REGISTRY/$PROJECT/$SERVICE:${VERSION:-build} \
    --file $1 \
    --cache-from $REGISTRY/$PROJECT/$SERVICE:latest \
    .
  docker push $REGISTRY/$PROJECT/$SERVICE:${VERSION:-build}
  docker tag $REGISTRY/$PROJECT/$SERVICE:${VERSION:-build} $REGISTRY/$PROJECT/$SERVICE:latest
  docker push $REGISTRY/$PROJECT/$SERVICE:latest
}

REGISTRY=hub.lumigame.com
PROJECT=ldb
export $(grep -v '^#' .env.docker | xargs -d '\n')
echo "$HUB_TOKEN" | docker login -u "$HUB_LOGIN" --password-stdin $REGISTRY

if [ -z $1 ]; then
  for FILE in $(ls Dockerfile_*); do
    build $FILE
  done
else
  echo "Building single file $1"
  build $1
fi
