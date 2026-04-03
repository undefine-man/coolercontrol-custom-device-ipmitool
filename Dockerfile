执行环境 Github Actions
基础镜像 coolcontrol/coolcontrold:latest
更新软件仓库
下载curl、ipmitool
复制 仓库install.sh 到容器 /etc/coolcontrol/install.sh
运行 install.sh
卸载 curl
清理apt缓存
删除 install.sh

FROM coolcontrol/coolcontrold:latest
RUN apt-get update && apt-get install -y curl ipmitool
COPY install.sh /etc/coolcontrol/install.sh
RUN chmod +x /etc/coolcontrol/install.sh && /etc/coolcontrol/install.sh
RUN apt-get remove -y curl && apt-get autoremove -y && apt-get clean && rm -rf /var/lib/apt/lists/* /etc/coolcontrol/install.sh
