REGISTRY=git3.nexdev.net:5050/l1/database/images
for FILE in $(ls Dockerfile_*)
do
  SERVICE=$(echo $FILE | sed 's/^Dockerfile_\(.*\)$/\1/')
  VERSION=$(cat version_$SERVICE | tr -d '\r\n')
  echo $SERVICE:$VERSION

  echo "ZPffaRzjxMpGs2X8bQ_E" | docker login -u billy.bui --password-stdin git3.nexdev.net:5050
  docker pull $REGISTRY/$SERVICE:latest || true
  docker build \
    --tag $REGISTRY/$SERVICE:$VERSION \
    --file $FILE \
    --cache-from $REGISTRY/$SERVICE:latest \
    .
  docker push $REGISTRY/$SERVICE:$VERSION
  docker tag $REGISTRY/$SERVICE:$VERSION $REGISTRY/$SERVICE:latest
  docker push $REGISTRY/$SERVICE:latest
done
