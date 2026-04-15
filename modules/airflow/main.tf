resource "google_project_service" "container" {
  project            = var.project_name
  service            = "container.googleapis.com"
  disable_on_destroy = false
}

resource "google_service_account" "airflow_sa" {
  project    = var.project_name
  account_id = "${var.project_name}-airflow-sa"
}

resource "google_project_iam_member" "airflow_dataproc_editor" {
  project = var.project_name
  role    = "roles/dataproc.editor"
  member  = "serviceAccount:${google_service_account.airflow_sa.email}"
}

resource "google_project_iam_member" "airflow_sa_user" {
  project = var.project_name
  role    = "roles/iam.serviceAccountUser"
  member  = "serviceAccount:${google_service_account.airflow_sa.email}"
}

resource "google_project_iam_member" "airflow_storage" {
  project = var.project_name
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${google_service_account.airflow_sa.email}"
}

resource "google_container_cluster" "airflow" {
  #checkov:skip=CKV_GCP_91: "Workshop cluster — CSEK not needed"
  #checkov:skip=CKV_GCP_24: "Workshop cluster — PodSecurityPolicy not needed"
  #checkov:skip=CKV_GCP_25: "Workshop cluster — private cluster not required"
  #checkov:skip=CKV_GCP_18: "Workshop cluster — master auth networks not required"
  #checkov:skip=CKV_GCP_12: "Workshop cluster — network policy not required"
  #checkov:skip=CKV_GCP_23: "Workshop cluster — alias IPs not required"
  depends_on = [google_project_service.container]

  name     = "airflow-cluster"
  project  = var.project_name
  location = "${var.region}-b"

  # Use Standard mode (not Autopilot) to avoid SSD quota issues
  initial_node_count       = 1
  remove_default_node_pool = true

  network    = var.network
  subnetwork = var.subnet

  deletion_protection = false

  enable_intranode_visibility = true

  node_config {
    workload_metadata_config {
      mode = "GKE_METADATA"
    }
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }

#  workload_identity_config {
#    workload_pool = "${var.project_name}.svc.id.goog"
#  }

  # Skip CKV_GCP_65 (Manage Kubernetes RBAC users with Google Groups for GKE)
  # as it requires a verified Google Workspace domain which we do not have here.
  #checkov:skip=CKV_GCP_65: "Cannot configure RBAC groups without a valid Google Workspace domain."

  binary_authorization {
    evaluation_mode = "PROJECT_SINGLETON_POLICY_ENFORCE"
  }

  release_channel {
    channel = "REGULAR"
  }

  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = "0.0.0.0/0"
      display_name = "all"
    }
  }

  network_policy {
    enabled = true
  }

  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  resource_labels = {
    environment = "workshop"
  }
}

resource "google_container_node_pool" "airflow_nodes" {
  name     = "airflow-pool"
  project  = var.project_name
  location = "${var.region}-b"
  cluster  = google_container_cluster.airflow.name

  node_count = 2

  management {
    auto_upgrade = true
    auto_repair  = true
  }

  lifecycle {
    ignore_changes = [node_config]
  }

  node_config {
    machine_type    = var.machine_type
    service_account = google_service_account.airflow_sa.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    disk_type    = "pd-standard"
    disk_size_gb = 50

#    workload_metadata_config {
#      mode = "GKE_METADATA"
#    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }
}
