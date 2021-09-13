# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
while getopts v:r:a: flag
do
    case "${flag}" in
        v) version=${OPTARG};;
        r) repo=${OPTARG};;
        a) deploymentAccount=${OPTARG};;
    esac
done

if [[ -z "$version" || -z "$deploymentAccount" ]] ; then
  echo "usage: build.sh -v {version}  -a {deployment Account ID} [-r {container repo url}]"
  exit 2
fi

echo "Version: $version, Repo: $repo, Account: $deploymentAccount"

#Build a tag
if [ -z "$repo" ]; then
  tag="eksfg-test:$version"
else
  tag="$repo/eksfg-test:$version"
fi

echo $tag

#build image, tag it, and push it to repository
docker build -t eksfg-test .
docker tag eksfg-test:latest $tag
docker push $tag

#create a K8S manifest to match parameters
sed -i.orig "s/AWS_ACCOUNT/$deploymentAccount/g" testharness.template.yaml
sed -i "s#IMAGE_TAG#$tag#g" testharness.template.yaml
cp testharness.template.yaml testharness.yaml
mv testharness.template.yaml.orig testharness.template.yaml
 