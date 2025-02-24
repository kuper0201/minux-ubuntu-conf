#!/bin/bash

apt update

DISKS=$(lsblk -nd --output NAME | awk '{print $1 " " "/dev/"$1}')
TARGET_DISK="/dev/$(dialog --ascii-lines --title "Disk" --menu "Select disk for installation:" 15 50 5 $DISKS 3>&1 1>&2 2>&3)"
clear

if [ -z "$TARGET_DISK" ]; then
    echo "Cancel installation"
    exit 1
fi

TARGET_MOUNT="/mnt"
UBUNTU_VERSION="noble"  # 22.04 LTS
MIRROR="http://mirror.kakao.com/ubuntu"

echo "[1/6] disk partitioning"
# 기존 데이터 삭제 (주의!)
sgdisk --zap-all ${TARGET_DISK}

# EFI 파티션과 루트 파티션 생성
parted -s ${TARGET_DISK} mklabel gpt
parted -s ${TARGET_DISK} mkpart ESP fat32 1MiB 512MiB
parted -s ${TARGET_DISK} set 1 boot on
parted -s ${TARGET_DISK} mkpart primary ext4 512MiB 100%

# 파일시스템 생성
mkfs.vfat -F32 ${TARGET_DISK}1
mkfs.ext4 ${TARGET_DISK}2

# 마운트
mount ${TARGET_DISK}2 ${TARGET_MOUNT}
#mkdir -p ${TARGET_MOUNT}/boot
#mount ${TARGET_DISK}1 ${TARGET_MOUNT}/boot

echo "[2/6] debootstrap"
debootstrap --arch=amd64 ${UBUNTU_VERSION} ${TARGET_MOUNT} ${MIRROR}

echo "[3/6] setting fstab"
cat <<EOF > ${TARGET_MOUNT}/etc/fstab
UUID=$(blkid -s UUID -o value ${TARGET_DISK}2) / ext4 defaults 0 1
UUID=$(blkid -s UUID -o value ${TARGET_DISK}1) /boot vfat defaults 0 1
EOF

echo "[4/6] install systemd-boot"
mount --bind /dev ${TARGET_MOUNT}/dev
mount --bind /proc ${TARGET_MOUNT}/proc
mount --bind /sys ${TARGET_MOUNT}/sys
if [ -d "/sys/firmware/efi" ]; then
    mkdir -p ${TARGET_MOUNT}/boot
    mount "$TARGET_DISK"1 "${TARGET_MOUNT}/boot"
fi

# 테마 설정
cp -r dot_config ${TARGET_MOUNT}/etc/skel/.config
cp -r dot_themes ${TARGET_MOUNT}/etc/skel/.themes
cp -r wallpapers ${TARGET_MOUNT}/usr/share/wallpapers

chroot ${TARGET_MOUNT} bash -c "
cat <<EOF > /etc/apt/sources.list
deb $MIRROR $UBUNTU_VERSION main restricted universe multiverse
deb-src $MIRROR $UBUNTU_VERSION main restricted universe multiverse

deb $MIRROR $UBUNTU_VERSION-security main restricted universe multiverse
deb-src $MIRROR $UBUNTU_VERSION-security main restricted universe multiverse

deb $MIRROR $UBUNTU_VERSION-updates main restricted universe multiverse
deb-src $MIRROR $UBUNTU_VERSION-updates main restricted universe multiverse
EOF

apt update
apt install -y libterm-readline-gnu-perl systemd-sysv os-prober shim-signed grub-common grub-gfxpayload-lists grub-pc grub-pc-bin grub2-common grub-efi-amd64-signed
# if [ -d "/sys/firmware/efi" ]; then
#     grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ubuntu --recheck
# else
#     grub-install --target=i386-pc --recheck "$TARGET_DISK"
# fi

apt install -y --no-install-recommends linux-generic
update-grub

dbus-uuidgen > /etc/machine-id
ln -fs /etc/machine-id /var/lib/dbus/machine-id

# 패키지 설치
apt install -y --no-install-recommends --no-install-suggests xorg openbox lightdm lightdm-gtk-greeter xfce4-panel git nano alacritty
apt install -y adwaita-qt adwaita-qt6 gnome-themes-extra

# 환경 변수 설정
sed -i '$ s/$/\nQT_QPA_PLATFORMTHEME=qt5ct\nQT_STYLE_OVERRIDE=Adwaita-Dark\nGTK_THEME=Adwaita-dark/' /etc/environment

# lightdm 배경화면 설정
sed -i 's|^#background.*|background=/usr/share/wallpapers/wall_1.png|' /etc/lightdm/lightdm-gtk-greeter.conf

# 네트워크 설정
cat <<EOF > /etc/netplan/01-adapter.yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    eth:
      match:
        name: '*'
      dhcp4: true
EOF

netplan apply
"

while true; do
    ROOTPASSWORD=$(dialog --ascii-lines --title "ROOT Password" --insecure --passwordbox "ROOT Password:" 10 40 3>&1 1>&2 2>&3)
    if [ -z "$ROOTPASSWORD" ]; then
        dialog --ascii-lines --title "Error" --msgbox "Error: Empty root password. Please try again." 6 40
    else
        break
    fi
done

while true; do
    USERNAME=$(dialog --ascii-lines --title "Add User" --inputbox "Username:" 10 40 3>&1 1>&2 2>&3)
    if [ -z "$USERNAME" ]; then
        dialog --ascii-lines --title "Error" --msgbox "Error: Empty username. Please try again." 6 40
    else
        break
    fi
done

while true; do
    PASSWORD=$(dialog --ascii-lines --title "Password Setting" --insecure --passwordbox "Password:" 10 40 3>&1 1>&2 2>&3)
    if [ -z "$PASSWORD" ]; then
        dialog --ascii-lines --title "Error" --msgbox "Error: Empty password. Please try again." 6 40
    else
        break
    fi
done

dialog --ascii-lines --title "Permission" --yesno "Sudo?" 7 50
SUDO_CHOICE=$?

clear

# 4️⃣ 사용자 계정 생성
chroot ${TARGET_MOUNT} bash -c "
useradd -m -s /bin/bash $USERNAME
echo '$USERNAME:$PASSWORD' | chpasswd
"

if [ "$SUDO_CHOICE" -eq 0 ]; then
    chroot ${TARGET_MOUNT} bash -c "usermod -aG sudo $USERNAME"
fi

echo "[5/6] root password"
chroot ${TARGET_MOUNT} bash -c "
echo 'minux' > /etc/hostname
echo 'root:$ROOTPASSWORD' | chpasswd
"

echo "[6/6] installation end - reboot"
umount -R ${TARGET_MOUNT}
echo "Reboot"
