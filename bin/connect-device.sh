#!/bin/bash

set -e
set -o pipefail

# Variables.
DIR=$(cd "$(dirname "$0")" && pwd)
AWS_IOT_CA_URL=${AWS_IOT_CA_URL:-"https://www.amazontrust.com/repository/AmazonRootCA1.pem"}
AWS_IOT_CA_PATH="$DIR/aws-root-cert.pem"
CERTIFICATE_PATH="$DIR/device-certs/device-certificate.crt"
PRIVATE_KEY_PATH="$DIR/device-certs/device-certificate.key"
THING_NAME="thing-1234"
AWS_IOT_ENDPOINT=$(aws iot describe-endpoint --endpoint-type iot:Data-ATS --query endpointAddress --output text)

# The help usage text.
USAGE="Initiates an MQTTS connection and publishes messages to AWS IoT using the generated device certificates.
Options :
    -t  (Optional) - the thing name to use
    -c  (Optional) - the path to the device certificate
    -p  (Optional) - the path to the device private key"

# Retrieving arguments from the command-line.
while getopts ":t:c:p:h" o; do
  case "${o}" in
    t) THING_NAME=${OPTARG} ;;
    c) CERTIFICATE_PATH=${OPTARG} ;;
    p) PRIVATE_KEY_PATH=${OPTARG} ;;
    h) echo "$USAGE"
       exit 0 ;;
   \?) echo "Invalid option: -$OPTARG" >&2
       exit 1 ;;
    :) echo "Option -$OPTARG requires an argument." >&2
       exit 1 ;;
  esac
done

# Verifying that the certificate and private key exists.
if [ ! -f "$CERTIFICATE_PATH" ] || [ ! -f "$PRIVATE_KEY_PATH" ]; then
  echo "[!] The device certificate does not exist. Did you execute the 'create-device-certificate.sh' ?"
  exit 1
fi

# If it doesn't already exist, we download the AWS root certificate required
# to create a connection to AWS IoT, and for the local TLS agent to acknowledge
# that the remote platform is indeed AWS IoT, and not a man in the middle.
if [ ! -f "$AWS_IOT_CA_PATH" ]; then
  echo "[+] AWS Root Certificate not detected, downloading it ..."
  wget "$AWS_IOT_CA_URL" -O "$AWS_IOT_CA_PATH" -o /dev/null
  echo "[+] The AWS Root certificate has been successfully saved locally"
fi

# Connects to AWS IoT using the generated certificates
# and publishing a message.
function connect_device() {
  mosquitto_pub -d \
    --cafile "$AWS_IOT_CA_PATH" \
    --cert "$CERTIFICATE_PATH" \
    --key "$PRIVATE_KEY_PATH" \
    --host "$AWS_IOT_ENDPOINT" \
    -p 8883 \
    -t "$THING_NAME/telemetry" \
    -i "$THING_NAME" \
    --tls-version tlsv1.2 \
    --repeat 10 \
    --repeat-delay 5 \
    --message "{ \"message\": \"Hello World !\" }"
}

# Connecting and publishing a message.
connect_device
