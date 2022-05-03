#!/bin/bash

set -e
set -o pipefail

# Variables.
DIR=${DIR:-"$(cd "$(dirname "$0")" && pwd)"}
ROOT_CERT_URL=${ROOT_CERT_URL:-"https://www.amazontrust.com/repository/AmazonRootCA1.pem"}
ROOT_CERT_NAME="aws-root-cert.pem"
ROOT_CERT_PATH="$DIR/$ROOT_CERT_NAME"
DEVICE_CERTS_DIRECTORY=${DEVICE_CERTS_DIRECTORY:-"$DIR/device-certs"}
CERTIFICATE_NAME=${CERTIFICATE_NAME:-"device-certificate"}
THING_NAME=${THING_NAME:-"thing-1234"}
AWS_IOT_ENDPOINT=$(aws iot describe-endpoint --endpoint-type iot:Data-ATS --query endpointAddress --output text)

# The help usage text.
USAGE="Initiates an MQTTS connection to AWS IoT using the generated device certificates.
Options :
    -t  (Optional) - the thing name to use
    -d  (Optional) - the path of the directory containing the device certificate"

# Retrieving arguments from the command-line.
while getopts ":t:d:h" o; do
  case "${o}" in
    t) THING_NAME=${OPTARG} ;;
    d) DEVICE_CERTS_DIRECTORY=${OPTARG} ;;
    h) echo "$USAGE"
       exit 0 ;;
   \?) echo "Invalid option: -$OPTARG" >&2
       exit 1 ;;
    :) echo "Option -$OPTARG requires an argument." >&2
       exit 1 ;;
  esac
done

# If it doesn't already exist, we download the AWS root certificate required
# to create a connection to AWS IoT, and for the local TLS agent to acknowledge
# that the remote platform is indeed AWS IoT, and not a man in the middle.
if [ ! -f "$ROOT_CERT_PATH" ]; then
  echo "[+] AWS Root Certificate not detected, downloading it ..."
  curl "$ROOT_CERT_URL" | tee "$ROOT_CERT_PATH"
  echo "[+] The AWS Root certificate has been successfully saved in the local directory ($ROOT_CERT_PATH)"
fi

# Connecting to AWS IoT using the generated certificates
# and publishing a message.
mosquitto_pub -d \
  --cafile "$DIR/$ROOT_CERT_NAME" \
  --cert "$DEVICE_CERTS_DIRECTORY/$CERTIFICATE_NAME.crt" \
  --key "$DEVICE_CERTS_DIRECTORY/$CERTIFICATE_NAME.key" \
  -h "$AWS_IOT_ENDPOINT" \
  -p 8883 \
  -t "$THING_NAME/telemetry" \
  -i "$THING_NAME" \
  --tls-version tlsv1.2 \
  -m "{ \"message\": \"Hello World !\" }"
