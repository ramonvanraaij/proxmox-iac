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

## Prerequisites

Before you begin, ensure you have the following on your control machine:

1.  **Terraform:** [Install Terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)
2.  **Ansible:** [Install Ansible](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html)

### Preparing Proxmox for Automation

To enable secure automation, you must configure a dedicated Terraform user and a `ci` user for SSH bootstrapping. For a full architectural explanation, see the [detailed setup guide](https://ramon.vanraaij.eu/the-reproducible-fortress-proxmox-as-code-with-terraform-ansible/#h-step-2-preparing-proxmox-for-automation).

3.  **Proxmox API Token:** Run the following commands on your Proxmox host as root to set up the necessary role, user, and token:

    ```bash
    # Create the TerraformProv role with the correct permissions
    pveum role add TerraformProv -privs "Pool.Audit Datastore.AllocateSpace Datastore.AllocateTemplate Datastore.Audit Pool.Allocate Sys.Audit Sys.Console Sys.Modify VM.Allocate VM.Audit VM.Clone VM.Config.CDROM VM.Config.Cloudinit VM.Config.CPU VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Migrate VM.PowerMgmt SDN.Use"

    # Create the user and assign the role
    pveum user add terraform-prov@pve
    pveum acl modify / -user terraform-prov@pve -role TerraformProv

    # Create the API token (Take note of the secret value!)
    pveum user token add terraform-prov@pve terraform-token --privsep 0
    ```

4.  **Dedicated CI User:** A `ci` user is required to install `openssh` on new Alpine Linux containers via `pct exec`. Run these commands on your Proxmox host as root:

    ```bash
    # Create the ci user and grant passwordless sudo for 'pct'
    adduser ci
    echo "ci ALL=(ALL) NOPASSWD: /usr/sbin/pct" > /etc/sudoers.d/ci
    
    # Authorize your control node's SSH key (run from your control node)
    ssh-copy-id ci@<proxmox_host_ip>
    ```

    *Note: For enhanced security, consider using a [forced command validation script](https://ramon.vanraaij.eu/the-reproducible-fortress-proxmox-as-code-with-terraform-ansible/#h-create-a-validation-script-for-ci-user-s-ssh-commands) to restrict the `ci` user.*

5.  **Proxmox LXC Template:** An Alpine Linux LXC template must be available in your Proxmox storage (e.g., `local`).

    *Example commands to find and download the template:*
    ```bash
    sudo pveam available | grep alpine
    sudo pveam download local alpine-3.23-default_20260116_amd64.tar.xz
    ```

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
## 🤝 Credits & Maintenance

Developed and maintained by **[Rámon van Raaij](https://ramon.vanraaij.eu)** (2025-2026).

*   **🦋 Bluesky:** [ @ramonvanraaij.nl](https://bsky.app/profile/ramonvanraaij.nl)
*   **🐙 GitHub:** [ @ramonvanraaij](https://github.com/ramonvanraaij)
*   **🌐 Website:** [ramon.vanraaij.eu](https://ramon.vanraaij.eu)

---

## ☕ Buy me a Coffee

If you found this project helpful, informative, or if it saved you some time, consider supporting my work! Your support motivates me to keep building and sharing.

*   **💳 [Bunq.me](https://bunq.me/ramonvanraaij)** (iDeal, Bancontact, Cards)
*   **🅿️ [PayPal](http://paypal.me/ramonvanraaij)**

Thank you for your support! ❤️

---

## Disclaimer

These scripts are provided "as is" without warranty of any kind, express or implied. The author is not liable for any damages arising from the use of these scripts.

## Copyright

Copyright (c) 2025-2026 Rámon van Raaij

This project is licensed under the MIT License - see the [LICENSE.md](LICENSE.md) file for details.
