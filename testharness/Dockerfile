FROM python:3.9-alpine
RUN mkdir /app
WORKDIR /app
RUN pip install --upgrade pip
COPY requirements.txt /app
RUN pip install requests
RUN pip install -U boto3
RUN pip install -r requirements.txt
COPY . /app
EXPOSE 8080
CMD ["python", "testDriver.py"]