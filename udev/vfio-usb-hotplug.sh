#!/bin/bash
# ============================================================
# USB 热插拔自动跟随：VM 运行时，宿主机上插入的任何 USB 设备
# 自动 attach 进 win10-game，拔出自动 detach。
#
# 由 udev 触发:  vfio-usb-hotplug.sh <sys-devpath> <add|remove>
# 手动同步:      vfio-usb-hotplug.sh sync   （把当前已插的设备全部挂进 VM，
#                                             由 start-detached.sh 在启动后调用）
#
# 铁律来源：本机 USB 控制器 00:14.0 不能整控直通（OVMF 卡 TianoCore），
# 键鼠为静态设备级直通；本脚本只做"运行期动态跟随"。
# ============================================================
DOM="win10-game"
LOG=/var/log/vfio-usb-hotplug.log
log() { echo "$(date '+%F %T') $*" >> "$LOG" 2>/dev/null; }

running() { [ "$(virsh domstate "$DOM" 2>/dev/null)" = "running" ]; }

# 过滤：跳过集线器（bDeviceClass=09，含所有 root hub）
should_skip() {
    local p="$1"
    [ -f "$p/idVendor" ] || return 0
    local cls; cls=$(cat "$p/bDeviceClass" 2>/dev/null)
    [ "$cls" = "09" ] && return 0
    return 1
}

make_xml() {   # $1 = sys 路径  →  stdout
    local v p b d
    v=$(cat "$1/idVendor"); p=$(cat "$1/idProduct")
    b=$(cat "$1/busnum");   d=$(cat "$1/devnum")
    cat <<EOF
<hostdev mode='subsystem' type='usb' managed='yes'>
  <source><address type='usb' bus='$b' device='$d'/></source>
</hostdev>
EOF
}

do_attach() {  # $1 = sys 路径
    local p="$1" v pid
    v=$(cat "$p/idVendor" 2>/dev/null); pid=$(cat "$p/idProduct" 2>/dev/null)
    local xml; xml=$(make_xml "$p") || return
    local tmp=/run/.vfio-usb-$$.xml
    echo "$xml" > "$tmp"
    # 已挂相同 vendor:product（如静态直通的键鼠重插）→ libvirt 会报错，容忍即可
    if virsh attach-device "$DOM" "$tmp" --live >/dev/null 2>&1; then
        log "✓ attached $v:$pid ($p)"
    else
        log "× attach $v:$pid 失败（可能已在 VM 里 / 被占用）"
    fi
    rm -f "$tmp"
}

do_detach() {  # $1 = sys 路径
    local p="$1" v pid
    v=$(cat "$p/idVendor" 2>/dev/null); pid=$(cat "$p/idProduct" 2>/dev/null)
    local tmp=/run/.vfio-usb-$$.xml
    make_xml "$p" > "$tmp" 2>/dev/null
    if virsh detach-device "$DOM" "$tmp" --live >/dev/null 2>&1; then
        log "✓ detached $v:$pid"
    else
        log "× detach $v:$pid 失败（可能不在 VM 里）"
    fi
    rm -f "$tmp"
}

case "$1" in
    sync)
        running || { log "sync: VM 未运行，跳过"; exit 0; }
        log "---- sync 开始 ----"
        for d in /sys/bus/usb/devices/*; do
            should_skip "$d" && continue
            do_attach "$d"
        done
        log "---- sync 结束 ----"
        ;;
    add|remove)
        should_skip "/sys$1" && exit 0
        running || exit 0
        if [ "$2" = "add" ]; then do_attach "/sys$1"; else do_detach "/sys$1"; fi
        ;;
    *) exit 0 ;;
esac
