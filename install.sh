#!/bin/bash

# Exit if any command fails
set -e

# Apply VPC and EKS first
echo "Applying VPC and EKS..."
terraform init
terraform apply -target=module.vpc \
               -target=module.eks \
               -auto-approve

# Apply ACM certificate and wait for validation
echo "Applying ACM certificate..."
terraform apply -target=aws_acm_certificate.domain \
               -target=aws_route53_record.acm_validation \
               -target=aws_acm_certificate_validation.domain \
               -auto-approve

# Apply storage class and EBS CSI driver
echo "Applying storage configuration..."
terraform apply -target=kubernetes_annotations.disable_gp2 \
               -target=kubernetes_storage_class.default_gp3 \
               -target=module.ebs_csi_driver_irsa \
               -auto-approve

# Apply EKS blueprints addons
echo "Applying EKS blueprints addons..."
terraform apply -target=module.eks_blueprints_addons \
               -auto-approve

echo "Waiting for AWS Load Balancer Controller and ingress-nginx to be ready..."
sleep 60

# Apply Route53 configuration
echo "Applying Route53 configuration..."
terraform apply -target=aws_route53_record.wildcard \
               -auto-approve

# Apply data addons (includes KubeRay operator, JupyterHub, and Kubecost)
echo "Applying data addons..."
terraform apply -target=module.data_addons \
               -auto-approve

# Apply remaining resources
echo "Applying remaining resources..."
terraform apply -auto-approve
