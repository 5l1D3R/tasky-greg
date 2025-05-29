locals {
  mongo_uri = "mongodb://greg:greg123@${module.ec2_mongodb.private_ip}:27017/admin"
}

resource "null_resource" "redeploy_trigger" {
  triggers = {
    always_run = timestamp()
  }
}

resource "random_uuid" "redeploy" {}

# --- Réseau VPC, Subnets, IGW, Route Table ---

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "main-vpc-terraform"
  }
}

data "aws_availability_zones" "available" {}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "public-subnet-terraform"
  }
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "private-subnet-terraform"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "main-igw-terraform"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "public-rt-terraform"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "eks_nodes" {
  name        = "eks-nodes-sg-terraform"
  description = "Security group for EKS worker nodes"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow all traffic from within the VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "eks-nodes-sg-terraform"
  }
}

# --- S3 Bucket for MongoDB Backups ---

resource "random_id" "s3_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "mongodb_backups" {
  bucket        = "mongodb-backups-${random_id.s3_suffix.hex}"
  force_destroy = true
  tags = {
    Name = "mongodb-backups"
  }
}

resource "aws_s3_bucket_public_access_block" "public" {
  bucket                  = aws_s3_bucket.mongodb_backups.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "public_read" {
  bucket = aws_s3_bucket.mongodb_backups.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = "*",
        Action = ["s3:GetObject", "s3:ListBucket"],
        Resource = [
          aws_s3_bucket.mongodb_backups.arn,
          "${aws_s3_bucket.mongodb_backups.arn}/*"
        ]
      }
    ]
  })
}

# --- Module MongoDB EC2 ---

module "ec2_mongodb" {
  source        = "./modules/ec2_mongodb"
  ami_id        = var.ami_id
  instance_type = var.instance_type
  subnet_id     = aws_subnet.public.id
  vpc_id        = aws_vpc.main.id
  key_name      = var.key_name
  eks_cidr      = aws_vpc.main.cidr_block
  s3_bucket_name = aws_s3_bucket.mongodb_backups.bucket
}

# --- Module EKS (Cluster & Node Groups) ---

module "eks" {
  source          = "terraform-aws-modules/eks/aws"
  version         = "20.8.5"
  cluster_name    = var.cluster_name
  cluster_version = "1.29"
  vpc_id          = aws_vpc.main.id
  subnet_ids      = [aws_subnet.public.id, aws_subnet.private.id]

  eks_managed_node_groups = {
    default = {
      min_size     = 1
      max_size     = 3
      desired_size = 2
      instance_types = ["t3.medium"]
      subnet_ids     = [aws_subnet.public.id, aws_subnet.private.id]
      additional_security_group_ids = [aws_security_group.eks_nodes.id]
    }
  }
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.cluster.token

  # Ajoute cette ligne :
  depends_on = [module.eks]
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_id
}

# --- Déploiement Kubernetes ---

resource "kubernetes_service_account" "tasky_admin" {
  metadata {
    name      = "tasky-admin"
    namespace = "default"
    labels = {
      ManagedBy = "terraform"
    }
  }
}

resource "kubernetes_cluster_role_binding" "tasky_admin" {
  metadata {
    name = "tasky-admin-binding"
    labels = {
      ManagedBy = "terraform"
    }
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.tasky_admin.metadata[0].name
    namespace = "default"
  }
}

resource "kubernetes_deployment" "tasky" {
  metadata {
    name = "tasky"
    labels = {
      app = "tasky-terraform"
    }
    annotations = {
      "redeploy-hash" = null_resource.redeploy_trigger.triggers.always_run
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "tasky-terraform"
      }
    }

    template {
      metadata {
        labels = {
          app = "tasky-terraform"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.tasky_admin.metadata[0].name

        container {
          name  = "tasky"
          image = var.image_url
          image_pull_policy = "Always"

          port {
            container_port = 8080
          }

          env {
            name  = "MONGODB_URI"
            value = local.mongo_uri
          }

          env {
            name  = "SECRET_KEY"
            value = var.secret_key
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "tasky" {
  metadata {
    name = "tasky-service"
    labels = {
      app = "tasky-terraform"
    }
  }

  spec {
    selector = {
      app = "tasky-terraform"
    }

    port {
      name        = "http"
      port        = 80
      target_port = 8080
    }

    type = "LoadBalancer"
  }
}

# --- Outputs ---

output "ec2_public_ip" {
  value = module.ec2_mongodb.public_ip
}

output "mongodb_private_ip" {
  value = module.ec2_mongodb.private_ip
}

output "tasky_url" {
  value = kubernetes_service.tasky.status[0].load_balancer[0].ingress[0].hostname
}

output "s3_backup_url" {
  value = "https://${aws_s3_bucket.mongodb_backups.bucket}.s3.amazonaws.com/"
}