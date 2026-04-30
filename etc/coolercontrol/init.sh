#!/bin/bash

# 安装 cron 和 ipmitool
apt update && apt install -y ipmitool

#apt install -y cron

# 设置 crontab（每分钟两次）
#(crontab -l 2>/dev/null; echo "* * * * * /etc/coolercontrol/ipmi_script.sh"; echo "* * * * * sleep 10; /etc/coolercontrol/ipmi_script.sh") | crontab -

# 启动 cron 服务
#service cron start

# /etc/coolercontrol/run.sh
nohup /etc/coolercontrol/ipmi_script.sh -i 2 > /dev/null 2>&1 &
#disown $(nohup /etc/coolercontrol/ipmi_script.sh &> /dev/null & echo $!)

# 调用原始 entrypoint
#exec /entrypoint.sh "$@"
