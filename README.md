# nerdctl 自动安装脚本

一个功能完善的 nerdctl 安装脚本，支持 **root 用户（系统级）** 和 **普通用户（rootless）** 两种安装模式，包含完整的安装、配置和卸载功能。

## 📖 项目简介

本项目提供了一套完整的自动化脚本，用于在 Linux 系统上安装和管理 nerdctl（containerd 的 Docker 兼容 CLI）及其完整生态系统。支持系统级和用户级两种安装模式，满足不同使用场景的需求。

## ✨ 功能特性

- 🚀 **双模式支持**：支持 root 用户（系统级）和普通用户（rootless）两种安装模式
- 📦 **完整生态**：自动安装 nerdctl-full 包，包含所有必需组件
- 🏗️ **多架构支持**：支持 x86_64 和 arm64/aarch64 架构
- 🔧 **智能配置**：根据用户类型自动配置环境变量和服务
- 🔗 **Docker 兼容**：可选择创建 docker 软链接，提供完全兼容的体验
- 🧪 **安装验证**：内置组件验证确保安装成功
- 🗑️ **完整卸载**：提供彻底的卸载脚本，清理所有相关文件

## 📦 包含的组件

安装脚本会自动下载并配置以下组件：

| 组件 | 描述 | 用途 |
|------|------|------|
| **nerdctl** | Docker 兼容的容器 CLI | 主要的容器管理命令行工具 |
| **containerd** | 容器运行时 | 负责容器的生命周期管理 |
| **runc** | OCI 运行时 | 底层容器执行引擎 |
| **RootlessKit** | Rootless 容器支持 | 为普通用户提供容器权限管理 |
| **CNI 插件** | 容器网络插件 | 处理容器网络配置和管理 |
| **BuildKit** | 镜像构建引擎 | 高性能的容器镜像构建工具 |
| **fuse-overlayfs** | 文件系统层 | Rootless 模式的存储驱动 |
| **slirp4netns** | 网络虚拟化 | Rootless 模式的网络支持 |

## 🔧 系统要求

### 支持的操作系统
- **Ubuntu/Debian**（使用 apt 包管理器）
- **Fedora/CentOS/RHEL**（使用 dnf/yum 包管理器）
- **Arch Linux**（使用 pacman 包管理器）
- **openSUSE**（使用 zypper 包管理器）
- 其他 Linux 发行版（需手动安装依赖）

### 支持的架构
- x86_64 (amd64)
- arm64/aarch64

### 系统依赖
以下依赖会根据发行版自动安装：
- `curl`、`tar`、`systemctl`
- `fuse-overlayfs`、`slirp4netns`（rootless 模式需要）
- `iptables`、`dbus-user-session`（可选，增强功能）

## 🚀 快速开始

### 方式一：一键安装（推荐）

```bash
# 普通用户模式（rootless）
curl -fsSL https://raw.githubusercontent.com/jianjunx/nerdctl-install/main/install.sh | bash

# 系统级模式（root）
curl -fsSL https://raw.githubusercontent.com/jianjunx/nerdctl-install/main/install.sh | sudo bash
```

### 方式二：手动安装

```bash
# 1. 下载项目
git clone https://github.com/jianjunx/nerdctl-install.git
cd nerdctl-install

# 2. 选择安装模式
# 普通用户模式（推荐）
chmod +x install.sh
./install.sh

# 或者系统级模式（需要 root 权限）
sudo ./install.sh
```

## 📋 安装模式对比

| 特性 | 普通用户模式 (Rootless) | 系统级模式 (Root) |
|------|------------------------|-------------------|
| **权限要求** | 普通用户权限 | 需要 root 权限 |
| **安装位置** | `~/.local/bin` | `/usr/local/bin` |
| **服务管理** | 用户级 systemd 服务 | 系统级 systemd 服务 |
| **环境变量** | 用户级配置文件 | 系统级 `/etc/profile.d/` |
| **容器权限** | 受限的用户权限 | 完整的系统权限 |
| **网络功能** | 通过 slirp4netns | 完整的网络功能 |
| **存储驱动** | fuse-overlayfs | overlay2/fuse-overlayfs |
| **使用场景** | 开发测试、个人使用 | 生产环境、多用户系统 |

## ⚙️ 安装后配置

### 1. 环境变量生效

安装完成后，需要重新加载环境变量：

```bash
# 对于 Bash 用户
source ~/.bashrc

# 对于 Zsh 用户  
source ~/.zshrc

# 或者重新登录
```

### 2. Rootless 模式额外配置

**仅普通用户模式需要**，系统级模式可跳过：

```bash
# 配置用户命名空间映射
echo "$(whoami):100000:65536" | sudo tee -a /etc/subuid
echo "$(whoami):100000:65536" | sudo tee -a /etc/subgid

# 调整内核参数（可选，提升性能）
echo 'user.max_user_namespaces=28633' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

### 3. 验证安装

```bash
# 检查版本
nerdctl --version
containerd --version

# 测试运行容器
nerdctl run --rm hello-world

# 检查服务状态
# 普通用户模式
systemctl --user status containerd.service

# 系统级模式
sudo systemctl status containerd.service
```

## 🎯 使用指南

### 基本容器操作

```bash
# 容器管理
nerdctl pull nginx:alpine              # 拉取镜像
nerdctl run -d -p 8080:80 nginx:alpine # 运行容器
nerdctl ps                             # 查看运行中的容器
nerdctl stop <container_id>            # 停止容器
nerdctl rm <container_id>              # 删除容器

# 镜像管理
nerdctl images                         # 查看镜像列表
nerdctl rmi <image_id>                 # 删除镜像
nerdctl build -t myapp .               # 构建镜像

# 网络管理
nerdctl network ls                     # 查看网络
nerdctl network create mynet           # 创建网络

# 卷管理
nerdctl volume ls                      # 查看卷
nerdctl volume create myvolume         # 创建卷
```

### 使用 Docker 别名

如果安装时选择创建了 docker 软链接：

```bash
# 可以使用 docker 命令，完全兼容 Docker CLI
docker run -it ubuntu:latest bash
docker-compose up -d
docker build -t myapp .
```

### 高级功能

```bash
# 使用 BuildKit 构建镜像
nerdctl build --buildkit -t myapp .

# 命名空间操作
nerdctl --namespace k8s.io images     # 查看 k8s 命名空间的镜像

# 与 containerd 交互
nerdctl system info                   # 查看系统信息
nerdctl system df                     # 查看磁盘使用
```

## 🔧 服务管理

### 普通用户模式

```bash
# 查看服务状态
systemctl --user status containerd.service

# 服务控制
systemctl --user start containerd.service
systemctl --user stop containerd.service
systemctl --user restart containerd.service

# 查看日志
journalctl --user -u containerd.service -f

# 开机自启
systemctl --user enable containerd.service
```

### 系统级模式

```bash
# 查看服务状态
sudo systemctl status containerd.service

# 服务控制
sudo systemctl start containerd.service
sudo systemctl stop containerd.service
sudo systemctl restart containerd.service

# 查看日志
sudo journalctl -u containerd.service -f

# 开机自启（默认已启用）
sudo systemctl enable containerd.service
```

## 🗑️ 卸载说明

项目提供了完整的卸载脚本，支持彻底清理：

### 使用卸载脚本

```bash
# 普通用户模式
curl -fsSL https://raw.githubusercontent.com/jianjunx/nerdctl-install/main/uninstall.sh | bash

# 系统级模式
curl -fsSL https://raw.githubusercontent.com/jianjunx/nerdctl-install/main/uninstall.sh | sudo bash
```

卸载脚本会：
1. **安全确认**：要求输入 `Y` 确认卸载
2. **停止服务**：停止并禁用相关 systemd 服务
3. **删除文件**：清理所有二进制文件和配置
4. **清理数据**：删除容器镜像、卷和网络数据
5. **环境清理**：移除环境变量和服务配置
6. **验证结果**：检查清理完整性

### 手动卸载（备用方案）

如果卸载脚本无法使用，可以手动清理：

<details>
<summary>点击展开手动卸载步骤</summary>

```bash
# 1. 停止服务
# 普通用户模式
systemctl --user stop containerd.service
systemctl --user disable containerd.service

# 系统级模式
sudo systemctl stop containerd.service
sudo systemctl disable containerd.service

# 2. 删除二进制文件
# 普通用户模式
rm -rf ~/.local/bin/{nerdctl,containerd,runc,rootlesskit,buildctl,docker}
rm -rf ~/.local/lib/cni

# 系统级模式
sudo rm -rf /usr/local/bin/{nerdctl,containerd,runc,buildctl,docker}
sudo rm -rf /usr/local/lib/cni

# 3. 删除数据和配置
# 普通用户模式
rm -rf ~/.local/share/{containerd,nerdctl,buildkit}
rm -rf ~/.config/{containerd,nerdctl}
rm -rf ~/.config/systemd/user/containerd.service

# 系统级模式
sudo rm -rf /var/lib/{containerd,nerdctl,buildkit}
sudo rm -rf /etc/{containerd,nerdctl}
sudo rm -rf /etc/systemd/system/containerd.service

# 4. 清理环境变量
# 编辑 ~/.bashrc 或 ~/.zshrc，删除相关行
# 系统级模式还需删除 /etc/profile.d/nerdctl.sh
```

</details>

## 🔍 故障排除

### 常见问题及解决方案

<details>
<summary><strong>1. 命令未找到 (command not found)</strong></summary>

```bash
# 检查安装路径
ls -la ~/.local/bin/nerdctl  # 普通用户模式
ls -la /usr/local/bin/nerdctl  # 系统级模式

# 检查 PATH 环境变量
echo $PATH

# 重新加载环境变量
source ~/.bashrc  # 或 ~/.zshrc

# 手动添加到 PATH（临时解决）
export PATH=~/.local/bin:$PATH  # 普通用户模式
```

</details>

<details>
<summary><strong>2. 权限被拒绝 (permission denied)</strong></summary>

```bash
# 检查 subuid/subgid 配置（仅 rootless 模式）
grep $(whoami) /etc/subuid
grep $(whoami) /etc/subgid

# 如果没有配置，添加映射
echo "$(whoami):100000:65536" | sudo tee -a /etc/subuid
echo "$(whoami):100000:65536" | sudo tee -a /etc/subgid

# 检查用户命名空间支持
sysctl user.max_user_namespaces
```

</details>

<details>
<summary><strong>3. containerd 连接失败</strong></summary>

```bash
# 检查 containerd 服务状态
systemctl --user status containerd.service  # 普通用户模式
sudo systemctl status containerd.service     # 系统级模式

# 重启服务
systemctl --user restart containerd.service  # 普通用户模式
sudo systemctl restart containerd.service    # 系统级模式

# 检查套接字文件
ls -la ~/.local/run/containerd*.sock  # 普通用户模式
ls -la /run/containerd/*.sock         # 系统级模式

# 查看详细日志
journalctl --user -u containerd.service -f  # 普通用户模式
sudo journalctl -u containerd.service -f    # 系统级模式
```

</details>

<details>
<summary><strong>4. 网络连接问题</strong></summary>

```bash
# 检查网络相关组件（仅 rootless 模式）
which slirp4netns
which fuse-overlayfs

# 检查 CNI 插件
ls -la ~/.local/lib/cni/  # 普通用户模式
ls -la /usr/local/lib/cni/  # 系统级模式

# 测试网络连接
nerdctl run --rm alpine ping -c3 google.com
```

</details>

<details>
<summary><strong>5. 构建镜像失败</strong></summary>

```bash
# 检查 BuildKit 服务
nerdctl system info | grep BuildKit

# 重启 BuildKit（如果需要）
systemctl --user restart buildkit.service  # 普通用户模式

# 使用详细输出查看错误
nerdctl build --progress=plain -t myapp .
```

</details>

### 获取帮助

如果遇到其他问题：

1. **查看日志**：使用 `journalctl` 查看详细的服务日志
2. **检查配置**：确认环境变量和服务配置正确
3. **重新安装**：先运行卸载脚本，再重新安装
4. **提交 Issue**：在项目仓库中报告问题，提供详细的错误信息

## 🔗 相关资源

- [nerdctl 官方文档](https://github.com/containerd/nerdctl)
- [containerd 官方文档](https://containerd.io/)
- [Rootless 容器指南](https://rootlesscontaine.rs/)
- [CNI 插件文档](https://www.cni.dev/)
- [BuildKit 文档](https://github.com/moby/buildkit)

## 🤝 贡献指南

欢迎贡献代码和改进建议！

1. **Fork** 本仓库
2. 创建功能分支：`git checkout -b feature/amazing-feature`
3. 提交更改：`git commit -m 'Add amazing feature'`
4. 推送分支：`git push origin feature/amazing-feature`
5. 创建 **Pull Request**

## 📄 许可证

本项目采用 [MIT 许可证](LICENSE)。

---

<div align="center">

**⭐ 如果这个项目对你有帮助，请给个 Star！⭐**

</div>
