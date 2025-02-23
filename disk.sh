#!/bin/bash

# 1️⃣ 디스크 목록 가져오기
DISKS=$(lsblk -nd --output NAME | awk '{print $1 " " "/dev/"$1}')

# 2️⃣ `dialog`로 디스크 선택 메뉴 표시
CHOICE=$(dialog --title "디스크 선택" --menu "사용할 디스크를 선택하세요:" 15 50 5 $DISKS 3>&1 1>&2 2>&3)

# 3️⃣ 선택 결과 처리
clear  # 다이얼로그 창 종료 후 화면 정리

if [ -n "$CHOICE" ]; then
    echo "선택한 디스크: /dev/$CHOICE"
else
    echo "선택을 취소했습니다."
fi
