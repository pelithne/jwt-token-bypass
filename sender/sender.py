#!/usr/bin/env python3
"""
Local sender application that acquires JWT token from Microsoft Entra ID
and sends requests to Application Gateway endpoint
"""
import os
import sys
import json
import argparse
from msal import PublicClientApplication
import requests
from datetime import datetime


class TokenSender:
    def __init__(self, tenant_id, client_id, api_scope):
        self.tenant_id = tenant_id
        self.client_id = client_id
        self.api_scope = api_scope
        self.authority = f"https://login.microsoftonline.com/{tenant_id}"
        
        # Create MSAL Public Client Application
        self.app = PublicClientApplication(
            client_id=client_id,
            authority=self.authority
        )
    
    def acquire_token_interactive(self):
        """Acquire token using interactive browser flow"""
        print(f"\n Acquiring token from Microsoft Entra ID...")
        print(f"Tenant ID: {self.tenant_id}")
        print(f"Client ID: {self.client_id}")
        print(f"Scopes: {self.api_scope}")
        print("\nOpening browser for authentication...")
        
        scopes = [self.api_scope]
        
        # First, check if we have a cached token
        accounts = self.app.get_accounts()
        if accounts:
            print(f"\n Found {len(accounts)} cached account(s)")
            result = self.app.acquire_token_silent(scopes, account=accounts[0])
            if result and 'access_token' in result:
                print(" Using cached token")
                return result['access_token']
        
        # If no cached token, acquire interactively
        result = self.app.acquire_token_interactive(scopes=scopes)
        
        if 'access_token' in result:
            print(" Token acquired successfully!")
            return result['access_token']
        else:
            error = result.get('error', 'Unknown error')
            error_desc = result.get('error_description', 'No description')
            print(f" Error acquiring token: {error}")
            print(f"   Description: {error_desc}")
            raise Exception(f"Failed to acquire token: {error}")
    
    def decode_token_info(self, token):
        """Decode token for display (without validation)"""
        try:
            import jwt
            # Decode without verification just to see the claims
            decoded = jwt.decode(token, options={"verify_signature": False})
            return decoded
        except Exception as e:
            return {"error": f"Could not decode token: {str(e)}"}
    
    def send_request(self, endpoint_url, token, method='GET'):
        """Send request to the backend API through Application Gateway"""
        print(f"\n Sending {method} request to: {endpoint_url}")
        print(f"Token (first 50 chars): {token[:50]}...")
        print(f"Token length: {len(token)} characters")
        
        # Display some token info
        token_info = self.decode_token_info(token)
        print(f"\n Token Claims Preview:")
        print(f"   Issuer: {token_info.get('iss', 'N/A')}")
        print(f"   Audience: {token_info.get('aud', 'N/A')}")
        print(f"   Subject: {token_info.get('sub', 'N/A')}")
        print(f"   User: {token_info.get('upn', token_info.get('preferred_username', 'N/A'))}")
        
        headers = {
            'Authorization': f'Bearer {token}',
            'Content-Type': 'application/json'
        }
        
        try:
            if method.upper() == 'GET':
                response = requests.get(endpoint_url, headers=headers, timeout=30)
            elif method.upper() == 'POST':
                response = requests.post(endpoint_url, headers=headers, timeout=30)
            else:
                raise ValueError(f"Unsupported HTTP method: {method}")
            
            print(f"\n Response Status: {response.status_code}")
            print(f"Response Headers:")
            for key, value in response.headers.items():
                print(f"   {key}: {value}")
            
            print(f"\n Response Body:")
            try:
                response_json = response.json()
                print(json.dumps(response_json, indent=2))
            except:
                print(response.text)
            
            return response
            
        except requests.exceptions.RequestException as e:
            print(f"\n Request failed: {str(e)}")
            raise


def main():
    parser = argparse.ArgumentParser(
        description='Send JWT-authenticated requests to backend API',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Send request to protected endpoint
  python sender.py --endpoint https://your-appgw.example.com/api/protected
  
  # Use environment variables
  export AZURE_TENANT_ID=your-tenant-id
  export AZURE_CLIENT_ID=your-client-id
  export API_SCOPE=api://your-client-id/.default
  export BACKEND_ENDPOINT=https://your-appgw.example.com/api/protected
  python sender.py
        """
    )
    
    parser.add_argument(
        '--tenant-id',
        default=os.environ.get('AZURE_TENANT_ID'),
        help='Azure Tenant ID (or set AZURE_TENANT_ID env var)'
    )
    
    parser.add_argument(
        '--client-id',
        default=os.environ.get('AZURE_CLIENT_ID'),
        help='Azure Client ID for the app registration (or set AZURE_CLIENT_ID env var)'
    )
    
    parser.add_argument(
        '--scope',
        default=os.environ.get('API_SCOPE', 'api://your-client-id/.default'),
        help='API scope to request (or set API_SCOPE env var)'
    )
    
    parser.add_argument(
        '--endpoint',
        default=os.environ.get('BACKEND_ENDPOINT', 'http://localhost:8080/api/protected'),
        help='Backend API endpoint URL (or set BACKEND_ENDPOINT env var)'
    )
    
    parser.add_argument(
        '--method',
        default='GET',
        choices=['GET', 'POST'],
        help='HTTP method to use'
    )
    
    args = parser.parse_args()
    
    # Validate required parameters
    if not args.tenant_id:
        print(" Error: --tenant-id is required (or set AZURE_TENANT_ID environment variable)")
        sys.exit(1)
    
    if not args.client_id:
        print(" Error: --client-id is required (or set AZURE_CLIENT_ID environment variable)")
        sys.exit(1)
    
    print("=" * 80)
    print("JWT Token Sender Application")
    print("=" * 80)
    print(f"Timestamp: {datetime.utcnow().isoformat()}Z")
    
    try:
        # Create sender instance
        sender = TokenSender(args.tenant_id, args.client_id, args.scope)
        
        # Acquire token
        token = sender.acquire_token_interactive()
        
        # Send request
        response = sender.send_request(args.endpoint, token, args.method)
        
        print("\n" + "=" * 80)
        if response.status_code == 200:
            print(" SUCCESS: Request completed successfully!")
        else:
            print(f"WARNING:  WARNING: Request completed with status {response.status_code}")
        print("=" * 80)
        
    except Exception as e:
        print(f"\n Error: {str(e)}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == '__main__':
    main()
