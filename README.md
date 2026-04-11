<img src="https://avatars.githubusercontent.com/u/53173414?s=200&v=4" alt="logo" width="200" height="200" align="right">

# ImmortalWrt 项目

ImmortalWrt 是 [OpenWrt](https://openwrt.org) 的一个分支，移植了更多的软件包，支持更多的设备，默认优化配置，并为中国大陆用户进行了本地化修改。<br/>
与上游相比，我们允许使用（无法上游的）修改/优化来提供更好的功能/性能/支持。

**默认管理地址**：http://192.168.32.10，用户名：root，密码：passwd

> ⚠️ **重要提示**：本固件只适用 X86 软路由，未适配任何硬路由。

## 下载
已构建的固件镜像可用于多种架构，并带有软件包选择，可用作 WiFi 家庭路由器。要快速找到可用于从厂商原厂固件迁移到 ImmortalWrt 的工厂镜像，请尝试 *固件选择器*。

- [ImmortalWrt 固件选择器](https://firmware-selector.immortalwrt.org/)

如果您的设备受支持，请按照 **信息** 链接查看安装说明，或查阅下面列出的支持资源。

## 开发
要构建自己的固件，您需要 GNU/Linux、BSD 或 macOS 系统（需要区分大小写的文件系统）。Cygwin 不支持，因为缺乏区分大小写的文件系统。<br/>

  ### 要求
  要使用此项目进行构建，首选 Debian 11。您需要使用基于 AMD64 架构的 CPU，至少 4GB RAM 和 25GB 可用磁盘空间。确保可以访问互联网。

  编译 ImmortalWrt 需要以下工具，不同发行版的软件包名称有所不同。

  - 以下是 Debian/Ubuntu 用户的示例：<br/>
    - 方法 1:
      <details>
        <summary>通过 APT 设置依赖项</summary>

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
      </details>
    - 方法 2:
      ```bash
      sudo bash -c 'bash <(curl -s https://build-scripts.immortalwrt.org/init_build_environment.sh)'
      ```

  注意：
  - 以非特权用户身份执行所有操作，不要使用 root，不要使用 sudo。
  - 使用基于其他架构的 CPU 应该可以编译 ImmortalWrt，但需要更多优化 - 完全不保证。
  - 您必须 __不要__ 在 PATH 或驱动器上的工作文件夹中使用空格或非 ASCII 字符。
  - 如果您使用 Windows Subsystem for Linux（或 WSL），需要从 PATH 中删除 Windows 文件夹，请参阅 [Build system setup WSL](https://openwrt.org/docs/guide-developer/build-system/wsl) 文档。
  - 使用 macOS 作为主机构建操作系统 __不推荐__。完全不保证。您可以从 [Build system setup macOS](https://openwrt.org/docs/guide-developer/build-system/buildroot.exigence.macosx) 文档中获取提示。
  - 更多详情，请参阅 [Build system setup](https://openwrt.org/docs/guide-developer/build-system/install-buildsystem) 文档。

  ### 快速开始
  1. 运行 `git clone -b <branch> --single-branch --filter=blob:none https://github.com/zxmlysxl/immortalwrt` 克隆源代码。
  2. 运行 `cd immortalwrt` 进入源代码目录。
  3. 运行 `./scripts/feeds update -a` 获取 feeds.conf / feeds.conf.default 中定义的所有最新软件包定义。
  4. 运行 `./scripts/feeds install -a` 为所有获取的软件包安装符号链接到 package/feeds/。
  5. 运行 `make menuconfig` 选择您的工具链、目标系统和固件软件包的首选配置。
  6. 运行 `make` 构建您的固件。这将下载所有源代码，构建交叉编译工具链，然后为您的目标系统交叉编译 GNU/Linux 内核和所有选择的应用程序。

  ### 相关仓库
  主仓库使用多个子仓库来管理不同类别的软件包。所有软件包都通过名为 opkg 的 OpenWrt 软件包管理器安装。如果您想开发 Web 界面或将软件包移植到 ImmortalWrt，请在下面找到合适的仓库。
  - [LuCI Web 界面](https://github.com/zxmlysxl/immortalwrt): 现代化模块化界面，通过浏览器控制设备。
  - [ImmortalWrt Packages](https://github.com/zxmlysxl/immortalwrt): 移植软件包的社区仓库。
  - [OpenWrt Routing](https://github.com/openwrt/routing): 专注于（mesh）路由的软件包。
  - [OpenWrt Video](https://github.com/openwrt/video): 专注于显示服务器和客户端（Xorg 和 Wayland）的软件包。

## 支持信息
有关受支持设备的列表，请参阅 [OpenWrt 硬件数据库](https://openwrt.org/supported_devices)

  ### 文档
  - [快速入门指南](https://openwrt.org/docs/guide-quick-start/start)
  - [用户指南](https://openwrt.org/docs/guide-user/start)
  - [开发者文档](https://openwrt.org/docs/guide-developer/start)
  - [技术参考](https://openwrt.org/docs/techref/start)

  ### 支持社区
  - 支持聊天：[Telegram](https://telegram.org/) 上的 [@ctcgfw_openwrt_discuss](https://t.me/ctcgfw_openwrt_discuss) 群组。
  - 支持聊天：[Matrix](https://matrix.org/) 上的 [#immortalwrt](https://matrix.to/#/#immortalwrt:matrix.org) 群组。

## 许可证
ImmortalWrt 根据 [GPL-2.0-only](https://spdx.org/licenses/GPL-2.0-only.html) 许可。

## 致谢
<table>
  <tr>
    <td><a href="https://dlercloud.com/"><img src="https://user-images.githubusercontent.com/22235437/111103249-f9ec6e00-8588-11eb-9bfc-67cc55574555.png" width="183" height="52" border="0" alt="Dler Cloud"></a></td>
    <td><a href="https://www.jetbrains.com/"><img src="https://resources.jetbrains.com/storage/products/company/brand/logos/jb_square.png" width="120" height="120" border="0" alt="JetBrains Black Box Logo logo"></a></td>
    <td><a href="https://sourceforge.net/"><img src="https://sourceforge.net/sflogo.php?type=17&group_id=3663829" alt="SourceForge" width=200></a></td>
  </tr>
</table>
