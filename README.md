# ZUOXM ImmortalWrt

基于 [ImmortalWrt](https://github.com/immortalwrt/immortalwrt) 的定制固件，针对 x86_64 架构优化。

## 默认登录信息

- **IP地址：** 192.168.32.10
- **用户名：** root
- **密码：** passwd
- **Web管理界面：** http://192.168.32.10

## 下载固件

从 GitHub Actions 构建产物获取最新版本：

- 进入 [Actions](https://github.com/zxmlysxl/immortalwrt/actions) 页面
- 选择最新的成功构建产物（success）
- 下载 `Build ImmortalWrt x86_64` artifacts 中的固件文件

## 编译固件

### 环境要求

- Linux 系统（推荐 Debian 11+，文件系统大小写敏感）
- AMD64 架构 CPU
- 至少 4GB 内存
- 至少 25GB 可用磁盘空间
- 网络畅通

### 编译步骤

1. 克隆源码：

```bash
git clone -b master --single-branch https://github.com/zxmlysxl/immortalwrt
cd immortalwrt
```

2. 安装编译依赖（Debian/Ubuntu）：

```bash
sudo apt update -y
sudo apt full-upgrade -y
sudo apt install -y ack antlr3 asciidoc autoconf automake autopoint binutils bison build-essential \
  bzip2 ccache clang cmake cpio curl device-tree-compiler ecj fastjar flex gawk gettext gcc-multilib \
  g++-multilib git gnutls-dev gperf haveged help2man intltool lib32gcc-s1 libc6-dev-i386 libelf-dev \
  libglib2.0-dev libgmp3-dev libltdl-dev libmpc-dev libmpfr-dev libncurses-dev libpython3-dev \
  libreadline-dev libssl-dev libtool libyaml-dev libz-dev lld llvm lrzsz mkisofs msmtp nano \
  ninja-build p7zip p7zip-full patch pkgconf python3 python3-pip python3-ply python3-docutils \
  python3-pyelftools qemu-utils re2c rsync scons squashfs-tools subversion swig texinfo uglifyjs \
  upx-ucl unzip vim wget xmlto xxd zlib1g-dev zstd
```

3. 更新并安装 feeds：

```bash
./scripts/feeds update -a
./scripts/feeds install -a
```

4. 配置编译选项：

```bash
make menuconfig
```

选择 Target System（目标系统）和 Target Profile（目标设备配置）。

5. 开始编译：

```bash
make -j$(nproc)
```

编译产物位于 `bin/targets/` 目录下。

### 跳过上游同步快速编译

本仓库使用 `skip_sync=true` 参数跳过上游合并，可直接基于当前代码编译：

```bash
gh workflow run weekly_build.yml --field skip_sync=true --repo zxmlysxl/immortalwrt
```

## 主要定制内容

- 默认 IP：192.168.32.10
- 时区：Asia/Shanghai
- 主机名：ZUOXM
- 已移除上游导致编译失败的 realtek PHY 驱动补丁

## License

基于 [GPL-2.0-only](https://spdx.org/licenses/GPL-2.0-only.html) 许可证。
