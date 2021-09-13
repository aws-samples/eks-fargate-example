from flask import Flask, flash, request, redirect, url_for
from kafka import KafkaProducer
import time
import json


app = Flask(__name__)

producer = KafkaProducer(bootstrap_servers='kafka-hs.eksfg-etl-bus:9093',
            value_serializer=lambda m: json.dumps(m).encode('ascii'))
print("Connected to Kafka at kafka-hs.eksfg-etl-bus:9093" )
# producer.send('sample', b'Hello, World!')

@app.route('/')
def index():
    return 'Hello World'
    
@app.route('/message', methods = ['POST','GET'])
def message():
    if request.method == 'POST':
        ingestTS = int(time.time() * 1000)
        print ("received post")
        # check if the post request has the file part
        if 'file' not in request.files:
            print('No file part')
            return redirect(request.url)
        file = request.files['file']
        filecontent = file.read()
        filename="/data/"+ str(abs(hash(filecontent)))+".nc"
        print ("Saving file to " + filename)
        
        fout = open(filename,'wb')
        
        fout.write(filecontent)
        fout.close()
        
        print ("Sending kafka message")
        resp=producer.send('ingest', {'filename':filename, "ingestTS": ingestTS})
        print(resp)
        print ("Sent message to kafka")
        return "Success"

    return "Error"
    
if __name__ == '__main__':
    app.run(host="0.0.0.0", port=5000)
    