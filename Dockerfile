# 执行环境 Github Actions
# 基础镜像 coolercontrol/coolercontrold:latest
# 更新软件仓库
# 下载curl、ipmitool
# 复制 仓库install.sh 到容器 /etc/coolercontrol/install.sh
# 运行 install.sh
# 卸载 curl
# 清理apt缓存
# 删除 install.sh

FROM coolercontrol/coolercontrold:latest
RUN apt-get update && apt-get install -y curl ipmitool
COPY install.sh /etc/coolercontrol/install.sh
RUN chmod +x /etc/coolercontrol/install.sh && /etc/coolercontrol/install.sh
RUN apt-get remove -y curl && apt-get autoremove -y && apt-get clean && rm -rf /var/lib/apt/lists/* /etc/coolercontrol/install.sh
