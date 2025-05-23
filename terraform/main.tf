resource "null_resource" "redeploy_trigger" {
  triggers = {
    always_run = timestamp()
  }
}
resource "random_uuid" "redeploy" {}
resource "kubernetes_deployment" "tasky" {
  metadata {
    name = "tasky"
    labels = {
      app = "tasky"
    }
    annotations = {
        "redeploy-hash" = null_resource.redeploy_trigger.triggers.always_run
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "tasky"
      }
    }

    template {
      metadata {
        labels = {
          app = "tasky"
        }
      }

      spec {
        container {
          name  = "tasky"
          image = var.image_url
          image_pull_policy = "Always"

          port {
            container_port = 8080
          }

          env {
            name  = "MONGODB_URI"
            value = var.mongo_uri
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
      app = "tasky"
    }
  }

  spec {
    selector = {
      app = "tasky"
    }

    port {
      name       = "http"
      port       = 80
      target_port = 8080
    }

    type = "LoadBalancer"
  }
}
