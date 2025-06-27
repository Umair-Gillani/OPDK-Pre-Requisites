#!/usr/bin/env bash
set -Eeuo pipefail

# -------------------------------------------------------------------------
# Helper functions
# -------------------------------------------------------------------------

log() {
  echo -e "\033[1;34m$(date '+%Y-%m-%d %H:%M:%S') : [INFO] $*\033[0m"
}

log1() {
  echo -e "\033[1;34m [INFO] $*\033[0m"
}

cmd() {
  echo -e "\033[1;34m $*\033[0m"
}

error_exit() {
  echo -e "\033[1;31m[ERROR] $*\033[0m" >&2
  exit 1
}

# -------------------------------------------------------------------------
# Root check
# -------------------------------------------------------------------------
if (( EUID != 0 )); then
  error_exit "Please run this script as root (sudo ./install_apigee.sh)"
fi

# -------------------------------------------------------------------------
# Decide PRE‑REBOOT vs POST‑REBOOT
# -------------------------------------------------------------------------
read -p "Is this the PRE‑REBOOT run? [y/N] : " PREBOOT
PREBOOT=${PREBOOT,,}

if [[ "$PREBOOT" =~ ^y(es)?$ ]]; then
  # -----------------------------------------------------------------------
  # PRE‑REBOOT  (only SELinux disable + reboot)
  # -----------------------------------------------------------------------
  log "Disabling SELinux (persistent and runtime)"
  sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config
  setenforce 0 || true
  sestatus
  echo ""
  echo ""
  echo ""

  # Change hostname now (persists across reboot)
  read -p "FQDN / Hostname                 : " VM_HOST
  log "Setting system hostname to $VM_HOST"
  hostnamectl set-hostname "$VM_HOST"
  echo ""
  echo ""
  echo ""
  
  log "Rebooting now.  After reboot, rerun this script and answer 'n'."
  sleep 3
  reboot
fi

# -------------------------------------------------------------------------
# POST‑REBOOT  – collect minimal input up‑front
# -------------------------------------------------------------------------

# Automatically determine hostname & IP address
VM_HOST=$(hostname -f)
VM_IP=$(hostname -I | awk '{print $1}')
  
echo ""
echo ""
echo ""

log "Detected hostname : $VM_HOST"
log "Detected IP       : $VM_IP"

echo ""
echo ""
echo ""

# Prompt only for portal credentials
read -p  "Apigee Edge OPDK Username          : " APIGEE_USER
read -s -p "Apigee Edge OPDK password          : " APIGEE_PASSWORD
echo


echo ""
echo ""
echo ""
# From this point on the script is non‑interactive -------------------------
log "Step 1: Stopping and masking firewalld"
systemctl mask firewalld
systemctl stop firewalld
systemctl --no-pager status firewalld || true
echo ""
echo ""
echo ""

log "Step 2: Updating nss"
yum update -y nss
echo ""
echo ""
echo ""

log "Step 3: Installing EPEL Release latest 8 Version Repo - (If you want to install EPEL release archived 7 version repo for Apigee v:4.19.?? 'run below commands')"
cmd "############ This below is for epel release archived 7 version repo ##############"
cmd "wget https://archives.fedoraproject.org/pub/archive/epel/7/x86_64/Packages/e/epel-release-7-14.noarch.rpm"
cmd "rpm -ivh epel-release-7-14.noarch.rpm"
cmd "yum install epel-release"
############ This below is for epel Release latest 8 version repo ##############
curl -sSL -o /tmp/epel.rpm \
  https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm
rpm -ivh /tmp/epel.rpm
yum install -y /tmp/epel.rpm
rpm -q epel-release
echo ""
echo ""
echo ""


log "Step 4: Installing yum‑utils and Python 2"
yum install -y yum-utils
yum install -y python2
sleep 5
ln -sf /usr/bin/python2 /usr/bin/python 
# ln -s /usr/bin/python2 /usr/bin/python
echo ""
echo ""
echo ""


log "Step 5: Creating apigee user and directories"
groupadd -r apigee || true
id -u apigee &>/dev/null || \
  useradd -r -g apigee -d /opt/apigee -s /sbin/nologin -c "Apigee platform user" apigee
mkdir -p /app/apigee
ln -Ts /app/apigee /opt/apigee
chown -h apigee:apigee /app/apigee /opt/apigee
echo ""
echo ""
echo ""


log "Step 6: Updating /etc/hosts (comment first two lines)"
sed -i '1,2 s/^/#/' /etc/hosts
printf "%s\t%s\n" "$VM_IP" "$VM_HOST" >> /etc/hosts
tail -n 5 /etc/hosts
echo ""
echo ""
echo ""


log "Step 7: Disabling nginx and postgresql DNF modules | setting clean_requirements_on_remove to 'False'"
yum module disable -y nginx
yum module disable -y postgresql
sudo sed -i -E 's/^(clean_requirements_on_remove=).*/\1False/' /etc/yum.conf
echo ""
echo ""
echo ""


log "Step 8: Downloading bootstrap script"
VERSION=bootstrap_4.51.00.sh
BOOT=/tmp/$VERSION
curl -sSL https://software.apigee.com/$VERSION -o "$BOOT"
if [ ! -f "$BOOT" ]; then
    log "Download failed: $BOOT not found"
    exit 1
fi
chmod +x "$BOOT"
echo ""
echo ""
echo ""


log "Step 9: Installing Apigee Edge bootstrap (auto‑select option 1 for Java)"
printf '1\n' | bash "$BOOT" \
  apigeeuser="$APIGEE_USER" \
  apigeepassword="$APIGEE_PASSWORD"
echo ""
echo ""
cmd "##############################################################################"
cmd "          Apigee Edge bootstrap Installation completed !!!"
cmd "##############################################################################" 
echo "" 
echo "" 
log1 " => Now You need to Install (Apigee Mirror Utility) on Management Node for creating a local repo mirror of Apigee Software packages using this below command's."
log1 " This will also create TAR file which you will sent to other nodes for installation of Apigee Edge Version $VERSION"
cmd "/opt/apigee/apigee-service/bin/apigee-service apigee-mirror install"
cmd "/opt/apigee/apigee-service/bin/apigee-service apigee-mirror sync --only-new-rpms"
echo ""
echo ""
echo ""
log1 " => Install (Apigee Edge Version $VERSION) through Mirror (execute this below command on management node only)"
cmd "bash /opt/apigee/data/apigee-mirror/repos/$VERSION apigeeprotocol="file://" apigeerepobasepath=/opt/apigee/data/apigee-mirror/repos"
echo ""
log1 " => Install (Apigee Edge Version $VERSION) through Mirror (extract the TAR file in /tmp and execute below command on all other nodes)"
cmd "bash /tmp/$VERSION apigeeprotocol="file://" apigeerepobasepath=/tmp/repos"
echo ""
cmd "/opt/apigee/apigee-service/bin/apigee-service apigee-setup install"
echo ""
echo ""
echo ""
log1 " => Complete these 2 Step for installing Apigee Nginx from Local Repo on Management Node ONLY"
log1 "1. Add or update the following configurations:" 
cmd "nano /opt/apigee/customer/application/mirror.properties"
echo "conf_apigee_mirror_listen_port=6000 
conf_apigee_mirror_server_name=localhost "
echo ""
log1 "2. Reload and Restart Nginx Configuration"
cmd "/opt/apigee/apigee-service/bin/apigee-service apigee-mirror nginxconfig && /opt/nginx/scripts/apigee-nginx restart"
echo ""
echo ""
echo ""
log1 " => Create Config file on all Nodes" 
log1 " => Create License file on Management Node ONLY"
echo ""
echo ""
echo ""
log1 "Before Insalling all component on any node please run the below command..."
cmd "ln -sf /usr/bin/python2 /usr/bin/python"
echo ""
log1 "Now You are ready to Install Component based on your nodes or requirement Manually..."
echo ""
echo ""
log "For Onboarding Organization - Create (/tmp/org-setup) file and copy content of file in it and after copying RUN below command"
cmd "/opt/apigee/apigee-service/bin/apigee-service apigee-provision install"
cmd "/opt/apigee/apigee-service/bin/apigee-service apigee-provision setup-org -f /tmp/org-setup"
echo ""
echo ""
