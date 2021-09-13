from flask import Flask, flash, request, redirect, url_for
import threading
import requests
import time
import boto3

app = Flask(__name__)

currentrate = 0.1
# get list of s3 objects from file
print("reading bucket list file")
bucketListFile = open("inputbuckets.txt", "r")
bucketList = []
for line in bucketListFile:
  bucketList.append(line)

#Configure S3 buckets
s3 = boto3.resource('s3')
goes16bucket = "noaa-goes16"

loopcounter = 0

url = 'http://etl-ingest.eksfg-etl/message'
def datapump():
    while True:
        global loopcounter
        print("Reading: ", "s3://",goes16bucket,"/",bucketList[loopcounter] , sep='')
        # obj = s3.Object('njdavids-eksfg','7547259005708861619.jpg')
        obj = s3.Object(goes16bucket, str(bucketList[loopcounter]).strip())
        my_img = obj.get()['Body'].read()
        print("Sending file to ", url)    
        r = requests.post(url, files={'file': my_img})
        time.sleep(1/currentrate)
        loopcounter=loopcounter+1
        
        
@app.route('/')
def index():
    return 'I am alive'
    
@app.route('/rate', methods = ['POST','GET'])
def rate():
    global currentrate
    if request.method == 'GET':
        print ("GET", currentrate, "per second")
        return str(currentrate) + " messages per second"
        
    if request.method == 'POST':
        print(request)
        content = request.json
        print(content)
        newrate = content['value']
        currentrate = newrate
        print(newrate)
        return str(newrate) + " messages per second"
    
if __name__ == '__main__':
    x = threading.Thread(target=datapump)
    print("Starting datapump thread")
    x.start()
    app.run(host="0.0.0.0", port=8080)