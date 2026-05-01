CoolerControl ipmi
本仓库用于帮助你在 CoolerControl Docker 环境中通过 ipmi 控制主机（如Dell R730）。

相关资源
CoolerControl 主仓库

自定义设备插件仓库 (cc-plugin-custom-device)

插件开发文档

部署步骤
1. 挂载目录并安装插件
将目录挂载到容器的 /etc/coolercontrol/，然后拉取并安装插件：

拉取自定义设备插件仓库

进入目录并执行安装（该过程会将插件写入挂载目录）
cd cc-plugin-custom-device
./install.sh
安装完成后，挂载的目录中会写入 cc-plugins 插件。

2. 复制脚本到挂载目录
将本仓库中的脚本文件复制到已挂载的 /etc/coolercontrol/ 目录中。

3. 修改 Docker 入口点
修改 CoolerControl Docker 容器的默认入口点为：

text
/etc/coolercontrol/custom-entrypoints
请确保该入口点脚本具有可执行权限。

4. 启动容器
bash
docker run coolercontrol/coolercontrold:latest \
  --privileged \
  -v /path/to/your/mounted/folder:/etc/coolercontrol \
  coolercontrol/coolercontrol
注意事项：

请根据实际情况设置文件及目录权限。

推荐开启 特权容器 (--privileged)，以确保对硬件设备的访问权限。

入口点修改方式取决于你的启动方式（compose、run 或镜像构建）。

完成
以上步骤全部完成后，容器启动即可使用自定义设备插件。
![alt text](image.png)
