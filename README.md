


# 🚀 Kiloview NDI CORE Installer

Welcome to the official script to install **Kiloview NDI CORE** on your cloud or on-premise machine.
NDI CORE is your flexible, powerful and scalable way to **route, manage and distribute NDI video streams** over IP.

---

## ⚙️ Quick Installation

Paste the following command into your terminal (Ubuntu/Debian recommended):

```bash
sudo -i bash -c 'command -v curl >/dev/null 2>&1 || { apt-get update && apt-get install -y curl; }; bash <(curl -fsSL https://raw.githubusercontent.com/RtPalace/NdicoreInstall/master/ndicore_auto_install.sh)'
```

The script will automatically:

✅ Check required dependencies (avahi-daemon, curl, docker)
📦 Download and install the latest stable version of NDI CORE
🐳 Run the container with the correct volume mappings and network settings
🌐 Automatically tell you where to access the Web UI
🔐 Set up with default credentials: admin / admin (you'll be prompted to change password at first login)

---

## 🔗 Access the Web UI

Once installed, simply open your browser and go to:

* Web UI: `http://<YOUR_SERVER_IP>`

Default credentials:

* **Username:** `admin`
* **Password:** `admin`

At first login, you’ll be asked to define a new password.

---

## 🆕 Check for Updates

New versions of NDI CORE firmware can be downloaded from:

👉 [https://www.kiloview.com/en/support/download/](https://www.kiloview.com/en/support/download/)

You can upload the `.bin` file directly via the Web UI to upgrade your deployment.

---

## 💡 About Kiloview

Kiloview is your AVoIP Trailblazer – delivering reliable, scalable and intuitive solutions to help you manage video over IP with ease.

🔍 Learn more at [www.kiloview.com](https://www.kiloview.com/en)

