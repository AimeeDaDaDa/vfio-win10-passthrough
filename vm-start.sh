#!/bin/bash
# ============================================================
# 启动 win10-game
# 用法: bash vm-start.sh
#
# 效果：Linux 桌面会立刻消失（黑屏），这是正常的 —— GPU 被交给虚拟机了。
#       稍等几秒，接在 RTX 3050 上的显示器会出现 Windows 开机画面。
# 回到 Linux：在 Windows 里正常「关机」，hook 会自动把 GPU 还给宿主并恢复桌面。
# ============================================================
DIR=/home/yssm/WorkBuddy/2026-10-13-16-44-19/vfio-win10-passthrough

if virsh domstate win10-game 2>/dev/null | grep -q running; then
    echo "win10-game 已经在运行了。"
    exit 0
fi

echo "清掉上一次的失败单元（如果有）..."
sudo systemctl reset-failed win10-vm-start.service 2>/dev/null

echo "提交到独立 systemd 单元启动（桌面被停也不会中断）..."
sudo systemd-run --unit=win10-vm-start --collect --property=Type=oneshot \
    /bin/bash "$DIR/start-detached.sh" 2>&1

echo
echo "已提交。约 15 秒后桌面会黑屏，随后显示器上出现 Windows。"
echo "日志: $DIR/start.log"
echo "hook 日志: /run/vm-passthrough/hook.log"
