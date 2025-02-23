#!/bin/bash

# 설정
TARGET_DISK="/dev/vda"
TARGET_MOUNT="/mnt"
UBUNTU_VERSION="noble"  # 22.04 LTS
MIRROR="http://mirror.kakao.com/ubuntu"

apt install -y gdisk dialog

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
mkdir -p ${TARGET_MOUNT}/boot
mount ${TARGET_DISK}1 ${TARGET_MOUNT}/boot

echo "[2/6] debootstrap"
apt update
apt install -y debootstrap

debootstrap --arch=amd64 ${UBUNTU_VERSION} ${TARGET_MOUNT} ${MIRROR}

echo "[3/6] setting fstab"
cat <<EOF > ${TARGET_MOUNT}/etc/fstab
UUID=$(blkid -s UUID -o value ${TARGET_DISK}2) / ext4 defaults 0 1
UUID=$(blkid -s UUID -o value ${TARGET_DISK}1) /boot/efi vfat defaults 0 1
EOF

echo "[4/6] install systemd-boot"
mount --bind /dev ${TARGET_MOUNT}/dev
mount --bind /proc ${TARGET_MOUNT}/proc
mount --bind /sys ${TARGET_MOUNT}/sys

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
apt install -y libterm-readline-gnu-perl systemd-sysv linux-image-generic linux-headers-generic systemd-boot
update-initramfs -c -k all
bootctl install

# 부팅 옵션 설정
rm -rf /boot/loader
rm -rf /boot/efi/loader

mv /boot/initrd.img* /boot/initrd.img
mv /boot/vmlinuz* /boot/vmlinuz

mkdir -p /boot/loader/entries
cat <<BOOT > /boot/loader/entries/ubuntu.conf
title Ubuntu ${UBUNTU_VERSION}
linux /vmlinuz
initrd /initrd.img
options root=UUID=$(blkid -s UUID -o value ${TARGET_DISK}2) rw quiet splash
BOOT

# 부트로더 기본 설정
cat <<LOADER > /boot/loader/loader.conf
default ubuntu.conf
timeout 3
LOADER

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

echo "[5/6] root password"
chroot ${TARGET_MOUNT} bash -c "
echo 'minux' > /etc/hostname
echo 'root:root' | chpasswd
"

echo "[6/6] installation end - reboot"
umount -R ${TARGET_MOUNT}
echo "Reboot"
