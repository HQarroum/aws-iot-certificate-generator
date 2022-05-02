#!/bin/bash

set -e
set -o pipefail

# Variables.
DIR="$(cd "$(dirname "$0")" && pwd)"
CACERT_NAME='ca-certificate'
PRIVATE_KEY_VERIFICATION='private-key-registration'
OPENSSL_CONFIG="$DIR/config/openssl-ca.conf"
OUTPUT_DIRECTORY="$DIR/ca-certs"
CA_EXPIRY_IN_DAYS=365
CERTIFICATE_PARAMETER='/iot/ca/certificate'
PRIVATE_KEY_PARAMETER='/iot/ca/private-key'

# The help usage text.
USAGE="Generates a new custom CA compatible with the AWS IoT Just-In-Time-Registration.
Options :
    -o  (Optional) - the path to the OpenSSL config file to use to generate a new Root CA
    -d  (Optional) - the path of the directory in which the CA certificates will be stored
    -c  (Optional) - the name of the AWS Parameter Store for storing the CA certificate
    -p  (Optional) - the name of the AWS Parameter Store for storing the CA private key
    -e  (Optional) - the number of days the CA certificate will be valid for"

# Retrieving arguments from the command-line.
while getopts ":o:d:c:p:e:h" o; do
  case "${o}" in
    o) OPENSSL_CONFIG=${OPTARG} ;;
    d) OUTPUT_DIRECTORY=${OPTARG} ;;
    c) CERTIFICATE_PARAMETER=${OPTARG} ;;
    p) PRIVATE_KEY_PARAMETER=${OPTARG} ;;
    e) CA_EXPIRY_IN_DAYS=${OPTARG} ;;
    h) echo "$USAGE"
       exit 0 ;;
   \?) echo "Invalid option: -$OPTARG" >&2
       exit 1 ;;
    :) echo "Option -$OPTARG requires an argument." >&2
       exit 1 ;;
  esac
done

# Creating the output directory.
mkdir -p "$OUTPUT_DIRECTORY"

# Creates a new X.509 private and public key
# and stores them in the output directory.
function create_ca_certificates() {
  openssl genrsa -out "$OUTPUT_DIRECTORY/$CACERT_NAME.key" 2048 2>/dev/null
  openssl req \
    -config "$OPENSSL_CONFIG" \
    -x509 \
    -new \
    -nodes \
    -key "$OUTPUT_DIRECTORY/$CACERT_NAME.key" \
    -sha256 \
    -days "$CA_EXPIRY_IN_DAYS" \
    -out "$OUTPUT_DIRECTORY/$CACERT_NAME.pem"
  echo "[+] Created new X.509 CA certificate ($CACERT_NAME.pem)"
}

# Generates a registration code from AWS IoT
# and uses it to create a CSR.
function create_csr() {
  # Retrieves an AWS IoT registration code using the AWS CLI.
  local code=$(aws iot get-registration-code --query 'registrationCode' --output text)
  # Generate a new private key.
  openssl genrsa -out "$OUTPUT_DIRECTORY/$PRIVATE_KEY_VERIFICATION.key" 2048 2>/dev/null
  # Generate a new CSR using the private key and the registration code.
  openssl req \
    -new \
    -key "$OUTPUT_DIRECTORY/$PRIVATE_KEY_VERIFICATION.key" \
    -subj "/CN=$code" \
    -out "$OUTPUT_DIRECTORY/$PRIVATE_KEY_VERIFICATION.csr"
  echo "[+] Created a CSR using the registration code ($PRIVATE_KEY_VERIFICATION.csr)"
}

# Registers the generated certificate on AWS IoT.
function register_ca() {
  CERTIFICATE_ID=$(aws iot register-ca-certificate \
    --ca-certificate "file://$OUTPUT_DIRECTORY/$CACERT_NAME.pem" \
    --verification-certificate "file://$OUTPUT_DIRECTORY/$PRIVATE_KEY_VERIFICATION.crt" \
    --set-as-active \
    --allow-auto-registration \
    --query 'certificateId' \
    --output text)
  echo "[+] The CA certificate has been registered with the ID: $CERTIFICATE_ID"
}

# Creates a new certificate using the generated CSR.
function create_csr_challenge() {
  openssl x509 \
    -req \
    -in "$OUTPUT_DIRECTORY/$PRIVATE_KEY_VERIFICATION.csr" \
    -CA "$OUTPUT_DIRECTORY/$CACERT_NAME.pem" \
    -CAkey "$OUTPUT_DIRECTORY/$CACERT_NAME.key" \
    -CAcreateserial \
    -CAserial "$OUTPUT_DIRECTORY/$CACERT_NAME.srl" \
    -out "$OUTPUT_DIRECTORY/$PRIVATE_KEY_VERIFICATION.crt" \
    -days "$CA_EXPIRY_IN_DAYS" \
    -sha256
  echo "[+] Created a new X.509 certificate using the CSR and the CA certificate ($PRIVATE_KEY_VERIFICATION.crt)"
}

# Exports the generated CA certificate and private key
# to the AWS Parameter Store.
function export_ca_certificates() {
  local ca_certificate=$(cat "$OUTPUT_DIRECTORY/$CACERT_NAME.pem")
  local ca_private_key=$(cat "$OUTPUT_DIRECTORY/$CACERT_NAME.key")
  aws ssm put-parameter \
    --name "$CERTIFICATE_PARAMETER/$CERTIFICATE_ID" \
    --description "Value of the AWS IoT CA certificate" \
    --value "$ca_certificate" \
    --type SecureString \
    --overwrite > /dev/null
  aws ssm put-parameter \
    --name "$PRIVATE_KEY_PARAMETER/$CERTIFICATE_ID" \
    --description "Value of the AWS IoT CA private key" \
    --value "$ca_private_key" \
    --type SecureString \
    --overwrite > /dev/null
  echo "[+] Exported the CA certificate and private key to the AWS Parameter Store"
}

# Creates a new X.509 CA certificate.
create_ca_certificates

# Creating a CSR using the AWS IoT registration code.
create_csr

# Creating a new X.509 certificate using the CSR and the CA certificate.
create_csr_challenge

# Registering the CA certificate on AWS IoT.
register_ca

echo "[+] You can see your newly registered CA in your console at: https://console.aws.amazon.com/iotv2/home#/cacertificatehub"

read -p "Do you want to export your CA certificates in the AWS Parameter Store (Y/n) ?" -r REPLY
if [[ $REPLY =~ ^[Yy]$ ]]
then
  export_ca_certificates
fi
