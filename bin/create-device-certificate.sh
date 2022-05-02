#!/bin/bash

set -e
set -o pipefail

# Variables.
DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_CA_DIRECTORY="$DIR/ca-certs"
OPENSSL_CONFIG="$DIR/config/openssl-device.conf"
OUTPUT_DIRECTORY="$DIR/device-certs"
CACERT_NAME='ca-certificate'
CERTIFICATE_NAME='device-certificate'

# The help usage text.
USAGE="Generates device certificates compatible with the AWS IoT Just-In-Time-Registration process given Root CA certificates.
Options :
    -o  (Optional) - the path to the OpenSSL config file to use
    -d  (Optional) - the path of the directory containing the Root CA certificates
    -r  (Optional) - the location in which the AWS IoT Root CA will be downloaded"

# Retrieving arguments from the command-line.
while getopts ":d:r:o:h" o; do
  case "${o}" in
    r) ROOT_CERT_NAME=${OPTARG} ;;
    o) OPENSSL_CONFIG=${OPTARG} ;;
    d) ROOT_CA_DIRECTORY=${OPTARG} ;;
    h) echo "$USAGE"
       exit 0 ;;
   \?) echo "Invalid option: -$OPTARG" >&2
       exit 1 ;;
    :) echo "Option -$OPTARG requires an argument." >&2
       exit 1 ;;
  esac
done

# Verifying that the Root CA directory exists.
if [ ! -d $ROOT_CA_DIRECTORY ]; then
  echo "[!] The Root CA directory ($ROOT_CA_DIRECTORY) does not exist. Did you execute the 'create-and-register-ca.sh' script first to generate a CA ?"
  exit 1
fi

# Verifying that the Root CA directory contains certificates.
if [ ! -f $ROOT_CA_DIRECTORY/$CACERT_NAME.pem ] || [ ! -f $ROOT_CA_DIRECTORY/$CACERT_NAME.key ]; then
  echo "[!] The Root CA directory ($ROOT_CA_DIRECTORY) does not contain valid Root CA certificates (expected '$ROOT_CA_DIRECTORY/$CACERT_NAME.pem' and '$ROOT_CA_DIRECTORY/$CACERT_NAME.key' to exist)."
  exit 1
fi

# Creating the output directory.
mkdir -p $OUTPUT_DIRECTORY

# Creates a new X.509 private and public key
# signed by the generated CA and stores them
# in the output directory.
function create_device_certificate() {
  openssl genrsa -out $OUTPUT_DIRECTORY/$CERTIFICATE_NAME.key 2048

  # Creating a CSR.
  openssl req \
    -config $OPENSSL_CONFIG \
    -new \
    -key $OUTPUT_DIRECTORY/$CERTIFICATE_NAME.key \
    -out $OUTPUT_DIRECTORY/$CERTIFICATE_NAME.csr

  # Creating the device certificate using the given Certificate Authority.
  openssl x509 \
    -req \
    -in $OUTPUT_DIRECTORY/$CERTIFICATE_NAME.csr \
    -CA $ROOT_CA_DIRECTORY/$CACERT_NAME.pem \
    -CAkey $ROOT_CA_DIRECTORY/$CACERT_NAME.key \
    -CAcreateserial \
    -CAserial $OUTPUT_DIRECTORY/$CERTIFICATE_NAME.srl \
    -out $OUTPUT_DIRECTORY/$CERTIFICATE_NAME.crt \
    -days 365 \
    -sha256

  echo "[+] Created a new device certificate ($OUTPUT_DIRECTORY/$CERTIFICATE_NAME.key)"
}

# Create the device certificate.
create_device_certificate
