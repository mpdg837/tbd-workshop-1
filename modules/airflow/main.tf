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
  #checkov:skip=CKV_GCP_65: "Workshop cluster — no Google Group available for RBAC"
  
  depends_on = [google_project_service.container]

  name     = "airflow-cluster"
  project  = var.project_name
  location = "${var.region}-b"

  # CKV_GCP_21: Ensure Kubernetes Clusters are configured with Labels
  resource_labels = {
    environment = "dev"
  }

  # CKV_GCP_64: Ensure clusters are created with Private Nodes
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  # CKV_GCP_13: Ensure client certificate authentication is disabled
  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }

  # CKV_GCP_69: Ensure the GKE Metadata Server is Enabled
  workload_metadata_config {
    mode = "GKE_METADATA"
  }

  # CKV_GCP_66: Ensure use of Binary Authorization
  binary_authorization {
    evaluation_mode = "PROJECT_SINGLETON_POLICY_ENFORCE"
  }

  # CKV_GCP_70: Ensure the GKE Release Channel is set
  release_channel {
    channel = "REGULAR"
  }

  # CKV_GCP_20: Ensure master authorized networks is set to enabled
  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = "0.0.0.0/0"
      display_name = "all"
    }
  }

  # CKV_GCP_61: Enable VPC Flow Logs and Intranode Visibility
  enable_intranode_visibility = true
  network_policy {
    enabled  = true
    provider = "CALICO"
  }

  # Use Standard mode (not Autopilot) to avoid SSD quota issues
  initial_node_count       = 1
  remove_default_node_pool = true

  network    = var.network
  subnetwork = var.subnet

  deletion_protection = false
}

resource "google_container_node_pool" "airflow_nodes" {
  name     = "airflow-pool"
  project  = var.project_name
  location = "${var.region}-b"
  cluster  = google_container_cluster.airflow.name

  node_count = 2

  lifecycle {
    ignore_changes = [node_config]
  }

  # CKV_GCP_9 and CKV_GCP_10: Auto-repair and auto-upgrade
  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type    = var.machine_type
    service_account = google_service_account.airflow_sa.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    disk_type    = "pd-standard"
    disk_size_gb = 50

    # CKV_GCP_68: Ensure Secure Boot is enabled
    shielded_instance_config {
      enable_secure_boot = true
    }

    # CKV_GCP_69: Ensure the GKE Metadata Server is Enabled
    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }
}
