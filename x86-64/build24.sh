#!/bin/bash
# Log file for debugging
source shell/custom-packages.sh
echo "第三方软件包: $CUSTOM_PACKAGES"
LOGFILE="/tmp/uci-defaults-log.txt"
echo "Starting 99-custom.sh at $(date)" >>$LOGFILE
echo "编译固件大小为: $PROFILE MB"
echo "Include Docker: $INCLUDE_DOCKER"

echo "Create pppoe-settings"
mkdir -p /home/build/immortalwrt/files/etc/config

# 创建pppoe配置文件 yml传入环境变量ENABLE_PPPOE等 写入配置文件 供99-custom.sh读取
cat <<EOF >/home/build/immortalwrt/files/etc/config/pppoe-settings
enable_pppoe=${ENABLE_PPPOE}
pppoe_account=${PPPOE_ACCOUNT}
pppoe_password=${PPPOE_PASSWORD}
EOF

echo "cat pppoe-settings"
cat /home/build/immortalwrt/files/etc/config/pppoe-settings

if [ -z "$CUSTOM_PACKAGES" ]; then
  echo "⚪️ 未选择 任何第三方软件包"
else
  # ============= 同步第三方插件库==============
  # 同步第三方软件仓库run/ipk
  echo "🔄 正在同步第三方软件仓库 Cloning run file repo..."
  git clone --depth=1 https://github.com/wukongdaily/store.git /tmp/store-run-repo

  # 拷贝 run/x86 下所有 run 文件和ipk文件 到 extra-packages 目录
  mkdir -p /home/build/immortalwrt/extra-packages
  cp -r /tmp/store-run-repo/run/x86/* /home/build/immortalwrt/extra-packages/

  echo "✅ Run files copied to extra-packages:"
  ls -lh /home/build/immortalwrt/extra-packages/*.run
  # 解压并拷贝ipk到packages目录
  sh shell/prepare-packages.sh
  ls -lah /home/build/immortalwrt/packages/
fi

# 输出调试信息
echo "$(date '+%Y-%m-%d %H:%M:%S') - 开始构建固件..."

# ============= imm仓库内的插件==============
# 定义所需安装的包列表 下列插件你都可以自行删减
PACKAGES=""
PACKAGES="$PACKAGES curl"
PACKAGES="$PACKAGES luci-i18n-diskman-zh-cn"
PACKAGES="$PACKAGES luci-i18n-firewall-zh-cn"
PACKAGES="$PACKAGES luci-theme-argon"
PACKAGES="$PACKAGES luci-app-argon-config"
PACKAGES="$PACKAGES luci-i18n-argon-config-zh-cn"
#24.10
PACKAGES="$PACKAGES luci-i18n-package-manager-zh-cn"
PACKAGES="$PACKAGES luci-i18n-ttyd-zh-cn"
PACKAGES="$PACKAGES luci-i18n-passwall-zh-cn"
PACKAGES="$PACKAGES luci-app-openclash"
PACKAGES="$PACKAGES luci-i18n-homeproxy-zh-cn"
PACKAGES="$PACKAGES openssh-sftp-server"
PACKAGES="$PACKAGES luci-i18n-samba4-zh-cn"
# 文件管理器
PACKAGES="$PACKAGES luci-i18n-filemanager-zh-cn"
# ======== shell/custom-packages.sh =======
# 合并imm仓库以外的第三方插件
PACKAGES="$PACKAGES $CUSTOM_PACKAGES"

# 判断是否需要编译 Docker 插件
if [ "$INCLUDE_DOCKER" = "yes" ]; then
  PACKAGES="$PACKAGES luci-i18n-dockerman-zh-cn"
  echo "Adding package: luci-i18n-dockerman-zh-cn"
fi

# 若构建openclash 则添加内核
if echo "$PACKAGES" | grep -q "luci-app-openclash"; then
  echo "✅ 已选择 luci-app-openclash，添加 openclash core"
  OPENCLASH_CORE_DIR=files/etc/openclash/core
  mkdir -p $OPENCLASH_CORE_DIR
  cd $OPENCLASH_CORE_DIR

  # Download clash_meta
  echo "正在下载Clash Meta"
  CLASH_DEV_URL="https://github.com/vernesong/OpenClash/releases/download/Clash/clash-linux-amd64.tar.gz"
  CLASH_TUN_URL="https://raw.githubusercontent.com/vernesong/OpenClash/refs/heads/core/master/premium/clash-linux-amd64-2023.08.17-13-gdcc8d87.gz"
  CLASH_META_URL="https://github.com/MetaCubeX/mihomo/releases/download/v1.19.20/mihomo-linux-amd64-v1.19.20.gz"

  wget -qO- "$CLASH_DEV_URL" | tar xOvz >clash && chmod +x clash
  wget -qO- "$CLASH_TUN_URL" | gunzip -c >clash_tun && chmod +x clash_tun
  wget -qO- "$CLASH_META_URL" | gunzip -c >clash_meta && chmod +x clash_meta

  # Download GeoIP and GeoSite
  wget -qO GeoSite.dat "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.dat"
  wget -qO GeoIP.dat "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/GeoIP.dat"
  wget -qO geoip.metadb "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.metadb"
else
  echo "⚪️ 未选择 luci-app-openclash"
fi

REPO_FILE="/home/build/immortalwrt/repositories.conf"

echo "⚪️ 修改为中科大源 immortalwrt版本：$luci_version"
cat >"$REPO_FILE" <<EOF
src/gz immortalwrt_core https://chinanet.mirrors.ustc.edu.cn/immortalwrt/releases/$luci_version/targets/x86/64/packages
src/gz immortalwrt_base https://chinanet.mirrors.ustc.edu.cn/immortalwrt/releases/$luci_version/packages/x86_64/base
src/gz immortalwrt_kmods https://chinanet.mirrors.ustc.edu.cn/immortalwrt/releases/$luci_version/targets/x86/64/kmods/6.6.122-1-e7e50fbc0aafa7443418a79928da2602
src/gz immortalwrt_luci https://chinanet.mirrors.ustc.edu.cn/immortalwrt/releases/$luci_version/packages/x86_64/luci
src/gz immortalwrt_packages https://chinanet.mirrors.ustc.edu.cn/immortalwrt/releases/$luci_version/packages/x86_64/packages
src/gz immortalwrt_routing https://chinanet.mirrors.ustc.edu.cn/immortalwrt/releases/$luci_version/packages/x86_64/routing
src/gz immortalwrt_telephony https://chinanet.mirrors.ustc.edu.cn/immortalwrt/releases/$luci_version/packages/x86_64/telephony
EOF

echo -e "\n===== 当前 $REPO_FILE 配置内容 ====="
cat $REPO_FILE
echo -e "===== $REPO_FILE 打印结束 =====\n"

# ls /home/build/immortalwrt

echo "⚪️ 更新软件"
cd "/home/build/immortalwrt"
./scripts/feeds update -a
./scripts/feeds install -a

# 构建镜像
echo "$(date '+%Y-%m-%d %H:%M:%S') 构建镜像- 使用以下包构建镜像:"
echo "$PACKAGES"

make image PROFILE="generic" PACKAGES="$PACKAGES" FILES="/home/build/immortalwrt/files" ROOTFS_PARTSIZE=$PROFILE

if [ $? -ne 0 ]; then
  echo "$(date '+%Y-%m-%d %H:%M:%S') - Error: Build failed!"
  exit 1
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') - Build completed successfully."
