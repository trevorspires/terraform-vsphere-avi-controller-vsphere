locals {
  # Controller Settings used as Ansible Variables
  cloud_settings = {
    vsphere_user                    = var.vsphere_user
    vsphere_server                  = var.vsphere_server
    vm_datacenter                   = var.vsphere_datacenter
    se_mgmt_portgroup               = var.se_mgmt_portgroup
    configure_se_mgmt_network       = var.configure_se_mgmt_network
    se_mgmt_network                 = var.configure_se_mgmt_network ? var.se_mgmt_network : null
    avi_version                     = var.avi_version
    dns_servers                     = var.dns_servers
    dns_search_domain               = var.dns_search_domain
    ntp_servers                     = var.ntp_servers
    email_config                    = var.email_config
    se_name_prefix                  = var.name_prefix
    se_cpu                          = var.se_size[0]
    se_memory                       = var.se_size[1]
    se_disk                         = var.se_size[2]
    controller_ha                   = var.controller_ha
    controller_ip_1                 = var.controller_ip[0]
    controller_name_1               = var.controller_ha ? vsphere_virtual_machine.avi_controller[0].name : null
    controller_ip_2                 = var.controller_ha ? var.controller_ip[1] : null
    controller_name_2               = var.controller_ha ? vsphere_virtual_machine.avi_controller[1].name : null
    controller_ip_3                 = var.controller_ha ? var.controller_ip[2] : null
    controller_name_3               = var.controller_ha ? vsphere_virtual_machine.avi_controller[2].name : null
    configure_ipam_profile          = var.configure_ipam_profile
    ipam_networks                   = var.configure_ipam_profile ? var.ipam_networks : null
    configure_dns_profile           = var.configure_dns_profile
    dns_service_domain              = var.dns_service_domain
    configure_dns_vs                = var.configure_dns_vs
    dns_vs_settings                 = var.dns_vs_settings
    configure_gslb                  = var.configure_gslb
    configure_gslb_additional_sites = var.configure_gslb_additional_sites
    gslb_site_name                  = var.gslb_site_name
    gslb_domains                    = var.gslb_domains
    additional_gslb_sites           = var.additional_gslb_sites
    se_ha_mode                      = var.se_ha_mode
  }
  controller_sizes = {
    small  = [8, 24576]
    medium = [16, 32768]
    large  = [24, 49152]
  }
}
resource "vsphere_virtual_machine" "avi_controller" {
  count            = var.controller_ha ? 3 : 1
  name             = "${var.name_prefix}-avi-controller-${count.index + 1}"
  resource_pool_id = data.vsphere_resource_pool.pool.id
  datastore_id     = data.vsphere_datastore.datastore.id
  num_cpus         = local.controller_sizes[var.controller_size][0]
  memory           = local.controller_sizes[var.controller_size][1]
  folder           = var.vm_folder
  network_interface {
    network_id = data.vsphere_network.avi.id
  }
  lifecycle {
    ignore_changes = [guest_id]
  }
  disk {
    label            = "disk1"
    size             = var.boot_disk_size
    thin_provisioned = true
  }
  clone {
    template_uuid = data.vsphere_content_library_item.item.id
  }
  vapp {
    properties = {
      "mgmt-ip"    = var.controller_ip[count.index]
      "mgmt-mask"  = var.controller_netmask
      "default-gw" = var.controller_gateway
    }
  }
  wait_for_guest_net_timeout  = 0
  wait_for_guest_net_routable = false
  provisioner "local-exec" {
    command = "bash ${path.module}/files/change-controller-password.sh --controller-address \"${var.controller_ip[count.index]}\" --current-password \"${var.controller_default_password}\" --new-password \"${var.controller_password}\""
  }
}
resource "null_resource" "ansible_provisioner" {
  # Changes to any instance of the cluster requires re-provisioning
  triggers = {
    controller_instance_ids = join(",", vsphere_virtual_machine.avi_controller.*.name)
  }
  connection {
    type     = "ssh"
    host     = var.controller_ip[0]
    user     = "admin"
    timeout  = "600s"
    password = var.controller_password
  }
  provisioner "file" {
    content = templatefile("${path.module}/files/avi-vsphere-all-in-one-play.yml.tpl",
    local.cloud_settings)
    destination = "/home/admin/avi-vsphere-all-in-one-play.yml"
  }
  provisioner "file" {
    content = templatefile("${path.module}/files/avi-cleanup.yml.tpl",
    local.cloud_settings)
    destination = "/home/admin/avi-cleanup.yml"
  }
  provisioner "remote-exec" {
    inline = [
      "ansible-playbook avi-vsphere-all-in-one-play.yml -e password=${var.controller_password} -e vsphere_password=${var.vsphere_password} > ansible-playbook.log 2> ansible-error.log",
      "echo Controller Configuration Completed"
    ]
  }
}