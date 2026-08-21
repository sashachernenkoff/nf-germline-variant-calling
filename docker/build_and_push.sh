#!/usr/bin/env bash
# Build the pipeline's tool images (AWS CLI baked in) and push them to ECR.
# Images target linux/amd64 for AWS Batch. Run from the repo root:
#     bash docker/build_and_push.sh
set -euo pipefail

AWS_REGION=us-east-1
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

# repo name | Dockerfile | image tag
IMAGES=(
  "nf-germline-gatk|docker/Dockerfile.gatk|4.5.0.0-aws"
  "nf-germline-mosdepth|docker/Dockerfile.mosdepth|0.3.8-aws"
  "nf-germline-bcftools|docker/Dockerfile.bcftools|1.18-aws"
)

aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "$REGISTRY"

for entry in "${IMAGES[@]}"; do
  IFS='|' read -r repo dockerfile tag <<< "$entry"
  uri="${REGISTRY}/${repo}:${tag}"

  aws ecr describe-repositories --repository-names "$repo" --region "$AWS_REGION" >/dev/null 2>&1 \
    || aws ecr create-repository --repository-name "$repo" --region "$AWS_REGION" >/dev/null

  echo ">>> building $uri"
  docker build --platform linux/amd64 -t "$uri" -f "$dockerfile" .
  echo ">>> pushing $uri"
  docker push "$uri"
done

echo "All images pushed to ${REGISTRY}"
