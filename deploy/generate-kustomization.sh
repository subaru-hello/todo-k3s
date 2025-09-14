#!/usr/bin/env bash
set -euo pipefail

# Load environment variables
if [ -f "deploy/.env" ]; then
    source deploy/.env
else
    echo "Error: deploy/.env not found. Please copy from .env.example"
    exit 1
fi

# Build the full image path
FULL_IMAGE="${DOCKER_REGISTRY}/${DOCKER_USER}/${APP_NAME}"

# Function to update kustomization.yaml with current image settings
update_kustomization() {
    local env=$1
    local kustomization_file="deploy/overlays/${env}/kustomization.yaml"
    
    echo "Updating ${env} environment with image: ${FULL_IMAGE}:${IMAGE_TAG}"
    
    # Create a temporary file with updated image configuration
    cat > "${kustomization_file}.tmp" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../base

# Generate secrets from local files (not in Git)
secretGenerator:
  - name: postgres-secret
    envs:
      - .env.secret

images:
  - name: IMAGE_PLACEHOLDER
    newName: ${FULL_IMAGE}
    newTag: ${IMAGE_TAG}

patchesStrategicMerge:
EOF

    # Add environment-specific patches
    if [ "$env" = "dev" ]; then
        cat >> "${kustomization_file}.tmp" <<EOF
  - ingress-patch.yaml
  - imagepullsecret-patch.yaml
EOF
    elif [ "$env" = "prod" ]; then
        cat >> "${kustomization_file}.tmp" <<EOF
  - deployment-patch.yaml

replicas:
  - name: todo-api
    count: 2
EOF
    fi
    
    # Replace the original file
    mv "${kustomization_file}.tmp" "${kustomization_file}"
}

# Update all environments
for env in dev prod; do
    if [ -d "deploy/overlays/${env}" ]; then
        update_kustomization "$env"
    fi
done

echo "✅ Kustomization files updated with current environment settings"