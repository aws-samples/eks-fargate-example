# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
import os
os.environ['MPLCONFIGDIR'] = "/data"
import matplotlib.pyplot as plt
import netCDF4
import requests
import xarray as xr
import io


bucket_name='noaa-goes16'
key='ABI-L1b-RadF/2021/125/03/OR_ABI-L1b-RadF-M6C03_G16_s20211250310194_e20211250319502_c20211250319551.nc'
resp = requests.get(f'https://{bucket_name}.s3.amazonaws.com/{key}')

# Load the dataset
nc4_ds = netCDF4.Dataset(key, memory = resp.content)
store = xr.backends.NetCDF4DataStore(nc4_ds)
DS = xr.open_dataset(store)
print (DS)

# make image
fig = plt.figure(figsize=(12, 12))
plt.imshow(DS.Rad, cmap='gray')
plt.axis('off')
image= io.BytesIO()

plt.savefig(image, dpi=300, facecolor='w', edgecolor='w', format='png')
image.seek(0)

f=open("out.png", mode='wb')
f.write(image.read())