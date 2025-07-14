#!/bin/bash

# Generate self-signed SSL certificates for testing
# This script creates wildcard certificates for the bastion deployment

DOMAIN=${1:-omni.example.com}
SSL_DIR="./omni"

echo "Generating self-signed SSL certificates for ${DOMAIN}"

# Create SSL directory if it doesn't exist
mkdir -p "$SSL_DIR"

# Generate private key
openssl genrsa -out "$SSL_DIR/tls.key" 4096

# Generate certificate signing request
openssl req -new -key "$SSL_DIR/tls.key" -out "$SSL_DIR/tls.csr" -subj "/C=US/ST=State/L=City/O=Organization/CN=${DOMAIN}" -config <(
cat <<EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
C = US
ST = State
L = City
O = Organization
CN = ${DOMAIN}

[v3_req]
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${DOMAIN}
DNS.2 = *.${DOMAIN}
EOF
)

# Generate self-signed certificate
openssl x509 -req -in "$SSL_DIR/tls.csr" -signkey "$SSL_DIR/tls.key" -out "$SSL_DIR/tls.crt" -days 365 -extensions v3_req -extfile <(
cat <<EOF
[v3_req]
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${DOMAIN}
DNS.2 = *.${DOMAIN}
EOF
)

# Clean up CSR file
rm "$SSL_DIR/tls.csr"

echo "SSL certificates generated:"
echo "  - Certificate: $SSL_DIR/tls.crt"
echo "  - Private key: $SSL_DIR/tls.key"
echo ""
echo "Note: These are self-signed certificates for testing only."
echo "For production, use Let's Encrypt or a trusted CA."
