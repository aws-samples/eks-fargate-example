# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

while getopts i:t:l:r:h flag
do
    case "${flag}" in
        i) ingest_version=${OPTARG};;
        t) transform_version=${OPTARG};;
        l) efsload_version=${OPTARG};;
        r) repo=${OPTARG};;
        h) echo "Usage: build.sh -i <ingest version> -t <transform version> -l <load version> -r <reporistory url>"
    esac
done

cd "$(dirname "$0")"

cp ETL.template.yaml ETL.yaml

cd efsload
./build.sh -v $efsload_version -r $repo

cd ../ingest
./build.sh -v $ingest_version -r $repo

cd ../transform 
./build.sh -v $transform_version -r $repo

cd "$(dirname "$0")"
