#!/bin/bash

# -------------------------
# Paramètres modifiables
# -------------------------
VMID=9000
VMNAME="debian12-cloudinit"
STORAGE="local-lvm"                 # Modifier en fonction du stockage disponible (ex : "local", "ssd", etc.)
BRIDGE="vmbr0"
ISO_URL="https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2"
DISK_IMAGE="debian-12-genericcloud-amd64.qcow2"
SSH_KEY_PATH="$HOME/.ssh/id_rsa.pub"  # Facultatif — injecter la clé SSH dans le template (si disponible)

# -------------------------
# Vérification des dépendances
# -------------------------
echo "🔍 Vérification des dépendances..."
REQUIRED_CMDS=("virt-customize" "wget" "qm")
for cmd in "${REQUIRED_CMDS[@]}"; do
  if ! command -v $cmd >/dev/null 2>&1; then
    echo "❌ '$cmd' manquant. Installez-le avec : sudo apt install libguestfs-tools"
    exit 1
  fi
done

# -------------------------
# Téléchargement de l'image
# -------------------------
echo "🔽 Téléchargement de l'image Debian 12 Cloud..."
wget -q -O "$DISK_IMAGE" "$ISO_URL"
if [ $? -ne 0 ]; then
  echo "❌ Échec du téléchargement de l'image."
  exit 1
fi

# -------------------------
# Personnalisation de l'image (Cloud-Init + terminal série)
# -------------------------
echo "🛠️ Personnalisation de l'image..."
virt-customize -a "$DISK_IMAGE" \
  --install qemu-guest-agent \
  --run-command 'sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT=\"console=tty1\"/" /etc/default/grub' \
  --run-command 'update-grub' \
  --root-password password:debian \
  --hostname "$VMNAME"

# Injection de clé SSH si spécifiée
if [ -f "$SSH_KEY_PATH" ]; then
  virt-customize -a "$DISK_IMAGE" --ssh-inject root:file:"$SSH_KEY_PATH"
  echo "🔑 Clé SSH injectée dans l'image."
else
  echo "⚠️ Clé SSH non trouvée. Ignorée."
fi

# -------------------------
# Création de la VM
# -------------------------
echo "⚙️ Création de la VM ID $VMID..."
qm create "$VMID" \
  --name "$VMNAME" \
  --memory 2048 \
  --cores 2 \
  --net0 virtio,bridge="$BRIDGE" \
  --ostype l26

# -------------------------
# Import du disque QCOW2
# -------------------------
echo "📦 Import du disque..."
qm importdisk "$VMID" "$DISK_IMAGE" "$STORAGE"

# -------------------------
# Configuration du disque et du Cloud-Init
# -------------------------
qm set "$VMID" \
  --scsihw virtio-scsi-pci \
  --scsi0 "$STORAGE:vm-$VMID-disk-0" \
  --ide2 "$STORAGE:cloudinit" \
  --boot c \
  --bootdisk scsi0 \
  --serial0 socket \
  --vga serial0 \
  --agent enabled=1

# -------------------------
# Conversion en template
# -------------------------
echo "📸 Conversion en template..."
qm template "$VMID"

# -------------------------
# Nettoyage
# -------------------------
rm -f "$DISK_IMAGE"

echo "✅ Template $VMNAME ($VMID) prêt à être utilisé avec Proxmox ou Terraform 🎉"
