# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

import requests

url = 'http://localhost/message'
#url = 'http://a0f715eaff4514a84a68c2f36266f1c6-472988388.us-east-2.elb.amazonaws.com/message'
my_img = {'file': open('goes.jpg', 'rb')}
r = requests.post(url, files=my_img)

# convert server response into JSON format.
print(r)