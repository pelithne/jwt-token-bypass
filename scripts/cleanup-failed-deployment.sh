#!/bin/bash
# Quick cleanup script to remove failed deployment resources

RESOURCE_GROUP="rg-jwttest-dev-eastus"

echo "Checking if resource group exists..."
if az group exists --name "$RESOURCE_GROUP" | grep -q "true"; then
    echo "Found resource group: $RESOURCE_GROUP"
    echo ""
    echo "⚠️  This will delete ALL resources in the resource group."
    read -p "Continue? (y/n) " -n 1 -r
    echo ""
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Deleting resource group..."
        az group delete --name "$RESOURCE_GROUP" --yes --no-wait
        echo "SUCCESS: Deletion initiated (running in background)"
        echo ""
        echo "Wait a few minutes, then check status with:"
        echo "  az group exists --name $RESOURCE_GROUP"
        echo ""
        echo "Once deleted (returns 'false'), re-run:"
        echo "  ./scripts/deploy.sh"
    else
        echo "Cancelled."
    fi
else
    echo "SUCCESS: Resource group does not exist - ready for fresh deployment"
    echo "Run: ./scripts/deploy.sh"
fi
