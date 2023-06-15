locals {
  cloud_init_volume_name = var.cloud_init_volume_name == "" ? "${var.name}-cloud-init.iso" : var.cloud_init_volume_name
  network_interfaces = concat(
    [for libvirt_network in var.libvirt_networks: {
      network_name = libvirt_network.network_name != "" ? libvirt_network.network_name : null
      network_id = libvirt_network.network_id != "" ? libvirt_network.network_id : null
      macvtap = null
      addresses = null
      mac = libvirt_network.mac
      hostname = null
    }],
    [for macvtap_interface in var.macvtap_interfaces: {
      network_name = null
      network_id = null
      macvtap = macvtap_interface.interface
      addresses = null
      mac = macvtap_interface.mac
      hostname = null
    }]
  )
  volumes = var.data_volume_id != "" ? [var.volume_id, var.data_volume_id] : [var.volume_id]
}

module "network_configs" {
  source = "git::https://github.com/Ferlab-Ste-Justine/terraform-cloudinit-templates.git//network?ref=v0.10.0"
  network_interfaces = concat(
    [for idx, libvirt_network in var.libvirt_networks: {
      ip = libvirt_network.ip
      gateway = libvirt_network.gateway
      prefix_length = libvirt_network.prefix_length
      interface = "libvirt${idx}"
      mac = libvirt_network.mac
      dns_servers = libvirt_network.dns_servers
    }],
    [for idx, macvtap_interface in var.macvtap_interfaces: {
      ip = macvtap_interface.ip
      gateway = macvtap_interface.gateway
      prefix_length = macvtap_interface.prefix_length
      interface = "macvtap${idx}"
      mac = macvtap_interface.mac
      dns_servers = macvtap_interface.dns_servers
    }]
  )
}

module "dhcp_configs" {
  source = "git::https://github.com/Ferlab-Ste-Justine/terraform-cloudinit-templates.git//dhcp?ref=v0.10.0"
  dhcp = {
    interfaces = var.dhcp.interfaces
    networks = var.dhcp.networks
    default_lease_time = var.dhcp.default_lease_time
    max_lease_time = var.dhcp.max_lease_time
  }
  pxe = var.pxe
  install_dependencies = var.install_dependencies
}

module "prometheus_node_exporter_configs" {
  source = "git::https://github.com/Ferlab-Ste-Justine/terraform-cloudinit-templates.git//prometheus-node-exporter?ref=v0.10.0"
  install_dependencies = var.install_dependencies
}

module "chrony_configs" {
  source = "git::https://github.com/Ferlab-Ste-Justine/terraform-cloudinit-templates.git//chrony?ref=v0.10.0"
  install_dependencies = var.install_dependencies
  chrony = {
    servers  = var.chrony.servers
    pools    = var.chrony.pools
    makestep = var.chrony.makestep
  }
}

module "etcd_sync_configs" {
  source = "git::https://github.com/Ferlab-Ste-Justine/terraform-cloudinit-templates.git//configurations-auto-updater?ref=v0.10.0"
  install_dependencies = var.install_dependencies
  filesystem = {
    path = replace(join("/", ["/var/www/html", var.etcd_sync.url_path]), "////", "/")
    files_permission = "770"
    directories_permission = "770"
  }
  etcd = {
    key_prefix = var.etcd_sync.etcd.key_prefix
    endpoints = var.etcd_sync.etcd.endpoints
    connection_timeout = "30s"
    request_timeout = "30s"
    retry_interval = "5s"
    retries = 6
    auth = var.etcd_sync.etcd.auth
  }
  naming = {
    binary  = "pxe-conf-updater"
    service = "pxe-conf-updater"
  }
  user = "www-data"
}

module "s3_sync_configs" {
  source = "git::https://github.com/Ferlab-Ste-Justine/terraform-cloudinit-templates.git//s3-syncs?ref=v0.10.0"
  install_dependencies = var.install_dependencies
  object_store = {
    url                    = var.s3_sync.s3.url
    region                 = var.s3_sync.s3.region
    access_key             = var.s3_sync.s3.auth.access_key
    secret_key             = var.s3_sync.s3.auth.secret_key
    server_side_encryption = var.s3_sync.s3.server_side_encryption
    ca_cert                = var.s3_sync.s3.auth.ca_cert
  }
  incoming_sync = {
    sync_once    = false
    calendar     = "*-*-* *:*:00"
    bucket       = var.s3_sync.s3.bucket
    paths        = [{
      fs = replace(join("/", ["/var/www/html", var.s3_sync.url_path]), "////", "/")
      s3 = ""
    }]
    symlinks     = "copy"
  }
}

module "fluentbit_configs" {
  source = "git::https://github.com/Ferlab-Ste-Justine/terraform-cloudinit-templates.git//fluent-bit?ref=v0.10.0"
  install_dependencies = var.install_dependencies
  fluentbit = {
    metrics = var.fluentbit.metrics
    systemd_services = concat(
      [
        {
          tag     = var.fluentbit.dhcp_server_tag
          service = "isc-dhcp-server.service"
        },
        {
          tag     = var.fluentbit.tftp_server_tag
          service = "tftpd-hpa.service"
        },
        {
          tag     = var.fluentbit.http_server_tag
          service = "nginx.service"
        }
      ],
      var.etcd_sync.enabled && var.pxe.enabled ? [{
        tag     = var.fluentbit.etcd_sync_tag
        service = "pxe-conf-updater.service"
      }]: [],
      var.s3_sync.enabled && var.pxe.enabled ? [{
        tag     = var.fluentbit.s3_sync_tag
        service = "s3-incoming-sync.service"
      }]: [],
    )
    forward = var.fluentbit.forward
  }
  etcd    = var.fluentbit.etcd
}

module "data_volume_configs" {
  source = "git::https://github.com/Ferlab-Ste-Justine/terraform-cloudinit-templates.git//data-volumes?ref=v0.10.0"
  volumes = [{
    label         = "dhcp_data"
    device        = "vdb"
    filesystem    = "ext4"
    mount_path    = "/var/lib/dhcp"
    mount_options = "defaults"
  }]
}

locals {
  cloudinit_templates = concat([
      {
        filename     = "base.cfg"
        content_type = "text/cloud-config"
        content = templatefile(
          "${path.module}/files/user_data.yaml.tpl", 
          {
            hostname = var.name
            ssh_admin_public_key = var.ssh_admin_public_key
            ssh_admin_user = var.ssh_admin_user
            admin_user_password = var.admin_user_password
          }
        )
      },
      {
        filename     = "node_exporter.cfg"
        content_type = "text/cloud-config"
        content      = module.prometheus_node_exporter_configs.configuration
      },
      {
        filename     = "dhcp.cfg"
        content_type = "text/cloud-config"
        content      = module.dhcp_configs.configuration
      }
    ],
    var.chrony.enabled ? [{
      filename     = "chrony.cfg"
      content_type = "text/cloud-config"
      content      = module.chrony_configs.configuration
    }] : [],
    var.fluentbit.enabled ? [{
      filename     = "fluent_bit.cfg"
      content_type = "text/cloud-config"
      content      = module.fluentbit_configs.configuration
    }] : [],
    var.etcd_sync.enabled && var.pxe.enabled ? [{
      filename     = "etcd_sync.cfg"
      content_type = "text/cloud-config"
      content      = module.etcd_sync_configs.configuration
    }]: [],
    var.s3_sync.enabled && var.pxe.enabled ? [{
      filename     = "s3_sync.cfg"
      content_type = "text/cloud-config"
      content      = module.s3_sync_configs.configuration
    }]: [],
    var.data_volume_id != "" ? [{
      filename     = "data_volume.cfg"
      content_type = "text/cloud-config"
      content      = module.data_volume_configs.configuration
    }]: []
  )
}

data "template_cloudinit_config" "user_data" {
  gzip = false
  base64_encode = false
  dynamic "part" {
    for_each = local.cloudinit_templates
    content {
      filename     = part.value["filename"]
      content_type = part.value["content_type"]
      content      = part.value["content"]
    }
  }
}

resource "libvirt_cloudinit_disk" "dhcp" {
  name           = local.cloud_init_volume_name
  user_data      = data.template_cloudinit_config.user_data.rendered
  network_config = module.network_configs.configuration
  pool           = var.cloud_init_volume_pool
}

resource "libvirt_domain" "dhcp" {
  name = var.name

  cpu {
    mode = "host-passthrough"
  }

  vcpu = var.vcpus
  memory = var.memory

  dynamic "disk" {
    for_each = local.volumes
    content {
      volume_id = disk.value
    }
  }

  dynamic "network_interface" {
    for_each = local.network_interfaces
    content {
      network_id = network_interface.value["network_id"]
      network_name = network_interface.value["network_name"]
      macvtap = network_interface.value["macvtap"]
      addresses = network_interface.value["addresses"]
      mac = network_interface.value["mac"]
      hostname = network_interface.value["hostname"]
    }
  }

  autostart = true

  cloudinit = libvirt_cloudinit_disk.dhcp.id

  //https://github.com/dmacvicar/terraform-provider-libvirt/blob/main/examples/v0.13/ubuntu/ubuntu-example.tf#L61
  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  console {
    type        = "pty"
    target_type = "virtio"
    target_port = "1"
  }
}