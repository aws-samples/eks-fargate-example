# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

from kafka import KafkaProducer
from kafka import KafkaConsumer
from pathlib import Path
from botocore.config import Config
import json
import sys
import os
import boto3
import time

my_config = Config(
    region_name='us-east-2',
    signature_version='v4',
)

cloudwatch = boto3.client('cloudwatch', config=my_config)

Path("/data/output/").mkdir(parents=True, exist_ok=True)
incomingTopic = 'transform'
consumer = KafkaConsumer(incomingTopic,
                             group_id='efsload',
                             bootstrap_servers=['kafka-hs.eksfg-etl-bus:9093'],
                             enable_auto_commit=True,
                             value_deserializer=lambda m: json.loads(m.decode('ascii')))
print("Connected to transform topic Kafka at 'kafka-hs.eksfg-etl-bus:9093'" )


def postLatencyMetric(ingestTS, completeTS):
    latency=(completeTS-ingestTS)/1000
    print("posting latency:", latency)
    response = cloudwatch.put_metric_data(
    MetricData = [
        {
            'MetricName': 'ETLLatency',
            'Unit': 'Seconds',
            'Dimensions': [
                {
                    'Name': 'Storage',
                    'Value': 'EFS'
                }
            ],            
            'Value': latency
        },
    ],
    Namespace='eksfg'
)

while True: 
    try:
        for message in consumer:
            # message value and key are raw bytes -- decode if necessary!
            # e.g., for unicode: `message.value.decode('utf-8')`
            print ("%s:%d:%d: key=%s" % (message.topic, message.partition,
                                                  message.offset, message.key))
            finName=message.value['filename']
            fin = open(finName, "rb")                                      
            finobj=fin.read()
            filename = "/data/output/" + str(hash(finobj)) + ".png"
            f = open(filename, mode='wb')
            
            f.write(finobj)
            
            print ("Successfully wrote file to filesystem: " + filename)
            fin.close()
            os.remove(finName)
            print("remvoved " + finName)
            completeTS = int(time.time() * 1000)
            postLatencyMetric(message.value['ingestTS'], completeTS)
    except:
        print ("Unexpected Error:", sys.exc_info())

       