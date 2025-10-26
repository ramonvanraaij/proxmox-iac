# The Reproducible Fortress: Proxmox as Code with Terraform & Ansible

This repository contains the complete Terraform and Ansible code to automatically provision and configure a hardened, production-ready LEMP (Linux, Nginx, MariaDB, PHP) server as an LXC container on a Proxmox host.

This project is the practical implementation of the concepts discussed in the detailed blog post:
**[The Reproducible Fortress: Proxmox as Code with Terraform & Ansible](https://ramon.vanraaij.eu/the-reproducible-fortress-proxmox-as-code-with-terraform-ansible/)**

For a full explanation of the architecture, security decisions, and step-by-step logic, please refer to the blog post.

## 🎯 Project Goal

The goal of this project is to define an entire LEMP server environment as code. This allows you to create, destroy, and recreate a consistent, secure, and fully configured server in minutes, eliminating manual setup and configuration drift.

## ✨ Key Technologies

* **Virtualization:** Proxmox VE
* **Infrastructure as Code:** Terraform
* **Configuration Management:** Ansible
* **Operating System:** Alpine Linux
* **Core Stack:** Nginx, MariaDB, PHP (8.3 & 8.4)
* **Security:** CrowdSec (Intrusion Prevention), `nftables` Firewall, Hardened SSH
* **Monitoring:** Monit

## 🚀 Features

The Ansible playbook configures the Alpine Linux container with the following features:

* **Hardened SSH:** Disables password and root login, allowing key-based access for a non-root sudo user only.
* **Automatic Updates:** Installs and configures `apk-autoupdate` to run daily.
* **LEMP Stack:** Installs Nginx, MariaDB, and two versions of PHP (8.3 and 8.4) with separate FPM pools.
* **WordPress Ready:** Sets up server blocks, users, and databases for two separate WordPress sites.
* **Intrusion Prevention:** Installs and fully configures CrowdSec, including the agent, the `nftables` bouncer, and the Nginx bouncer for application-level protection.
* **System Monitoring:** (Optional) Installs and configures Monit to monitor all critical system services and resources, with email alerting.
* **Backup Scripts:** Deploys a Restic backup script and example environment files for easy integration with B2 or SFTP storage.
* **Proxy Awareness:** (Optional) Can be configured to correctly log visitor IPs when behind Cloudflare or another reverse proxy like Nginx Proxy Manager.

##  Prerequisites

Before you begin, ensure you have the following on your control machine:

1.  **Terraform:** [Install Terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)
2.  **Ansible:** [Install Ansible](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html)
3.  **Proxmox API Token:** You need an API token with sufficient permissions on your Proxmox host.
4.  **Proxmox LXC Template:** An Alpine Linux LXC template must be available in your Proxmox storage. The playbook is tested with Alpine 3.22.

## ⚙ Configuration

1.  **Clone the Repository:**
    ```bash
    git clone https://github.com/ramonvanraaij/proxmox-iac.git
    cd proxmox-iac
    ```

2.  **Configure Proxmox Credentials:**
    1. Copy example_proxmox_api_secrets to ~/.proxmox_api_secrets:<br>
    `cp example_proxmox_api_secrets ~/.proxmox_api_secrets`
    <br>**Do not commit this file to Git.**
    2. Secure the file by setting restrictive permissions:<br>
    `chmod 600 ~/.proxmox_api_secrets`<br>
    This ensures that only your user account can read its sensitive contents.
    4. Follow the instruction in `~/.proxmox_api_secrets`
    5. Source this file in your shell before running Terraform commands:<br>
    `source ~/.proxmox_api_secrets`

3.  **Configure Ansible Variables:**
    Open `lemp/playbook.yml` and edit the `vars` section at the top.
    You can also enable or disable features like CrowdSec, Monit, and Cloudflare integration by changing the feature flags.

## 🚀 Usage

Once configured, deploying the server is a two-step process:

1.  **Initialize Terraform:**
    ```bash
    cd lemp
    terraform init -upgrade
    ```

2.  **Apply the Plan:**
    Terraform will show you what it's going to create. Type `yes` to approve.
    ```bash
    terraform apply
    ```
    Terraform will create the LXC container and then automatically invoke the Ansible playbook to configure it. After a few minutes, the entire process, including a final reboot, will be complete.

##  SSH Access

After the deployment is finished, you must connect using the user in `admin_user` (default is `myuser`) with the SSH key you defined in `admin_user_pub_key`

```bash
ssh myuser@<container_ip>
```
## Disclaimer

These scripts are provided "as is" without warranty of any kind, express or implied. The author is not liable for any damages arising from the use of these scripts.

## Copyright

Copyright (c) 2024-2025 Rámon van Raaij

This project is licensed under the MIT License - see the [LICENSE.md](LICENSE.md) file for details.
