#!/bin/bash
# 保存为 /custom-entrypoint.sh

set -e

# 1. 初始化 OpenRC（原 entrypoint 的第一步）
mkdir -p /run/openrc
openrc default 2>/dev/null || true

# 2. 在后台启动 coolercontrold
/usr/local/bin/coolercontrold "$@" &
COOLERCONTROL_PID=$!

# 3. 等待 coolercontrold 完全启动
# 可以检查进程或等待特定端口/文件
sleep 5  # 根据实际情况调整

# 4. 你的自定义初始化
apt update && apt install -y ipmitool -y
nohup /etc/coolercontrol/ipmi_script.sh -i 2 > /dev/null 2>&1 &

# 5. 等待 coolercontrold 进程（保持容器运行）
wait $COOLERCONTROL_PID