terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# --- Netzwerk mit IPv6-Support ---

resource "google_compute_network" "vpc" {
  name                    = "${var.vm_name}-vpc"
  auto_create_subnetworks = false
  enable_ula_internal_ipv6 = true
}

resource "google_compute_subnetwork" "subnet" {
  name             = "${var.vm_name}-subnet"
  ip_cidr_range    = "10.0.0.0/24"
  region           = var.region
  network          = google_compute_network.vpc.id
  stack_type       = "IPV4_IPV6"
  ipv6_access_type = "EXTERNAL"
}

resource "google_compute_firewall" "allow_ssh_ipv4" {
  name    = "${var.vm_name}-allow-ssh-ipv4"
  network = google_compute_network.vpc.id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
}

resource "google_compute_firewall" "allow_ssh_ipv6" {
  name    = "${var.vm_name}-allow-ssh-ipv6"
  network = google_compute_network.vpc.id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["::/0"]
}

resource "google_compute_firewall" "allow_http_https_ipv4" {
  name    = "${var.vm_name}-allow-http-https-ipv4"
  network = google_compute_network.vpc.id

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["http-server", "https-server"]
}

resource "google_compute_firewall" "allow_http_https_ipv6" {
  name    = "${var.vm_name}-allow-http-https-ipv6"
  network = google_compute_network.vpc.id

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  source_ranges = ["::/0"]
  target_tags   = ["http-server", "https-server"]
}

resource "google_compute_firewall" "allow_node_exporter_ipv4" {
  name    = "${var.vm_name}-allow-node-exporter-ipv4"
  network = google_compute_network.vpc.id

  allow {
    protocol = "tcp"
    ports    = ["9100"]
  }

  source_ranges = ["0.0.0.0/0"]
}

resource "google_compute_firewall" "allow_node_exporter_ipv6" {
  name    = "${var.vm_name}-allow-node-exporter-ipv6"
  network = google_compute_network.vpc.id

  allow {
    protocol = "tcp"
    ports    = ["9100"]
  }

  source_ranges = ["::/0"]
}

# --- VM ---

resource "google_compute_instance" "vm" {
  name         = var.vm_name
  machine_type = var.machine_type
  zone         = var.zone

  boot_disk {
    auto_delete = true
    device_name = var.vm_name

    initialize_params {
      image = "projects/debian-cloud/global/images/family/debian-12"
      size  = 10
      type  = "pd-balanced"
    }

    mode = "READ_WRITE"
  }

  network_interface {
    subnetwork = google_compute_subnetwork.subnet.id

    access_config {
      network_tier = "PREMIUM"
    }

    ipv6_access_config {
      network_tier = "PREMIUM"
    }

    stack_type = "IPV4_IPV6"
  }

  metadata = {
    ssh-keys        = "${var.ssh_user}:${var.ssh_public_key}"
    enable-osconfig = "TRUE"
  }

  tags = ["http-server", "https-server"]

  labels = {
    goog-ec-src = "vm_add-tf"
  }

  scheduling {
    automatic_restart   = true
    on_host_maintenance = "MIGRATE"
    preemptible         = false
    provisioning_model  = "STANDARD"
  }

  service_account {
    email  = "${var.project_number}-compute@developer.gserviceaccount.com"
    scopes = [
      "https://www.googleapis.com/auth/devstorage.read_only",
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring.write",
      "https://www.googleapis.com/auth/service.management.readonly",
      "https://www.googleapis.com/auth/servicecontrol",
      "https://www.googleapis.com/auth/trace.append",
    ]
  }

  shielded_instance_config {
    enable_integrity_monitoring = true
    enable_secure_boot          = false
    enable_vtpm                 = true
  }

  deletion_protection = false
  can_ip_forward      = false
  enable_display      = false
}

# --- Outputs ---

output "vm_name" {
  description = "Name der erstellten VM"
  value       = google_compute_instance.vm.name
}

output "vm_external_ip" {
  description = "Externe IPv4-Adresse der VM"
  value       = google_compute_instance.vm.network_interface[0].access_config[0].nat_ip
}

output "vm_internal_ip" {
  description = "Interne IP-Adresse der VM"
  value       = google_compute_instance.vm.network_interface[0].network_ip
}

output "vm_external_ipv6" {
  description = "Externe IPv6-Adresse der VM"
  value       = try(google_compute_instance.vm.network_interface[0].ipv6_access_config[0].external_ipv6, "nicht verfuegbar")
}

output "ssh_command_ipv4" {
  description = "SSH-Befehl zum Verbinden (IPv4)"
  value       = "ssh ${var.ssh_user}@${google_compute_instance.vm.network_interface[0].access_config[0].nat_ip}"
}

output "ssh_command_ipv6" {
  description = "SSH-Befehl zum Verbinden (IPv6)"
  value       = try("ssh ${var.ssh_user}@${google_compute_instance.vm.network_interface[0].ipv6_access_config[0].external_ipv6}", "nicht verfuegbar - VM hat kein IPv6")
}
