#!/bin/bash

# Vérifier que LocalStack est installé
if ! command -v localstack &> /dev/null; then
    echo "LocalStack n'est pas installé. Installation..."
    pip install localstack awscli-local
fi

# Vérifier que Terraform est installé
if ! command -v terraform &> /dev/null; then
    echo "Terraform n'est pas installé. Veuillez l'installer avant de continuer."
    exit 1
fi

# Démarrer LocalStack s'il n'est pas déjà en cours d'exécution
if ! pgrep -f "localstack" > /dev/null; then
    echo "Démarrage de LocalStack..."
    localstack start -d
    # Attendre que LocalStack soit prêt
    sleep 10
fi


# Vérifier que les services nécessaires sont accessibles
echo "Vérification des services LocalStack..."
awslocal ec2 describe-regions || { echo "Service EC2 non disponible"; exit 1; }
awslocal rds describe-db-instances || { echo "Service RDS non disponible"; exit 1; }
awslocal elbv2 describe-load-balancers || { echo "Service ELB non disponible"; exit 1; }
awslocal iam list-roles || { echo "Service IAM non disponible"; exit 1; }
awslocal cloudfront list-distributions || { echo "Service CloudFront non disponible"; exit 1; }
awslocal s3api list-buckets || { echo "Service S3 non disponible"; exit 1; }

echo "Tous les services sont disponibles. Initialisation de Terraform..."

# Initialiser et appliquer la configuration Terraform
terraform init
terraform apply -auto-approve

# Vérifier les ressources créées
echo "Vérification des ressources créées..."
echo "VPC:"
awslocal ec2 describe-vpcs --filters "Name=tag:Name,Values=wordpress-vpc-dev"
echo "Sous-réseaux:"
awslocal ec2 describe-subnets --filters "Name=vpc-id,Values=$(awslocal ec2 describe-vpcs --filters "Name=tag:Name,Values=wordpress-vpc-dev" --query "Vpcs[0].VpcId" --output text)"
echo "RDS:"
awslocal rds describe-db-instances --db-instance-identifier wordpress-db
echo "Load Balancer:"
awslocal elbv2 describe-load-balancers --names wordpress-alb
echo "Rôle IAM:"
awslocal iam get-role --role-name wordpress-ec2-role
echo "S3 Bucket:"
awslocal s3api list-buckets | grep wordpress-media
echo "CloudFront:"
awslocal cloudfront list-distributions

echo "Test terminé. Vous pouvez maintenant vérifier les ressources créées ci-dessus."