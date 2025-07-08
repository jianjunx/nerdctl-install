# nerdctl 自动安装脚本

一个自动安装 nerdctl、containerd 和 runc 的 Rootless 模式安装脚本，支持 systemd 服务管理。

## 📖 项目简介

本项目提供了一个简单易用的安装脚本，用于在 Linux 系统上自动安装和配置 nerdctl（containerd 的 Docker 兼容 CLI）及其依赖组件。所有组件均以 Rootless 模式运行，无需 root 权限即可使用容器功能。

## ✨ 功能特性

- 🚀 **一键安装**：自动下载并安装最新版本的 nerdctl、containerd 和 runc
- 🏗️ **多架构支持**：支持 x86_64 和 arm64 架构
- 🔐 **Rootless 模式**：无需 root 权限运行容器
- ⚙️ **自动配置**：自动配置环境变量和 systemd 用户服务
- 🔗 **Docker 兼容**：可选择创建 docker 别名，提供与 Docker 类似的使用体验
- 🧪 **安装验证**：内置测试容器验证安装是否成功

## 🔧 系统要求

### 支持的操作系统
- Ubuntu/Debian（使用 apt 包管理器）
- Fedora/CentOS/RHEL（使用 dnf 包管理器）
- Arch Linux（使用 pacman 包管理器）
- 其他 Linux 发行版（需手动安装依赖）

### 支持的架构
- x86_64
- arm64/aarch64

### 必需的依赖
以下依赖会自动安装：
- `fuse-overlayfs`
- `slirp4netns`

## 📦 安装步骤

### 1. 下载安装脚本

```bash
# 克隆仓库
git clone https://github.com/jianjunx/nerdctl-install.git
cd nerdctl-install

# 或直接下载脚本
curl -O https://raw.githubusercontent.com/jianjunx/nerdctl-install/main/install.sh
```

### 2. 运行安装脚本

```bash
chmod +x install.sh
./install.sh
```

### 3. 加载环境变量

根据您使用的 shell，执行相应命令：

**对于 Zsh 用户：**
```bash
source ~/.zshrc
```

**对于 Bash 用户：**
```bash
source ~/.bashrc
```

### 4. 配置 subuid/subgid（重要）

```bash
# 添加用户命名空间映射
echo "$(whoami):100000:65536" | sudo tee /etc/subuid
echo "$(whoami):100000:65536" | sudo tee /etc/subgid

# 调整内核参数
sudo sysctl user.max_user_namespaces=28633
```

## 🚀 使用方法

### 基本命令

```bash
# 查看版本
nerdctl --version

# 运行容器
nerdctl run --rm hello-world

# 拉取镜像
nerdctl pull nginx

# 运行服务
nerdctl run -d -p 8080:80 nginx
```

### 使用 Docker 别名（如果已创建软链接）

```bash
# 如果安装时选择了创建 docker 别名，可以使用 docker 命令
docker run --rm hello-world
docker pull nginx
docker ps
```

## ⚙️ 配置说明

### 安装目录结构

```
~/.local/bin/                 # 二进制文件目录
├── nerdctl                   # nerdctl 可执行文件
├── containerd               # containerd 守护进程
├── runc                     # OCI 运行时
├── containerd-rootless.sh   # Rootless 启动脚本
└── docker                   # docker 别名（可选）

~/.local/share/containerd/    # containerd 数据目录
~/.config/systemd/user/       # systemd 用户服务目录
```

### 环境变量

安装脚本会自动添加以下环境变量：

```bash
export PATH=~/.local/bin:$PATH
export CONTAINERD_ADDRESS=$HOME/.local/run/containerd.sock
```

### Systemd 服务

containerd 会作为 systemd 用户服务运行：

```bash
# 查看服务状态
systemctl --user status containerd-rootless.service

# 停止服务
systemctl --user stop containerd-rootless.service

# 重启服务
systemctl --user restart containerd-rootless.service

# 查看日志
journalctl --user -u containerd-rootless.service
```

## 🔍 故障排除

### 常见问题

**1. 命令未找到**
```bash
# 确保 PATH 环境变量包含 ~/.local/bin
echo $PATH
source ~/.bashrc  # 或 ~/.zshrc
```

**2. 权限错误**
```bash
# 检查 subuid/subgid 配置
cat /etc/subuid | grep $(whoami)
cat /etc/subgid | grep $(whoami)
```

**3. containerd 服务未运行**
```bash
# 检查服务状态
systemctl --user status containerd-rootless.service

# 重启服务
systemctl --user restart containerd-rootless.service
```

**4. 网络问题**
```bash
# 检查 slirp4netns 是否安装
which slirp4netns

# 检查用户命名空间
sysctl user.max_user_namespaces
```

### 手动卸载

如需卸载，请执行以下步骤：

```bash
# 停止并禁用服务
systemctl --user stop containerd-rootless.service
systemctl --user disable containerd-rootless.service

# 删除文件
rm -rf ~/.local/bin/nerdctl ~/.local/bin/containerd ~/.local/bin/runc
rm -rf ~/.local/share/containerd
rm -f ~/.config/systemd/user/containerd-rootless.service

# 重新加载 systemd
systemctl --user daemon-reload

# 手动删除环境变量（从 ~/.bashrc 或 ~/.zshrc 中删除相关行）
```

## ⚠️ 注意事项

1. **Docker 兼容性**：虽然 nerdctl 与 Docker 高度兼容，但某些高级功能可能存在差异
2. **性能考虑**：Rootless 模式可能在某些场景下性能略低于有权限模式
3. **网络限制**：Rootless 模式下的网络功能有一定限制
4. **存储驱动**：默认使用 fuse-overlayfs 作为存储驱动

## 📚 相关链接

- [nerdctl 官方文档](https://github.com/containerd/nerdctl)
- [containerd 官方文档](https://containerd.io/)
- [Rootless 容器指南](https://rootlesscontaine.rs/)

## 🤝 贡献

欢迎提交 Issue 和 Pull Request 来改进此项目！

## 📄 许可证

本项目采用 MIT 许可证。详情请查看 [LICENSE](LICENSE) 文件。
