#!/bin/bash
# ============================================================
# VM 启动执行体（由 vm-start.sh 通过 systemd-run 以 root 身份调用）
#
# 为什么必须是 systemd-run：
#   hook 在 prepare 阶段会停掉图形桌面（单显卡直通必须让出 GPU）。
#   如果 virsh 跑在图形会话的进程树里，桌面一停 virsh 就被杀，VM 起不来。
#   丢进 system.slice 的独立单元后，桌面死不死都与它无关。
# ============================================================
LOG=/home/yssm/WorkBuddy/2026-10-13-16-44-19/vfio-win10-passthrough/start.log
HOOKLOG=/run/vm-passthrough/hook.log
DEVS="0000:01:00.0 0000:01:00.1 0000:02:00.0 0000:00:14.0 0000:00:14.2"

snap() {
    local d
    for d in $DEVS; do
        echo "  $d -> $(basename $(readlink -f /sys/bus/pci/devices/$d/driver 2>/dev/null) 2>/dev/null || echo 无驱动)"
    done
}

# ★ 延迟开工：systemd-run 提交本脚本后立刻返回，而紧接着的 virsh start
#   会在几秒内让宿主机桌面消失（单显卡直通必然如此）。
#   留 25 秒缓冲，让调用方（终端 / WorkBuddy）能干净地拿到返回、打印完提示。
sleep "${VM_START_DELAY:-25}"

{
echo "===== $(date '+%F %T') 启动开始（systemd 单元 win10-vm-start）====="

echo "--- 启动前设备绑定 ---"
snap

echo "--- virsh start win10-game ---"
virsh start win10-game 2>&1
echo "virsh 退出码: $?"

echo "--- 等待域进入 running（最多 60s）---"
for i in $(seq 1 60); do
    st=$(virsh domstate win10-game 2>/dev/null)
    printf '  [%02d] %s\n' "$i" "$st"
    [ "$st" = "running" ] && break
    sleep 1
done

echo "--- 同步已插入的 USB 设备进 VM ---"
/usr/local/bin/vfio-usb-hotplug.sh sync

echo "--- 最终域状态 ---"
virsh list --all 2>&1

echo "--- 域磁盘 ---"
virsh domblklist win10-game 2>&1

echo "--- QEMU 进程 ---"
ps -ef | grep qemu-system-x86_64 | grep -v grep | cut -c1-160 || echo "  (无 QEMU 进程)"

echo "--- 启动后设备绑定 ---"
snap

echo "--- hook 日志（全量）---"
cat "$HOOKLOG" 2>/dev/null || echo "  (无 hook 日志)"

echo "===== $(date '+%F %T') 记录结束 ====="
} > "$LOG" 2>&1

chown yssm:yssm "$LOG" 2>/dev/null
chmod 644 "$LOG" 2>/dev/null
