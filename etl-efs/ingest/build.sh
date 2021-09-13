# ##############################################################################
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

while getopts v:r: flag
do
    case "${flag}" in
        v) version=${OPTARG};;
        r) repo=${OPTARG};;
    esac
done

if [ -z "$version" ] ; then
  echo "usage: build.sh -v {version}  [-r {container repo url}]"
  exit 2
fi

echo "Version: $version, Repo: $repo"

#Build a tag
if [ -z "$repo" ]; then
  tag="eksfg-ingest:$version"
else
  tag="$repo/eksfg-ingest:$version"
fi

echo $tag

#build image, tag it, and push it to repository
docker build -t eksfg-ingest .
docker tag eksfg-ingest:latest $tag
docker push $tag

#create a K8S manifest to match parameters
sed -i "s/AWS_ACCOUNT/$deploymentAccount/g" ../ETL.yaml
sed -i "s#INGEST_IMAGE_TAG#$tag#g" ../ETL.yaml

 