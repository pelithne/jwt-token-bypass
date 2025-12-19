#!/bin/bash
# Fix app registration to add missing API scope

CLIENT_ID="559a672f-ece6-4cb7-989e-f457d6a16c1c"
APP_DISPLAY_NAME="jwttest-dev"

echo "Fixing app registration: $APP_DISPLAY_NAME"
echo "Client ID: $CLIENT_ID"
echo ""

# Get object ID
OBJECT_ID=$(az ad app show --id "$CLIENT_ID" --query id -o tsv)
echo "Object ID: $OBJECT_ID"

# Generate a new UUID for the scope
SCOPE_ID=$(uuidgen)
echo "Scope ID: $SCOPE_ID"

# Set identifier URI first
API_URI="api://${CLIENT_ID}"
echo ""
echo "Setting identifier URI: $API_URI"
az ad app update --id "$CLIENT_ID" --identifier-uris "$API_URI"

# Create scope JSON
cat > /tmp/scope.json <<EOF
{
    "api": {
        "oauth2PermissionScopes": [
            {
                "adminConsentDescription": "Allow the application to access ${APP_DISPLAY_NAME} on behalf of the signed-in user",
                "adminConsentDisplayName": "Access ${APP_DISPLAY_NAME}",
                "id": "$SCOPE_ID",
                "isEnabled": true,
                "type": "User",
                "userConsentDescription": "Allow the application to access ${APP_DISPLAY_NAME} on your behalf",
                "userConsentDisplayName": "Access ${APP_DISPLAY_NAME}",
                "value": "access_as_user"
            }
        ]
    }
}
EOF

echo ""
echo "Adding API scope: access_as_user"
az rest --method PATCH --uri "https://graph.microsoft.com/v1.0/applications/$OBJECT_ID" \
    --headers "Content-Type=application/json" \
    --body @/tmp/scope.json

rm /tmp/scope.json

echo ""
echo "SUCCESS: API scope configured successfully!"
echo ""
echo "Scope to use: api://${CLIENT_ID}/access_as_user"
