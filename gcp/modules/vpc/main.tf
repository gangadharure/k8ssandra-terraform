# Copyright 2021 Datastax LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Create Compute Network for GKE
resource "google_compute_network" "compute_network" {
  name    = format("%s-network", var.name)
  project = var.project_id
  # Always define custom subnetworks- one subnetwork per region isn't useful for an opinional setup
  auto_create_subnetworks = "false"

  # A global routing mode can have an unexpected impact on load balancers; always use a regional mode
  routing_mode = "REGIONAL"
}


# This Cloud Router is used only for the Cloud NAT.
resource "google_compute_router" "vpc_compute_router" {
  # Only create the Cloud NAT if it is enabled.
  depends_on = [
    google_compute_network.compute_network
  ]
  count   = var.enable_cloud_nat ? 1 : 0
  name    = format("%s-router", var.name)
  project = var.project_id
  region  = var.region
  network = google_compute_network.compute_network.self_link
}

# create a public ip for NAT service
resource "google_compute_address" "compute_address" {
  name    = "${var.name}-nat-ip"
  project = var.project_id
  region  = var.region
}

# create compute router NAT service
resource "google_compute_router_nat" "compute_router_nat" {
  # Only create the Cloud NAT if it is enabled.
  count   = var.enable_cloud_nat ? 1 : 0
  name    = format("%s-nat", var.name)
  project = var.project_id
  // Because router has the count attribute set we have to use [0] here to
  // refer to its attributes.
  router  = google_compute_router.vpc_compute_router[0].name
  region  = google_compute_router.vpc_compute_router[0].region
  nat_ips = [google_compute_address.compute_address.self_link]
  # For this example project just use IPs allocated automatically by GCP.
  nat_ip_allocate_option = "MANUAL_ONLY"
  # Apply NAT to all IP ranges in the subnetwork.
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name = google_compute_subnetwork.private_compute_subnetwork.self_link

    source_ip_ranges_to_nat = ["PRIMARY_IP_RANGE", "LIST_OF_SECONDARY_IP_RANGES"]

    secondary_ip_range_names = [
      google_compute_subnetwork.private_compute_subnetwork.secondary_ip_range.0.range_name
    ]
  }

  log_config {
    enable = var.enable_cloud_nat_logging
    filter = var.cloud_nat_logging_filter
  }
}

// Create a public subnets config
resource "google_compute_subnetwork" "compute_subnetwork" {
  name    = format("%s-subnet", var.name)
  project = var.project_id
  network = google_compute_network.compute_network.self_link
  region  = var.region

  private_ip_google_access = true
  ip_cidr_range            = cidrsubnet(var.cidr_block, var.cidr_subnetwork_width_delta, 0)

  secondary_ip_range {
    range_name = "public-services"
    ip_cidr_range = cidrsubnet(
      var.secondary_cidr_block,
      var.secondary_cidr_subnetwork_width_delta,
      0
    )
  }
}

# Create private subnets
resource "google_compute_subnetwork" "private_compute_subnetwork" {
  name     = format("%s-private-subnet", var.name)
  project  = var.project_id
  network  = google_compute_network.compute_network.self_link
  region   = var.region
  provider = google-beta
  purpose  = "PRIVATE"

  private_ip_google_access = true
  ip_cidr_range = cidrsubnet(
    var.cidr_block,
    var.cidr_subnetwork_width_delta,
    1 * (1 + var.cidr_subnetwork_spacing)
  )

  secondary_ip_range {
    range_name = "private-services"
    ip_cidr_range = cidrsubnet(
      var.secondary_cidr_block,
      var.secondary_cidr_subnetwork_width_delta,
      1 * (1 + var.secondary_cidr_subnetwork_spacing)
    )
  }
}
