#!/bin/bash

# 在脚本开头添加 macOS 检测
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "错误：此脚本仅支持 Linux 系统。"
    echo "在 macOS 上使用容器，请选择："
    echo "1. 安装 Docker Desktop: brew install --cask docker"
    echo "2. 使用 Lima + nerdctl:"
    echo "   brew install lima"
    echo "   limactl start"
    echo "   lima nerdctl run hello-world"
    exit 1
fi

# 获取当前用户信息
USER_NAME=$(whoami)
USER_HOME="$HOME"
BIN_DIR="$USER_HOME/.local/bin"
DATA_DIR="$USER_HOME/.local/share/containerd"
SERVICE_DIR="$USER_HOME/.config/systemd/user"
SERVICE_FILE="$SERVICE_DIR/containerd-rootless.service"

# 自动检测架构
ARCH=$(uname -m)
case $ARCH in
    x86_64|amd64) ARCH="amd64";;
    aarch64|arm64) ARCH="arm64";;
    *) echo "不支持的架构: $ARCH，退出。"; exit 1;;
esac

# 创建安装目录
mkdir -p "$BIN_DIR" "$DATA_DIR" "$SERVICE_DIR"

# 设置PATH和CNI_PATH，确保脚本中能找到安装的工具
export PATH="$BIN_DIR:$PATH"
export CNI_PATH="$USER_HOME/.local/libexec/cni"

# 通用下载函数
download_file() {
    local url="$1"
    local output="$2"
    local description="$3"
    
    echo "=========================================="
    echo "下载 $description"
    echo "来源: $url"
    echo "目标: $output"
    echo "=========================================="
    
    if curl -L --fail --progress-bar "$url" -o "$output"; then
        echo "✅ $description 下载完成"
        return 0
    else
        echo "❌ 错误：$description 下载失败" >&2
        return 1
    fi
}

# 获取最新版本
echo "获取最新版本信息..."
if [ -n "$NERDCTL_VERSION_OVERRIDE" ]; then
    NERDCTL_VERSION="$NERDCTL_VERSION_OVERRIDE"
    echo "使用指定的 nerdctl 版本: $NERDCTL_VERSION"
else
    get_latest_version() {
        local repo="$1"
        local version
        echo "正在获取 $repo 的最新版本..." >&2
        version=$(curl -s --fail --max-time 30 "https://api.github.com/repos/$repo/releases/latest" | \
                  grep -o '"tag_name": *"[^"]*"' | sed -E 's/.*"([^"]+)".*/\1/')
        if [ -z "$version" ]; then
            echo "错误：无法获取 $repo 的最新版本" >&2
            exit 1
        fi
        echo "$version"
    }
    NERDCTL_VERSION=$(get_latest_version "containerd/nerdctl")
    echo "nerdctl 最新版本: $NERDCTL_VERSION"
fi
echo "版本信息获取完成"
echo

# 安装依赖
echo "安装依赖项..."
if command -v apt &> /dev/null; then
    sudo apt update
    sudo apt install -y fuse-overlayfs slirp4netns
elif command -v dnf &> /dev/null; then
    sudo dnf install -y fuse-overlayfs slirp4netns
elif command -v pacman &> /dev/null; then
    sudo pacman -S --noconfirm fuse-overlayfs slirp4netns
elif command -v yum &> /dev/null; then
    sudo yum install -y fuse-overlayfs slirp4netns
elif command -v brew &> /dev/null; then
    sudo brew install fuse-overlayfs slirp4netns
else
    echo "未知的包管理器，跳过依赖安装。"
fi

# 下载并安装 nerdctl-full（包含所有依赖项）
# 去除版本号中的 v 前缀用于文件名
NERDCTL_VERSION_CLEAN="${NERDCTL_VERSION#v}"
NERDCTL_FULL_TAR="nerdctl-full-$NERDCTL_VERSION_CLEAN-linux-$ARCH.tar.gz"
NERDCTL_FULL_URL="https://github.com/containerd/nerdctl/releases/download/$NERDCTL_VERSION/$NERDCTL_FULL_TAR"

download_file "$NERDCTL_FULL_URL" "$NERDCTL_FULL_TAR" "nerdctl-full $NERDCTL_VERSION" || exit 1

echo "📦 解压 nerdctl-full（包含所有组件）..."
# 创建临时目录解压
TEMP_DIR=$(mktemp -d)
tar -xzf "$NERDCTL_FULL_TAR" -C "$TEMP_DIR" || {
    echo "❌ 错误：解压 nerdctl-full 失败" >&2
    exit 1
}

# 复制二进制文件到目标目录
echo "📂 安装组件到 $BIN_DIR..."
cp "$TEMP_DIR/bin/"* "$BIN_DIR/" || {
    echo "❌ 错误：复制文件失败" >&2
    exit 1
}

# 设置 CNI 插件路径
CNI_DIR="$USER_HOME/.local/libexec/cni"
mkdir -p "$CNI_DIR"
if [ -d "$TEMP_DIR/libexec/cni" ]; then
    cp "$TEMP_DIR/libexec/cni/"* "$CNI_DIR/" || {
        echo "❌ 错误：复制 CNI 插件失败" >&2
        exit 1
    }
fi

# 清理临时文件
rm -rf "$TEMP_DIR" "$NERDCTL_FULL_TAR"
echo "✅ nerdctl-full 安装完成"
echo "✅ 已安装：nerdctl、containerd、runc、RootlessKit、CNI插件等"
echo

# 初始化 rootless containerd
echo "初始化 rootless containerd..."
if [ ! -f "$BIN_DIR/containerd-rootless-setuptool.sh" ]; then
    echo "错误：找不到 containerd-rootless-setuptool.sh" >&2
    exit 1
fi
"$BIN_DIR/containerd-rootless-setuptool.sh" install || {
    echo "错误：初始化 rootless containerd 失败" >&2
    exit 1
}

# 创建 systemd 用户服务
echo "创建 systemd 用户服务..."
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=containerd Rootless Mode
After=network.target

[Service]
ExecStart=$BIN_DIR/containerd-rootless.sh
Restart=always
User=$USER_NAME
WorkingDirectory=$USER_HOME

[Install]
WantedBy=default.target
EOF

# 启用 linger（确保服务在用户注销后仍运行）
echo "启用 linger..."
sudo loginctl enable-linger "$USER_NAME"

# 启用并启动服务
echo "启用并启动 systemd 用户服务..."
systemctl --user daemon-reload
systemctl --user enable containerd-rootless.service
systemctl --user start containerd-rootless.service

# 配置环境变量
echo "配置环境变量..."
add_env_vars() {
    local config_file="$1"
    if [ -f "$config_file" ]; then
        echo "export PATH=$BIN_DIR:\$PATH" >> "$config_file"
        echo "export CNI_PATH=\$HOME/.local/libexec/cni" >> "$config_file"
        echo "已添加环境变量到 $config_file"
    fi
}

add_env_vars "$USER_HOME/.bashrc"
add_env_vars "$USER_HOME/.zshrc"

# 提示用户根据 shell 类型加载配置
SHELL_TYPE=$(basename "$SHELL")
if [ "$SHELL_TYPE" = "zsh" ]; then
    echo "当前使用 Zsh，请执行以下命令使配置生效："
    echo "source ~/.zshrc"
elif [ "$SHELL_TYPE" = "bash" ]; then
    echo "当前使用 Bash，请执行以下命令使配置生效："
    echo "source ~/.bashrc"
else
    echo "检测到非 Bash/Zsh shell ($SHELL_TYPE)，请手动执行以下命令："
    echo "export PATH=$BIN_DIR:\$PATH"
    echo "export CNI_PATH=\$HOME/.local/libexec/cni"
fi

# 验证安装
echo "=========================================="
echo "🔍 验证安装结果"
echo "=========================================="

echo "验证安装的组件..."
if nerdctl --version; then
    echo "✅ nerdctl 验证成功"
else
    echo "⚠️  警告：nerdctl 验证失败" >&2
fi

if containerd --version; then
    echo "✅ containerd 验证成功"
else
    echo "⚠️  警告：containerd 验证失败" >&2
fi

if runc --version; then
    echo "✅ runc 验证成功"  
else
    echo "⚠️  警告：runc 验证失败" >&2
fi

if rootlesskit --version; then
    echo "✅ rootlesskit 验证成功"
else
    echo "⚠️  警告：rootlesskit 验证失败" >&2
fi
echo



# 是否将 nerdctl 软链接为 docker
echo
echo "是否将 nerdctl 软链接为 docker？(y/N)"
read -r answer

if [[ "$answer" =~ ^[Yy]$ ]]; then
    DOCKER_LINK="$BIN_DIR/docker"
    if [ -e "$DOCKER_LINK" ]; then
        echo "警告：$DOCKER_LINK 已存在，将被覆盖。"
    fi
    if ln -sf "$BIN_DIR/nerdctl" "$DOCKER_LINK"; then
        echo "已创建软链接：$DOCKER_LINK -> $BIN_DIR/nerdctl"
        echo "警告：此操作可能导致与原生 Docker 的行为不一致，请确认是否需要。"
        echo "请确保 $BIN_DIR 在您的 PATH 环境变量中。"
    else
        echo "错误：创建软链接失败" >&2
    fi
else
    echo "未创建软链接，您可以通过 nerdctl 命令使用容器功能。"
fi

# 提示用户配置 subuid/subgid 和内核参数
echo
echo "请确保已配置 subuid/subgid（示例）："
echo "echo '$USER_NAME:100000:65536' | sudo tee /etc/subuid"
echo "echo '$USER_NAME:100000:65536' | sudo tee /etc/subgid"
echo "并调整内核参数（需 root 权限）："
echo "sudo sysctl user.max_user_namespaces=28633"

echo "=========================================="
echo "🎉 安装完成！"
echo "=========================================="
echo "感谢使用 nerdctl 安装脚本！"
echo
echo "📦 已安装的组件："
echo "  • nerdctl (Docker-compatible CLI)"
echo "  • containerd (容器运行时)"
echo "  • runc (OCI运行时)"
echo "  • RootlessKit (rootless容器支持)"
echo "  • CNI插件 (网络支持)"
echo "  • BuildKit (镜像构建)"
echo
echo "📖 使用指南："
echo "  • 运行容器: nerdctl run -it --rm alpine"
echo "  • 查看帮助: nerdctl --help"
echo "  • 查看版本: nerdctl --version"
echo
echo "💡 提示："
echo "  • 如果命令找不到，请先执行 source ~/.bashrc 或 source ~/.zshrc"
echo "  • 确保已配置 subuid/subgid（如上所示）"
echo "  • rootless模式已就绪，可直接使用无需sudo"
echo "  • 有问题请查看 README.md 或提交 issue"
echo "=========================================="