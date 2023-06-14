variable "name" {
  description = "Name to give to the vm."
  type        = string
  default     = "dhcp"
}

variable "vcpus" {
  description = "Number of vcpus to assign to the vm"
  type        = number
  default     = 2
}

variable "memory" {
  description = "Amount of memory in MiB"
  type        = number
  default     = 8192
}

variable "volume_id" {
  description = "Id of the disk volume to attach to the vm"
  type        = string
}

variable "libvirt_networks" {
  description = "Parameters of libvirt network connections if a libvirt networks are used."
  type = list(object({
    network_name = string
    network_id = string
    prefix_length = string
    ip = string
    mac = string
    gateway = string
    dns_servers = list(string)
  }))
  default = []
}

variable "macvtap_interfaces" {
  description = "List of macvtap interfaces."
  type        = list(object({
    interface     = string
    prefix_length = string
    ip            = string
    mac           = string
    gateway       = string
    dns_servers   = list(string)
  }))
  default = []
}

variable "cloud_init_volume_pool" {
  description = "Name of the volume pool that will contain the cloud init volume"
  type        = string
}

variable "cloud_init_volume_name" {
  description = "Name of the cloud init volume"
  type        = string
  default = ""
}

variable "ssh_admin_user" { 
  description = "Pre-existing ssh admin user of the image"
  type        = string
  default     = "ubuntu"
}

variable "admin_user_password" { 
  description = "Optional password for admin user"
  type        = string
  sensitive   = true
  default     = ""
}

variable "ssh_admin_public_key" {
  description = "Public ssh part of the ssh key the admin will be able to login as"
  type        = string
}

variable "chrony" {
  description = "Chrony configuration for ntp. If enabled, chrony is installed and configured, else the default image ntp settings are kept"
  type        = object({
    enabled = bool,
    //https://chrony.tuxfamily.org/doc/4.2/chrony.conf.html#server
    servers = list(object({
      url = string,
      options = list(string)
    })),
    //https://chrony.tuxfamily.org/doc/4.2/chrony.conf.html#pool
    pools = list(object({
      url = string,
      options = list(string)
    })),
    //https://chrony.tuxfamily.org/doc/4.2/chrony.conf.html#makestep
    makestep = object({
      threshold = number
      limit = number
    })
  })
  default = {
    enabled = false
    servers = []
    pools = []
    makestep = {
      threshold = 0
      limit = 0
    }
  }
}

variable "fluentbit" {
  description = "Fluent-bit configuration"
  sensitive = true
  type = object({
    enabled = bool
    dhcp_server_tag = string
    tftp_server_tag = string
    http_server_tag = string
    etcd_sync_tag   = string
    s3_sync_tag     = string
    metrics = object({
      enabled = bool
      port    = number
    })
    forward = object({
      domain = string
      port = number
      hostname = string
      shared_key = string
      ca_cert = string
    })
    etcd = object({
      enabled = bool
      key_prefix = string
      endpoints = list(string)
      ca_certificate = string
      client = object({
        certificate = string
        key = string
        username = string
        password = string
      })
    })
  })
  default = {
    enabled = false
    dhcp_server_tag = ""
    tftp_server_tag = ""
    http_server_tag = ""
    etcd_sync_tag   = ""
    s3_sync_tag     = ""
    metrics = {
      enabled = false
      port = 0
    }
    forward = {
      domain = ""
      port = 0
      hostname = ""
      shared_key = ""
      ca_cert = ""
    }
    etcd = {
      enabled = false
      key_prefix = ""
      endpoints = []
      ca_certificate = ""
      client = {
        certificate = ""
        key = ""
        username = ""
        password = ""
      }
    }
  }
}

variable "dhcp" {
  description = "Parameters for dhcp server"
  type = object({
    networks = list(object({
      addresses   = string
      gateway     = string
      broadcast   = string
      dns_servers = list(string)
      range_start = string
      range_end   = string
    }))
    interfaces = list(string)
  })
  default = {
    networks = []
    interfaces = []
  }
}

variable "pxe" {
  description = "Parameters for ipxe booting"
  type = object({
    enabled = bool
    self_url = string
    static_boot_script = string
    boot_script_path = string
  })
  default = {
    enabled = false
    self_url = ""
    static_boot_script = ""
    boot_script_path = "ipxe-boot-script"
  }
}

variable "etcd_sync" {
  description = "Parameters for etcd sychronization in the serving path of the file server at a specified url"
  type = object({
    enabled  = bool
    url_path = string
    etcd     = object({
      key_prefix = string
      endpoints  = list(string)
      auth       = object({
        ca_certificate     = string
        client_certificate = string
        client_key         = string
        username           = string
        password           = string
      })
    })
  })
  default = {
    enabled  = false
    url_path = ""
    etcd     = {
      key_prefix = ""
      endpoints  = []
      auth = {
        ca_certificate     = ""
        client_certificate = ""
        client_key         = ""
        username           = ""
        password           = ""
      }
    }
  }
}

variable "s3_sync" {
  description = "Parameters for s3 sychronization in the serving path of the file server at a specified url"
  type = object({
    enabled  = bool
    url_path = string
    s3       = object({
      bucket                 = string
      url                    = string
      region                 = string
      server_side_encryption = string
      auth                   = object({
        ca_cert    = string
        access_key = string
        secret_key = string
      })
    })
  })
  default = {
    enabled  = false
    url_path = ""
    s3       = {
      bucket                 = ""
      url                    = ""
      region                 = ""
      server_side_encryption = ""
      auth                   = {
        ca_cert     = ""
        access_key  = ""
        secret_key  = ""
      }
    }
  }
}

variable "install_dependencies" {
  description = "Whether to install all dependencies in cloud-init"
  type = bool
  default = true
}