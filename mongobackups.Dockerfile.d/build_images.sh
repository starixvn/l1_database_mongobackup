#!/bin/bash
REGISTRY=hub.lumigame.com
PROJECT=ldb
export $(grep -v '^#' .env.docker | xargs -d '\n')
echo "$HUB_TOKEN" | docker login -u "$HUB_LOGIN" --password-stdin $REGISTRY

for FILE in $(ls Dockerfile_*)
do
  SERVICE=$(echo $FILE | sed 's/^Dockerfile_\(.*\)$/\1/')
  VERSION=$(cat version_$SERVICE | tr -d '\r\n')
  echo $SERVICE:$VERSION

  docker pull $REGISTRY/$PROJECT/$SERVICE:latest || true
  docker build \
    --tag $REGISTRY/$PROJECT/$SERVICE:$VERSION \
    --file $FILE \
    --cache-from $REGISTRY/$PROJECT/$SERVICE:latest \
    .
  docker push $REGISTRY/$PROJECT/$SERVICE:$VERSION
  docker tag $REGISTRY/$PROJECT/$SERVICE:$VERSION $REGISTRY/$PROJECT/$SERVICE:latest
  docker push $REGISTRY/$PROJECT/$SERVICE:latest
done
