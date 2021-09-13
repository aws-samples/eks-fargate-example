# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
from kafka import KafkaProducer
from kafka import KafkaConsumer
import json
import matplotlib.pyplot as plt
import netCDF4
import xarray as xr
import io
import time
import sys
import os
import gc

print ("Starting transfrom service")


incomingTopic = 'ingest'
outgoingTopic = 'transform'

print("Kafka topics: ", incomingTopic, outgoingTopic)

producer = KafkaProducer(bootstrap_servers='kafka-hs.eksfg-etl-bus:9093',
            value_serializer=lambda m: json.dumps(m).encode('ascii'))
consumer = KafkaConsumer(incomingTopic,
                             bootstrap_servers=['kafka-hs.eksfg-etl-bus:9093'],
                             enable_auto_commit=True,
                             value_deserializer=lambda m: json.loads(m.decode('ascii')))

print("Connected to Kafka at 'kafka-hs.eksfg-etl-bus:9093'" )
def run():
    while True: 
        try: 
            print("Polling Kafka")
            for message in consumer:
                transformImage(message)
                print ("cleaning mem")
                gc.collect()
        except:
                print ("Unexpected Error:", sys.exc_info()[0])
def transformImage(message):
    # message value and key are raw bytes -- decode if necessary!
    # e.g., for unicode: `message.value.decode('utf-8')`
    print ("%s:%d:%d: key=%s" % (message.topic, message.partition,
                                      message.offset, message.key))
    filename=message.value['filename']
    
    print("Filename: " + filename)    
    
    # Load the dataset
    nc4_ds = netCDF4.Dataset(filename)
    store = xr.backends.NetCDF4DataStore(nc4_ds)
    DS = xr.open_dataset(store)
    # make image
    fig = plt.figure(figsize=(12, 12))
    plt.imshow(DS.Rad, cmap='gray')
    plt.axis('off')
    file_name="/data/"+ str(abs(hash(fig))) + ".png"
    print("Saving file: " + file_name)
    plt.savefig(file_name, dpi=300, facecolor='w', edgecolor='w')
    plt.cla()
    plt.clf()
    plt.close('all')

    producer.send(outgoingTopic,{'filename':file_name, 'ingestTS': message.value['ingestTS']})
    print ("Message sent")
    
    # os.remove(filename)
    # print ("Removed: " + filename)
if __name__ == '__main__':
    run()


