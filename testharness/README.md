<!--Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.-->
<!--SPDX-License-Identifier: MIT-0-->
# ETL on EKS and Fargate Test Harness

The data are from NOAA Geostationary Operational Environmental Satellites (GOES) 16 & 17 hosted on the [Registry of Open Data on AWS](https://registry.opendata.aws/noaa-goes/)

Why not pull the files directly from the opendata registry? 
The intent is to create a RESTFUL endpoint via a K8S service for the extract service. This test harness conforms the opendata s3 interface to the desired service interface.

## Build
```sh
./build.sh <unique version> <repository url>
```

## Run

```sh
kubectl apply -f testharness.yaml
```

## License

Copyright 2021 AWS

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.