#!/bin/bash

set -e
set -o pipefail

# Variables.
DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIRECTORY="$DIR/ca-certs"
CA_EXPIRY_IN_DAYS=365
CERTIFICATE_PARAMETER="/iot/ca/certificate"
PRIVATE_KEY_PARAMETER="/iot/ca/private-key"
OPENSSL_CONFIG_PATH="$DIR/config/openssl-ca.conf"

# The help usage text.
USAGE="Generates a new custom CA compatible with the AWS IoT Just-In-Time-Registration.
Options :
    -c  (Optional) - the path to the OpenSSL config file to use to generate a new Root CA
    -o  (Optional) - the output path of the directory in which the CA certificates will be stored
    -a  (Optional) - the name of the AWS Parameter Store for storing the CA certificate
    -p  (Optional) - the name of the AWS Parameter Store for storing the CA private key
    -e  (Optional) - the number of days the CA certificate will be valid for"

# Exports the generated certificate output paths.
# This function is called at the beginning
# and called if `$OUTPUT_DIRECTORY` is updated.
function export_file_paths() {
  CA_CERTIFICATE_PATH="$OUTPUT_DIRECTORY/ca-certificate.pem"
  CA_CERTIFICATE_SERIAL_PATH="$OUTPUT_DIRECTORY/ca-certificate.srl"
  CA_PRIVATE_KEY_PATH="$OUTPUT_DIRECTORY/ca-certificate.key"
  CHALLENGE_CERTIFICATE_PATH="$OUTPUT_DIRECTORY/challenge.crt"
  CHALLENGE_KEY_PATH="$OUTPUT_DIRECTORY/challenge.key"
  CHALLENGE_CSR_PATH="$OUTPUT_DIRECTORY/challenge.csr"
}

# Initializing the output file paths.
export_file_paths

# Retrieving arguments from the command-line.
while getopts ":c:o:a:p:e:h" o; do
  case "${o}" in
    c) OPENSSL_CONFIG_PATH=${OPTARG} ;;
    o) OUTPUT_DIRECTORY=${OPTARG} && export_file_paths ;;
    a) CERTIFICATE_PARAMETER=${OPTARG} ;;
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
  openssl genrsa -out "$CA_PRIVATE_KEY_PATH" 2048 2>/dev/null
  openssl req \
    -config "$OPENSSL_CONFIG_PATH" \
    -x509 \
    -new \
    -nodes \
    -key "$CA_PRIVATE_KEY_PATH" \
    -sha256 \
    -days "$CA_EXPIRY_IN_DAYS" \
    -out "$CA_CERTIFICATE_PATH"
  echo "[+] Created new X.509 CA certificate ($CA_CERTIFICATE_PATH)"
}

# Generates a registration code from AWS IoT
# and uses it to create a CSR.
function create_csr() {
  # Retrieves an AWS IoT registration code using the AWS CLI.
  local code=$(aws iot get-registration-code --query 'registrationCode' --output text)
  # Generate a new private key.
  openssl genrsa -out "$CHALLENGE_KEY_PATH" 2048 2>/dev/null
  # Generate a new CSR using the private key and the registration code.
  openssl req \
    -new \
    -key "$CHALLENGE_KEY_PATH" \
    -subj "/CN=$code" \
    -out "$CHALLENGE_CSR_PATH"
  echo "[+] Created a CSR using the registration code"
}

# Creates a new certificate using the generated CSR.
function create_csr_challenge() {
  openssl x509 \
    -req \
    -in "$CHALLENGE_CSR_PATH" \
    -CA "$CA_CERTIFICATE_PATH" \
    -CAkey "$CA_PRIVATE_KEY_PATH" \
    -CAcreateserial \
    -CAserial "$CA_CERTIFICATE_SERIAL_PATH" \
    -out "$CHALLENGE_CERTIFICATE_PATH" \
    -days "$CA_EXPIRY_IN_DAYS" \
    -sha256
  echo "[+] Created a new X.509 certificate using the CSR and the CA certificate ($PRIVATE_KEY_VERIFICATION.crt)"
}

# Registers the generated certificate on AWS IoT.
function register_ca() {
  CERTIFICATE_ID=$(aws iot register-ca-certificate \
    --ca-certificate "file://$CA_CERTIFICATE_PATH" \
    --verification-certificate "file://$CHALLENGE_CERTIFICATE_PATH" \
    --set-as-active \
    --allow-auto-registration \
    --query 'certificateId' \
    --output text)
  echo "[+] The CA certificate has been registered with the ID: $CERTIFICATE_ID"
}

# Exports the generated CA certificate and private key
# to the AWS Parameter Store.
function export_ca_certificates() {
  local ca_certificate=$(cat "$CA_CERTIFICATE_PATH")
  local ca_private_key=$(cat "$CA_PRIVATE_KEY_PATH")

  # Exporting the CA certificate content to AWS SSM.
  aws ssm put-parameter \
    --name "$CERTIFICATE_PARAMETER/$CERTIFICATE_ID" \
    --description "Value of the AWS IoT CA certificate" \
    --value "$ca_certificate" \
    --type SecureString \
    --overwrite > /dev/null
  
  # Exporting the CA private key content to AWS SSM.
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
