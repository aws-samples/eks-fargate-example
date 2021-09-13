# ETL on EKS and Fargate Test Harness

The data are from NOAA Geostationary Operational Environmental Satellites (GOES) 16 & 17 hosted on the [Registry of Open Data on AWS](https://registry.opendata.aws/noaa-goes/)

## Ingest
A web service that accepts netCDF4 files, creates a Data Availability Message on Kafka, and stores the raw file in EFS

## Transform
Receives the Data Availability Message from kafka, pulls the raw file from EFS, and converts the file to PNG. 
Creates a Data Availability Message for the PNG and puts the PNG on EFS. 

## Load 
Receives the Data Availability Message from kafka, pulls the raw PNG file from EFS, and writes it S3. 


## Build
```sh
build.sh -i <ingest version> -t <transform version> -l <load version> -r <reporistory url>
```

## Run

```sh
kubect apply -f ETL.yaml
```

## License

Copyright 2021 AWS

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.