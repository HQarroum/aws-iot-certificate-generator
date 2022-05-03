#!/bin/bash

set -e
set -o pipefail

# Variables.
DIR="$(cd "$(dirname "$0")" && pwd)"
OPENSSL_CONFIG="$DIR/config/openssl-device.conf"
OUTPUT_DIRECTORY="$DIR/device-certs"
CA_CERTIFICATE_PATH="$DIR/ca-certs/ca-certificate.pem"
CA_PRIVATE_KEY_PATH="$DIR/ca-certs/ca-certificate.key"

# The help usage text.
USAGE="Generates device certificates compatible with the AWS IoT Just-In-Time-Registration process given Root CA certificates.
Options :
    -c  (Optional) - the path to the OpenSSL config file to use
    -a  (Optional) - the path of the CA certificate
    -p  (Optional) - the path of the CA private key
    -o  (Optional) - the output directory to write the certificates to"

# Exports the generated certificate output paths.
# This function is called each time the `$OUTPUT_DIRECTORY`
# variable is updated.
function export_file_paths() {
  DEVICE_CERTIFICATE_PATH="$OUTPUT_DIRECTORY/device-certificate.pem"
  DEVICE_PRIVATE_KEY_PATH="$OUTPUT_DIRECTORY/device-certificate.key"
  DEVICE_CERTIFICATE_SERIAL_PATH="$OUTPUT_DIRECTORY/device-certificate.srl"
  DEVICE_CSR_PATH="$OUTPUT_DIRECTORY/device.csr"
}

# Retrieving arguments from the command-line.
while getopts ":c:a:p:o:h" o; do
  case "${o}" in
    o) OUTPUT_DIRECTORY=${OPTARG} ;;
    c) OPENSSL_CONFIG=${OPTARG} ;;
    a) CA_CERTIFICATE_PATH=${OPTARG} ;;
    p) CA_PRIVATE_KEY_PATH=${OPTARG} ;;
    h) echo "$USAGE"
       exit 0 ;;
   \?) echo "Invalid option: -$OPTARG" >&2
       exit 1 ;;
    :) echo "Option -$OPTARG requires an argument." >&2
       exit 1 ;;
  esac
done

# Verifying that the CA certificate and private key exists.
if [ ! -f "$CA_CERTIFICATE_PATH" ] || [ ! -f "$CA_PRIVATE_KEY_PATH" ]; then
  echo "[!] The CA certificate or the CA private key does not exist, did you run create-and-register-ca.sh ?"
  exit 1
fi

# Initializing the output file paths.
export_file_paths

# Creating the output directory.
mkdir -p "$OUTPUT_DIRECTORY"

# Creates a new X.509 private and public key
# signed by the generated CA and stores them
# in the output directory.
function create_device_certificate() {
  openssl genrsa -out "$DEVICE_PRIVATE_KEY_PATH" 2048

  # Creating a CSR.
  openssl req \
    -config "$OPENSSL_CONFIG" \
    -new \
    -key "$DEVICE_PRIVATE_KEY_PATH" \
    -out "$DEVICE_CSR_PATH"

  # Creating the device certificate using the given Certificate Authority.
  openssl x509 \
    -req \
    -in "$DEVICE_CSR_PATH" \
    -CA "$CA_CERTIFICATE_PATH" \
    -CAkey "$CA_PRIVATE_KEY_PATH" \
    -CAcreateserial \
    -CAserial "$DEVICE_CERTIFICATE_SERIAL_PATH" \
    -out "$DEVICE_CERTIFICATE_PATH" \
    -days 365 \
    -sha256

  echo "[+] Created a new device certificate ($DEVICE_CERTIFICATE_PATH)."
}

# Create the device certificate.
create_device_certificate
