packer {
  required_plugins {
    amazon = {
      version = ">= 1.0.0"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

source "amazon-ebs" "windows_2025" {
  ami_name      = "rdpdev-win2025-{{timestamp}}"
  instance_type = "t3.large"
  region        = "us-east-1"
  source_ami_filter {
    filters = {
      name                = "Windows_Server-2025-English-Full-Base-*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    most_recent = true
    owners      = ["801119661308"] # Microsoft
  }
  user_data_file = "scripts/setup.ps1"
  communicator   = "ssh"
  ssh_username   = "administrator"
}

build {
  sources = ["source.amazon-ebs.windows_2025"]

  provisioner "powershell" {
    script = "provision.ps1"
  }

  provisioner "ansible" {
    playbook_file = "site.yml"
    user          = "administrator"
    use_proxy     = false
  }
}
