#!/bin/bash

echo "Starting cleanup process..."

# First, get kubectl configuration
TMPFILE=$(mktemp)
terraform output -raw configure_kubectl > "$TMPFILE"
if [[ ! $(cat $TMPFILE) == *"No outputs found"* ]]; then
  source "$TMPFILE"
  
  echo "Cleaning up Ray resources..."
  kubectl delete ingress ray-dashboard -n ray-system || true
  kubectl delete raycluster ray-cluster -n ray-system || true
  
  echo "Cleaning up monitoring resources..."
  kubectl delete ingress -n kubecost --all || true
fi

# List of Terraform resources/modules to destroy in sequence
targets=(
  "module.data_addons"
  "aws_route53_record.wildcard"
  "module.eks_blueprints_addons"
)

# First phase: Destroy up to eks_blueprints_addons
for target in "${targets[@]}"
do
  echo "Destroying $target..."
  terraform destroy -target="$target" -auto-approve
done

echo "Waiting for initial resource cleanup..."
sleep 30

echo "Ensuring ingress-nginx load balancer is destroyed..."
LB_NAME="k8s-ingressn-ingressn"
while true; do
  LBS=$(aws elbv2 describe-load-balancers --query "LoadBalancers[?contains(LoadBalancerName, '${LB_NAME}')].LoadBalancerArn" --output text)
  if [ -z "$LBS" ]; then
    echo "No matching load balancers found, proceeding with cleanup..."
    break
  fi
  
  echo "Found ingress-nginx load balancer, attempting to delete..."
  for LB in $LBS; do
    aws elbv2 delete-load-balancer --load-balancer-arn "$LB"
  done
  echo "Waiting for load balancer deletion..."
  sleep 30
done

# Second phase: Continue with remaining resources
remaining_targets=(
  "aws_acm_certificate_validation.domain"
  "aws_route53_record.acm_validation"
  "aws_acm_certificate.domain"
  "module.eks"
  "module.vpc"
  "aws_secretsmanager_secret_version.grafana"
  "module.ebs_csi_driver_irsa"
)

for target in "${remaining_targets[@]}"
do
  echo "Destroying $target..."
  terraform destroy -target="$target" -auto-approve
done

echo "Cleaning up any remaining load balancers..."
for arn in $(aws resourcegroupstaggingapi get-resources \
  --resource-type-filters elasticloadbalancing:loadbalancer \
  --tag-filters "Key=elbv2.k8s.aws/cluster,Values=smp-genai" \
  --query 'ResourceTagMappingList[].ResourceARN' \
  --output text); do \
    aws elbv2 delete-load-balancer --load-balancer-arn "$arn" || true
done

echo "Cleaning up any remaining target groups..."
for arn in $(aws resourcegroupstaggingapi get-resources \
  --resource-type-filters elasticloadbalancing:targetgroup \
  --tag-filters "Key=elbv2.k8s.aws/cluster,Values=smp-genai" \
  --query 'ResourceTagMappingList[].ResourceARN' \
  --output text); do \
    aws elbv2 delete-target-group --target-group-arn "$arn" || true
done

echo "Cleaning up any remaining security groups..."
for sg in $(aws ec2 describe-security-groups \
  --filters "Name=tag:elbv2.k8s.aws/cluster,Values=smp-genai" \
  --query 'SecurityGroups[].GroupId' --output text); do \
    aws ec2 delete-security-group --group-id "$sg" || true
done

echo "Cleanup complete"
