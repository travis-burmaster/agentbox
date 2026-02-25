###############################################################################
# AgentBox Marketing — GCP Infrastructure
# Provisions: Cloud Run · Memorystore Redis · Pub/Sub (Kafka bridge) · IAM
###############################################################################

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

variable "project_id"     { type = string }
variable "region"         { default = "us-central1" }
variable "kafka_bootstrap" { type = string }
variable "kafka_api_key"   { type = string; sensitive = true }
variable "kafka_api_secret"{ type = string; sensitive = true }
variable "smtp2go_pass"    { type = string; sensitive = true }
variable "image_tag"       { default = "latest" }

locals {
  service_name = "agentbox-marketing"
  image        = "${var.region}-docker.pkg.dev/${var.project_id}/agentbox/${local.service_name}:${var.image_tag}"
}

# ── Enable APIs ───────────────────────────────────────────────────────────────
resource "google_project_service" "apis" {
  for_each = toset([
    "run.googleapis.com",
    "redis.googleapis.com",
    "aiplatform.googleapis.com",
    "bigquery.googleapis.com",
    "secretmanager.googleapis.com",
    "artifactregistry.googleapis.com",
    "vpcaccess.googleapis.com",
  ])
  service            = each.key
  disable_on_destroy = false
}

# ── VPC for Redis (Memorystore requires VPC) ──────────────────────────────────
resource "google_compute_network" "vpc" {
  name                    = "agentbox-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnet" {
  name          = "agentbox-subnet"
  ip_cidr_range = "10.0.0.0/24"
  region        = var.region
  network       = google_compute_network.vpc.id
}

resource "google_vpc_access_connector" "connector" {
  name          = "agentbox-connector"
  region        = var.region
  ip_cidr_range = "10.8.0.0/28"
  network       = google_compute_network.vpc.name
}

# ── Memorystore Redis ─────────────────────────────────────────────────────────
resource "google_redis_instance" "memory" {
  name           = "agentbox-memory"
  tier           = "STANDARD_HA"    # HA for production; use BASIC for dev
  memory_size_gb = 2
  region         = var.region

  authorized_network = google_compute_network.vpc.id

  redis_version = "REDIS_7_0"
  display_name  = "AgentBox Marketing Memory"

  redis_configs = {
    maxmemory-policy = "noeviction"   # NEVER evict agent memory
  }

  labels = {
    app = "agentbox-marketing"
  }
}

# ── Secret Manager — store credentials ───────────────────────────────────────
resource "google_secret_manager_secret" "kafka_key" {
  secret_id = "agentbox-kafka-api-key"
  replication { auto {} }
}
resource "google_secret_manager_secret_version" "kafka_key" {
  secret      = google_secret_manager_secret.kafka_key.id
  secret_data = var.kafka_api_key
}

resource "google_secret_manager_secret" "kafka_secret" {
  secret_id = "agentbox-kafka-api-secret"
  replication { auto {} }
}
resource "google_secret_manager_secret_version" "kafka_secret" {
  secret      = google_secret_manager_secret.kafka_secret.id
  secret_data = var.kafka_api_secret
}

resource "google_secret_manager_secret" "smtp" {
  secret_id = "agentbox-smtp2go-pass"
  replication { auto {} }
}
resource "google_secret_manager_secret_version" "smtp" {
  secret      = google_secret_manager_secret.smtp.id
  secret_data = var.smtp2go_pass
}

# ── Service Account ───────────────────────────────────────────────────────────
resource "google_service_account" "agent" {
  account_id   = "agentbox-marketing"
  display_name = "AgentBox Marketing Agent"
}

resource "google_project_iam_member" "vertex_user" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.agent.email}"
}

resource "google_project_iam_member" "bigquery_user" {
  project = var.project_id
  role    = "roles/bigquery.dataViewer"
  member  = "serviceAccount:${google_service_account.agent.email}"
}

resource "google_project_iam_member" "secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.agent.email}"
}

# ── Artifact Registry ─────────────────────────────────────────────────────────
resource "google_artifact_registry_repository" "repo" {
  location      = var.region
  repository_id = "agentbox"
  format        = "DOCKER"
}

# ── Cloud Run — AgentBox (scale 0→N) ─────────────────────────────────────────
resource "google_cloud_run_v2_service" "agent" {
  name     = local.service_name
  location = var.region

  template {
    service_account = google_service_account.agent.email

    # Scale 0 to 10 — key for serverless cost model
    scaling {
      min_instance_count = 0
      max_instance_count = 10
    }

    # VPC for Redis access
    vpc_access {
      connector = google_vpc_access_connector.connector.id
      egress    = "PRIVATE_RANGES_ONLY"
    }

    containers {
      image = local.image

      resources {
        limits = {
          cpu    = "2"
          memory = "2Gi"
        }
        cpu_idle          = true   # Throttle CPU when idle (cost saving)
        startup_cpu_boost = true   # Boost CPU on cold start (faster boot)
      }

      # Env: non-secret
      env {
        name  = "GCP_PROJECT"
        value = var.project_id
      }
      env {
        name  = "GCP_LOCATION"
        value = var.region
      }
      env {
        name  = "REDIS_URL"
        value = "redis://${google_redis_instance.memory.host}:${google_redis_instance.memory.port}"
      }
      env {
        name  = "KAFKA_BOOTSTRAP_SERVERS"
        value = var.kafka_bootstrap
      }
      env {
        name  = "MAX_EVENTS_PER_RUN"
        value = "10"
      }

      # Env: from Secret Manager
      env {
        name = "KAFKA_API_KEY"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.kafka_key.secret_id
            version = "latest"
          }
        }
      }
      env {
        name = "KAFKA_API_SECRET"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.kafka_secret.secret_id
            version = "latest"
          }
        }
      }
      env {
        name = "SMTP2GO_PASS"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.smtp.secret_id
            version = "latest"
          }
        }
      }

      # Cloud Run requires an HTTP port even for Kafka consumers
      ports {
        container_port = 8080
      }

      startup_probe {
        http_get { path = "/health" }
        initial_delay_seconds = 5
        timeout_seconds       = 3
        period_seconds        = 5
        failure_threshold     = 3
      }
    }
  }

  depends_on = [
    google_project_service.apis,
    google_redis_instance.memory,
  ]
}

# ── Cloud Scheduler → Pub/Sub → Kafka bridge for scheduled triggers ───────────
resource "google_pubsub_topic" "schedule_trigger" {
  name = "agentbox-schedule-trigger"
}

# Daily marketing report: 6am CT
resource "google_cloud_scheduler_job" "daily_report" {
  name      = "agentbox-daily-report"
  schedule  = "0 11 * * 1-5"  # 6am CT = 11am UTC
  time_zone = "UTC"

  pubsub_target {
    topic_name = google_pubsub_topic.schedule_trigger.id
    data = base64encode(jsonencode({
      task         = "daily_report"
      scheduled_at = "now"
    }))
  }
}

# Weekly competitor scan: Monday 7am CT
resource "google_cloud_scheduler_job" "competitor_scan" {
  name      = "agentbox-competitor-scan"
  schedule  = "0 13 * * 1"  # 7am CT Monday = 13:00 UTC
  time_zone = "UTC"

  pubsub_target {
    topic_name = google_pubsub_topic.schedule_trigger.id
    data = base64encode(jsonencode({
      task         = "competitor_scan"
      scheduled_at = "now"
    }))
  }
}

# ── Outputs ───────────────────────────────────────────────────────────────────
output "cloud_run_url"  { value = google_cloud_run_v2_service.agent.uri }
output "redis_host"     { value = google_redis_instance.memory.host }
output "redis_port"     { value = google_redis_instance.memory.port }
output "artifact_repo"  { value = google_artifact_registry_repository.repo.name }
