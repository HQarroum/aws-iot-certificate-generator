#!/bin/bash

set -e
set -o pipefail

# Variables.
DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIRECTORY="$DIR"
ROOT_CERT_URL='https://www.amazontrust.com/repository/AmazonRootCA1.pem'
ROOT_CERT_NAME='aws-root-cert.pem'
ROOT_CERT_PATH="$OUTPUT_DIRECTORY/$ROOT_CERT_NAME"
DEVICE_CERTS_DIRECTORY="$DIR/device-certs"
CERTIFICATE_NAME='device-certificate'
THING_NAME='thing-1234'
PORT=8883
AWS_IOT_ENDPOINT=$(aws iot describe-endpoint --endpoint-type iot:Data-ATS --query endpointAddress --output text)

# If it doesn't already exist, we download the AWS root certificate required
# to create a connection to AWS IoT, and for the local TLS agent to acknowledge
# that the remote platform is indeed AWS IoT, and not a man in the middle.
if [ ! -f "$ROOT_CERT_PATH" ]; then
  echo "[+] AWS Root Certificate not detected, downloading it ..."
  curl $ROOT_CERT_URL | tee "$ROOT_CERT_PATH"
  echo "[+] The AWS Root certificate has been successfully saved in the local directory ($ROOT_CERT_PATH)"
fi

# Connecting to AWS IoT using the generated certificates
# and publishing a message.
mosquitto_pub -d \
  --cafile aws-root-cert.pem \
  --cert "$DEVICE_CERTS_DIRECTORY/$CERTIFICATE_NAME.crt" \
  --key "$DEVICE_CERTS_DIRECTORY/$CERTIFICATE_NAME.key" \
  -h $AWS_IOT_ENDPOINT \
  -p $PORT \
  -t $THING_NAME/telemetry \
  -i $THING_NAME \
  --tls-version tlsv1.2 \
  -m "{ \"message\": \"Hello World !\" }"
