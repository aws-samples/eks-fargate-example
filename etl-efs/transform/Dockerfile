# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

FROM python:3.9.6-slim-bullseye
RUN mkdir /app
WORKDIR /app
COPY requirements.txt /app
RUN pip install --upgrade pip
RUN pip install -U kafka-python
RUN pip install -r requirements.txt
RUN pip install -U netCDF4
RUN pip install -U matplotlib
RUN pip install -U xarray
RUN pip install -U lz4

COPY . /app

CMD ["python", "transform.py"]