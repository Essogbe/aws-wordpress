# Déploiement WordPress sur AWS avec Terraform

Ce projet fournit une infrastructure complète pour déployer WordPress sur AWS de manière sécurisée, évolutive et optimisée en coûts, en utilisant Terraform pour la gestion de l'infrastructure comme code (IaC).

## Architecture

L'architecture déployée comprend:

- **VPC** dédié avec sous-réseaux publics et privés répartis sur 2 zones de disponibilité
- **EC2** en auto-scaling pour héberger WordPress (dans les sous-réseaux privés)
- **RDS MySQL** en mode multi-AZ pour la haute disponibilité de la base de données
- **Application Load Balancer (ALB)** pour distribuer le trafic et servir de proxy
- **CloudFront** pour la distribution du contenu statique (CDN)
- **S3** pour le stockage des médias WordPress
- **IAM** avec les rôles et politiques appropriés pour la sécurité
- **NAT Gateway** pour permettre l'accès Internet aux instances dans les sous-réseaux privés

![Architecture WordPress AWS](https://i.imgur.com/diagram-placeholder.png)

## Optimisations de coûts

L'architecture implémente plusieurs stratégies d'optimisation des coûts:

1. **Instances t3.micro** - Offre un bon équilibre entre performance et coût avec la capacité de burst CPU
2. **Auto-scaling** - Ajuste automatiquement la capacité selon la charge, avec une seule instance par défaut
3. **CloudFront PriceClass_100** - Utilisation des points de présence les moins coûteux pour la distribution de contenu
4. **Stockage S3** - Décharge le stockage des médias de l'instance EC2, réduisant les besoins en disque
5. **NAT Gateway unique** - Compromis entre coût et haute disponibilité
6. **Cycle de vie S3** - Configuration automatique du cycle de vie des objets S3 pour réduire les coûts de stockage

## Prérequis

- [AWS CLI](https://aws.amazon.com/cli/) configuré avec des identifiants appropriés
- [Terraform](https://www.terraform.io/downloads.html) (v1.0.0+)
- [LocalStack](https://github.com/localstack/localstack) pour les tests locaux (optionnel)

## Structure des fichiers

```
.
├── main.tf                  # Code principal Terraform pour l'infrastructure
├── test-localstack.sh       # Script pour tester avec LocalStack
└── README.md                # Ce fichier
```

## Guide de déploiement

### 1. Préparation

Clonez ce dépôt et naviguez dans le répertoire du projet:

```bash
git clone <repository-url>
cd wordpress-aws-terraform
```

### 2. Test avec LocalStack (optionnel mais recommandé)

Pour tester le déploiement localement avant de l'exécuter sur AWS:

```bash
chmod +x test-localstack.sh
./test-localstack.sh
```

### 3. Personnalisation

Modifiez le fichier `main.tf` pour personnaliser:

- La région AWS (`region`)
- La taille des instances EC2 (`instance_type`)
- Les identifiants de base de données (`db_username`, `db_password`)
- Autres paramètres selon vos besoins

### 4. Déploiement sur AWS

Pour déployer sur AWS:

1. Retirez ou commentez les sections spécifiques à LocalStack dans la configuration du provider AWS:

```hcl
provider "aws" {
  region = "us-east-1"
  # Supprimer les lignes ci-dessous pour un déploiement sur AWS réel
  # skip_credentials_validation = true
  # skip_metadata_api_check     = true
  # skip_requesting_account_id  = true
  
  # Supprimer le bloc endpoints pour un déploiement sur AWS réel
  # endpoints {
  #   ...
  # }
}
```

2. Exécutez les commandes Terraform:

```bash
terraform init
terraform plan
terraform apply
```

3. Confirmez l'application en tapant `yes` lorsque vous êtes invité.

### 5. Accès à WordPress

Une fois le déploiement terminé, récupérez l'URL de l'Application Load Balancer:

```bash
terraform output alb_dns_name
```

Accédez à cette URL dans votre navigateur pour compléter l'installation de WordPress.

## Maintenance et mises à jour

### Mise à jour de l'infrastructure

Pour mettre à jour l'infrastructure après des modifications du code Terraform:

```bash
terraform plan  # Pour voir les changements prévus
terraform apply # Pour appliquer les changements
```

### Sauvegarde et restauration

- Les sauvegardes automatiques RDS sont configurées avec une période de rétention de 7 jours
- Pour une sauvegarde manuelle, créez un snapshot RDS:

```bash
aws rds create-db-snapshot --db-instance-identifier wordpress-db --db-snapshot-identifier wordpress-backup-$(date +%Y%m%d)
```

### Suppression de l'infrastructure

Pour supprimer toutes les ressources créées:

```bash
terraform destroy
```

**Attention**: Cette action est irréversible et supprimera toutes les données.

## Configuration WordPress

Le script d'initialisation configure automatiquement WordPress avec:

- Connexion à la base de données RDS
- Plugin AWS S3 pour le stockage des médias sur S3
- Configuration CloudFront pour accélérer la distribution du contenu statique

Après le déploiement initial, complétez l'installation de WordPress via l'interface web.

## Considérations de sécurité

- Les instances WordPress sont dans des sous-réseaux privés, non accessibles directement depuis Internet
- Le trafic est filtré par des groupes de sécurité spécifiques
- RDS est également dans des sous-réseaux privés
- Les accès IAM suivent le principe du moindre privilège

## Dépannage

### Problèmes courants

1. **Échec de connexion à la base de données**:
   - Vérifiez que les groupes de sécurité permettent le trafic sur le port 3306
   - Confirmez que les identifiants de la base de données sont corrects dans wp-config.php

2. **WordPress ne peut pas télécharger des médias sur S3**:
   - Vérifiez que le rôle IAM est correctement attaché à l'instance EC2
   - Confirmez que la politique S3 permet les actions nécessaires

3. **Échec du déploiement Terraform**:
   - Consultez les journaux d'erreur détaillés dans la sortie de la commande terraform
   - Vérifiez les quotas de service AWS dans votre compte

### Ressources complémentaires 
https://docs.aws.amazon.com/prescriptive-guidance/latest/patterns/test-aws-infra-localstack-terraform.html

https://github.com/aws-samples/localstack-terraform-test
## Contribuer

Les contributions sont les bienvenues! N'hésitez pas à ouvrir une issue ou à soumettre une pull request.

## Licence

Ce projet est distribué sous licence MIT. Voir le fichier LICENSE pour plus de détails.