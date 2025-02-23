#!/bin/bash

# 1️⃣ 사용자명 입력 받기
USERNAME=$(dialog --title "Add User" --inputbox "Username:" 10 40 3>&1 1>&2 2>&3)

# 입력이 비어 있으면 종료
if [ -z "$USERNAME" ]; then
    clear
    echo "cancel"
    exit 1
fi

# 2️⃣ 비밀번호 입력 받기
PASSWORD=$(dialog --title "Password Setting" --insecure --passwordbox "Password:" 10 40 3>&1 1>&2 2>&3)

# 입력이 비어 있으면 종료
if [ -z "$PASSWORD" ]; then
    clear
    echo "cancel"
    exit 1
fi

# 3️⃣ sudo 권한 여부 선택
dialog --title "Permission" --yesno "Sudo?" 7 50
SUDO_CHOICE=$?

clear  # 다이얼로그 창 종료 후 화면 정리

# 4️⃣ 사용자 계정 생성
useradd -m -s /bin/bash "$USERNAME"

# 5️⃣ 비밀번호 설정
echo "$USERNAME:$PASSWORD" | chpasswd

# 6️⃣ Sudo 그룹 추가 (선택한 경우)
if [ "$SUDO_CHOICE" -eq 0 ]; then
    usermod -aG sudo "$USERNAME"
fi

echo "User: '$USERNAME' created"
