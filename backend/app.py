#!/usr/bin/env python3
"""
Backend Container App that receives and validates JWT tokens from Microsoft Entra ID
"""
import os
import sys
import json
import logging
from datetime import datetime
from flask import Flask, request, jsonify
import jwt
from jwt import PyJWKClient
from functools import wraps

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    stream=sys.stdout
)
logger = logging.getLogger(__name__)

app = Flask(__name__)

# Configuration from environment variables
TENANT_ID = os.environ.get('AZURE_TENANT_ID', '')
CLIENT_ID = os.environ.get('AZURE_CLIENT_ID', '')
# Support both v1.0 and v2.0 token issuers
ISSUER_V1 = f'https://sts.windows.net/{TENANT_ID}/'
ISSUER_V2 = f'https://login.microsoftonline.com/{TENANT_ID}/v2.0'
JWKS_URI = f'https://login.microsoftonline.com/{TENANT_ID}/discovery/v2.0/keys'
# Accept both Client ID and api:// URI as audience
AUDIENCE = f'api://{CLIENT_ID}'


def validate_token(f):
    """Decorator to validate JWT token"""
    @wraps(f)
    def decorated_function(*args, **kwargs):
        auth_header = request.headers.get('Authorization', '')
        
        if not auth_header:
            logger.warning("No Authorization header found")
            return jsonify({'error': 'No authorization header'}), 401
        
        # Extract token
        parts = auth_header.split()
        if len(parts) != 2 or parts[0].lower() != 'bearer':
            logger.warning("Invalid Authorization header format")
            return jsonify({'error': 'Invalid authorization header format'}), 401
        
        token = parts[1]
        
        # Log the raw token (first 50 chars only for security)
        logger.info(f"Received JWT token: {token[:50]}...")
        logger.info(f"Full token length: {len(token)} characters")
        
        try:
            # Get the signing key from Microsoft's JWKS endpoint
            jwks_client = PyJWKClient(JWKS_URI)
            signing_key = jwks_client.get_signing_key_from_jwt(token)
            
            # Decode token without verification first to check issuer
            unverified = jwt.decode(token, options={"verify_signature": False})
            issuer = unverified.get('iss', '')
            
            # Determine which issuer to use for validation
            expected_issuer = ISSUER_V1 if issuer == ISSUER_V1 else ISSUER_V2
            logger.info(f"Token issuer: {issuer}")
            logger.info(f"Expected issuer: {expected_issuer}")
            
            # Decode and validate the token
            decoded_token = jwt.decode(
                token,
                signing_key.key,
                algorithms=['RS256'],
                audience=AUDIENCE,
                issuer=expected_issuer,
                options={
                    'verify_signature': True,
                    'verify_exp': True,
                    'verify_nbf': True,
                    'verify_iat': True,
                    'verify_aud': True,
                    'verify_iss': True
                }
            )
            
            # Log decoded token information
            logger.info("=" * 80)
            logger.info("JWT TOKEN VALIDATION SUCCESS")
            logger.info("=" * 80)
            logger.info(f"Token validated successfully at {datetime.utcnow().isoformat()}Z")
            logger.info(f"\nToken Claims:")
            logger.info(json.dumps(decoded_token, indent=2))
            logger.info(f"\nIssuer: {decoded_token.get('iss')}")
            logger.info(f"Subject: {decoded_token.get('sub')}")
            logger.info(f"Audience: {decoded_token.get('aud')}")
            logger.info(f"Issued At: {datetime.fromtimestamp(decoded_token.get('iat', 0)).isoformat()}Z")
            logger.info(f"Expires At: {datetime.fromtimestamp(decoded_token.get('exp', 0)).isoformat()}Z")
            logger.info(f"User Principal Name: {decoded_token.get('upn', 'N/A')}")
            logger.info(f"Object ID: {decoded_token.get('oid', 'N/A')}")
            logger.info("=" * 80)
            
            # Attach decoded token to request for use in handler
            request.decoded_token = decoded_token
            
        except jwt.ExpiredSignatureError:
            logger.error("Token has expired")
            return jsonify({'error': 'Token has expired'}), 401
        except jwt.InvalidAudienceError:
            logger.error(f"Invalid audience. Expected: {CLIENT_ID}")
            return jsonify({'error': 'Invalid token audience'}), 401
        except jwt.InvalidIssuerError:
            logger.error(f"Invalid issuer. Expected: {ISSUER}")
            return jsonify({'error': 'Invalid token issuer'}), 401
        except jwt.InvalidTokenError as e:
            logger.error(f"Invalid token: {str(e)}")
            return jsonify({'error': f'Invalid token: {str(e)}'}), 401
        except Exception as e:
            logger.error(f"Token validation error: {str(e)}", exc_info=True)
            return jsonify({'error': f'Token validation failed: {str(e)}'}), 401
        
        return f(*args, **kwargs)
    
    return decorated_function


@app.route('/')
def index():
    """Health check endpoint"""
    return jsonify({
        'status': 'healthy',
        'service': 'jwt-backend',
        'timestamp': datetime.utcnow().isoformat() + 'Z',
        'tenant_id': TENANT_ID,
        'client_id': CLIENT_ID
    })


@app.route('/api/protected', methods=['GET', 'POST'])
@validate_token
def protected():
    """Protected endpoint that requires valid JWT token"""
    decoded_token = request.decoded_token
    
    response_data = {
        'message': 'Successfully accessed protected resource',
        'timestamp': datetime.utcnow().isoformat() + 'Z',
        'user': {
            'upn': decoded_token.get('upn', 'N/A'),
            'name': decoded_token.get('name', 'N/A'),
            'oid': decoded_token.get('oid', 'N/A')
        },
        'token_info': {
            'issuer': decoded_token.get('iss'),
            'audience': decoded_token.get('aud'),
            'issued_at': datetime.fromtimestamp(decoded_token.get('iat', 0)).isoformat() + 'Z',
            'expires_at': datetime.fromtimestamp(decoded_token.get('exp', 0)).isoformat() + 'Z'
        }
    }
    
    logger.info(f"Protected endpoint accessed by user: {decoded_token.get('upn', 'N/A')}")
    
    return jsonify(response_data)


@app.route('/api/token-info', methods=['POST'])
@validate_token
def token_info():
    """Endpoint that returns full token information"""
    decoded_token = request.decoded_token
    
    logger.info(f"Token info requested by user: {decoded_token.get('upn', 'N/A')}")
    
    return jsonify({
        'message': 'Token decoded successfully',
        'claims': decoded_token
    })


if __name__ == '__main__':
    # Validate configuration
    if not TENANT_ID or not CLIENT_ID:
        logger.error("Missing required environment variables: AZURE_TENANT_ID and/or AZURE_CLIENT_ID")
        sys.exit(1)
    
    logger.info("Starting JWT Backend Service")
    logger.info(f"Tenant ID: {TENANT_ID}")
    logger.info(f"Client ID: {CLIENT_ID}")
    logger.info(f"Audience: {AUDIENCE}")
    logger.info(f"Issuer V1: {ISSUER_V1}")
    logger.info(f"Issuer V2: {ISSUER_V2}")
    logger.info(f"JWKS URI: {JWKS_URI}")
    
    port = int(os.environ.get('PORT', 8080))
    app.run(host='0.0.0.0', port=port, debug=False)
