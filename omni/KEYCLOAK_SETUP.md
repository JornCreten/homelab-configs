# Keycloak SAML Configuration for Omni

This guide shows how to configure Keycloak as a SAML Identity Provider for Omni.

## Prerequisites

- Keycloak server installed and running
- Administrative access to Keycloak
- Omni deployment configured with `AUTH_PROVIDER="saml"`

## Step 1: Create a Realm

1. Log into Keycloak Admin Console
2. Create a new realm (e.g., `omni`) or use an existing one
3. Note the realm name for the SAML URL

## Step 2: Create SAML Client

1. Navigate to **Clients** in your realm
2. Click **Create Client**
3. Configure the client:
   - **Client type**: `SAML`
   - **Client ID**: `omni`
   - Click **Next**

## Step 3: Configure Client Settings

In the client settings, configure:

### General Settings
- **Name**: `Omni`
- **Description**: `Omni Kubernetes Management Platform`

### Access Settings
- **Root URL**: `https://your-omni-domain.com`
- **Valid redirect URIs**: `https://your-omni-domain.com/*`
- **Base URL**: `https://your-omni-domain.com`
- **Master SAML Processing URL**: `https://your-omni-domain.com/saml/acs`

### SAML Settings
- **Name ID format**: `email`
- **Force POST binding**: `ON`
- **Include AuthnStatement**: `ON`
- **Sign documents**: `ON`
- **Sign assertions**: `ON`
- **Signature algorithm**: `RSA_SHA256`
- **SAML signature key name**: `KEY_ID`
- **Canonicalization method**: `EXCLUSIVE`

## Step 4: Configure Attribute Mappings

1. Go to **Client scopes** for your SAML client
2. Click on the `omni-dedicated` scope
3. Go to **Mappers** tab
4. Create the following mappers:

### Email Mapper
- **Name**: `email`
- **Mapper Type**: `User Attribute`
- **User Attribute**: `email`
- **SAML Attribute Name**: `email`
- **SAML Attribute NameFormat**: `Basic`

### First Name Mapper
- **Name**: `firstName`
- **Mapper Type**: `User Attribute`
- **User Attribute**: `firstName`
- **SAML Attribute Name**: `firstName`
- **SAML Attribute NameFormat**: `Basic`

### Last Name Mapper
- **Name**: `lastName`
- **Mapper Type**: `User Attribute`
- **User Attribute**: `lastName`
- **SAML Attribute Name**: `lastName`
- **SAML Attribute NameFormat**: `Basic`

## Step 5: Create Users

1. Navigate to **Users** in your realm
2. Create users that will access Omni
3. Ensure users have valid email addresses
4. Set passwords for the users

## Step 6: Get SAML Endpoint URL

The SAML URL format for Keycloak is:
```
https://your-keycloak-domain.com/realms/{realm-name}/protocol/saml
```

For example:
```
https://keycloak.example.com/realms/omni/protocol/saml
```

## Step 7: Configure Omni

In your `omni-config.env` file:

```bash
export AUTH_PROVIDER="saml"
export SAML_URL="https://keycloak.example.com/realms/omni/protocol/saml"
```

## Step 8: Deploy Omni

Run the deployment script:

```bash
source omni-config.env && ./deploy-omni.sh
```

## Testing the Configuration

1. Access your Omni instance: `https://your-omni-domain.com`
2. You should be redirected to Keycloak for authentication
3. Log in with a user account from your Keycloak realm
4. You should be redirected back to Omni after successful authentication

## Troubleshooting

### SAML Response Issues
- Check Keycloak logs for SAML errors
- Verify the redirect URIs match exactly
- Ensure certificates are properly configured

### Attribute Mapping Issues
- Verify user attributes are populated in Keycloak
- Check that SAML attribute mappers are correctly configured
- Ensure email attribute is present and mapped

### SSL/TLS Issues
- Ensure both Keycloak and Omni are accessible via HTTPS
- Verify SSL certificates are valid
- Check that there are no certificate validation errors

## Additional Security Considerations

1. **Certificate Management**: Regularly rotate SAML signing certificates
2. **Session Management**: Configure appropriate session timeouts
3. **User Provisioning**: Set up automatic user provisioning if needed
4. **Group Mapping**: Configure group/role mappings for authorization
5. **Audit Logging**: Enable audit logging in Keycloak for compliance

## Alternative: Keycloak with Docker Compose

If you want to run Keycloak alongside Omni, you can extend the docker-compose.yaml:

```yaml
services:
  omni:
    # ... existing omni configuration ...

  keycloak:
    image: quay.io/keycloak/keycloak:latest
    environment:
      KEYCLOAK_ADMIN: admin
      KEYCLOAK_ADMIN_PASSWORD: admin
      KC_HOSTNAME: keycloak.your-domain.com
      KC_PROXY: edge
    command: start --optimized
    ports:
      - "8080:8080"
    volumes:
      - keycloak_data:/opt/keycloak/data

volumes:
  keycloak_data:
```

Remember to:
- Set up proper SSL certificates for Keycloak
- Use strong admin passwords
- Configure proper firewall rules
- Set up reverse proxy if needed
