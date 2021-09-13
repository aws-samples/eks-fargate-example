# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
FROM python:3.9-alpine
RUN mkdir /app
WORKDIR /app
COPY requirements.txt /app
RUN pip install --upgrade pip
RUN pip install -U kafka-python
RUN pip install -r requirements.txt


COPY . /app
EXPOSE 5000
CMD ["python", "ingest.py"]