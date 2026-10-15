#!/bin/bash
# ============================================================
# 强制停止 win10-game 并把 GPU 还给宿主机
# 用法: bash vm-stop.sh [graceful|force]
#   graceful（默认）：先发 ACPI 关机信号，等 20 秒；不成就强杀
#   force：直接断电
#
# 什么时候用：
#   - Windows 里面关不了机（卡死）时
#   - 从 SSH / 手机终端执行（VM 运行时宿主机没显示输出）
# 停掉后 hook 的 release 会自动把 GPU/NVMe/USB 还回来并重启图形桌面。
# ============================================================
MODE="${1:-graceful}"

st=$(virsh domstate win10-game 2>/dev/null)
if [ "$st" != "running" ]; then
    echo "win10-game 当前状态: ${st:-未知}，无需停止。"
    exit 0
fi

if [ "$MODE" = "graceful" ]; then
    echo "发送 ACPI 关机信号..."
    virsh shutdown win10-game 2>&1
    for i in $(seq 1 20); do
        sleep 1
        if [ "$(virsh domstate win10-game 2>/dev/null)" != "running" ]; then
            echo "已正常关机。"
            exit 0
        fi
    done
    echo "20 秒内没关成，转为强制断电。"
fi

echo "强制断电..."
virsh destroy win10-game 2>&1
sleep 3
echo
echo "--- 设备归还情况 ---"
for d in 0000:01:00.0 0000:01:00.1 0000:02:00.0 0000:00:14.0 0000:00:14.2; do
    echo "  $d -> $(basename $(readlink -f /sys/bus/pci/devices/$d/driver 2>/dev/null) 2>/dev/null || echo 无驱动)"
done
echo
echo "--- 图形桌面 ---"
systemctl is-active gdm 2>&1
echo
echo "--- hook 日志末 20 行 ---"
tail -20 /run/vm-passthrough/hook.log 2>/dev/null || echo "(无 hook 日志)"
