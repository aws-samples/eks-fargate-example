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

print ("Starting transfrom service")


incomingTopic = 'ingest'
outgoingTopic = 'transform'

print("Kafka topics: ", incomingTopic, outgoingTopic)

producer = KafkaProducer(bootstrap_servers='kafka-hs.ab3-etl:9093')
consumer = KafkaConsumer(incomingTopic,
                             group_id='transform',
                             bootstrap_servers=['kafka-hs.ab3-etl:9093'],
                             enable_auto_commit=True)

print("Connected to Kafka at 'kafka-hs.ab3-etl:9093'" )
while True: 
    try: 
        print("Polling Kafka")
        for message in consumer:
            # message value and key are raw bytes -- decode if necessary!
            # e.g., for unicode: `message.value.decode('utf-8')`
            print ("%s:%d:%d: key=%s" % (message.topic, message.partition,
                                              message.offset, message.key))
            filename=message.value.decode()
            print("Filename: " + filename)    
            
            # Load the dataset
            nc4_ds = netCDF4.Dataset(filename)
            store = xr.backends.NetCDF4DataStore(nc4_ds)
            DS = xr.open_dataset(store)
            print (DS)
            
            # make image
            fig = plt.figure(figsize=(12, 12))
            plt.imshow(DS.Rad, cmap='gray')
            plt.axis('off')
            file_name="/data/"+ str(abs(hash(message.value))) + ".png"
            print("Saving file: " + file_name)
            plt.savefig(file_name, dpi=300, facecolor='w', edgecolor='w')
            plt.cla()
            plt.clf()
            plt.close()

            producer.send(outgoingTopic,file_name.encode())
            print ("Message sent")
    except:
            print ("Unexpected Error:", sys.exc_info()[0])

        

