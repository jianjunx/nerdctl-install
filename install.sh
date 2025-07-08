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
    x86_64) ARCH="x86_64";;
    aarch64|arm64) ARCH="arm64";;
    *) echo "不支持的架构: $ARCH，退出。"; exit 1;;
esac

# 创建安装目录
mkdir -p "$BIN_DIR" "$DATA_DIR" "$SERVICE_DIR"

# 获取最新版本
if [ -n "$NERDCTL_VERSION_OVERRIDE" ]; then
    NERDCTL_VERSION="$NERDCTL_VERSION_OVERRIDE"
else
    get_latest_version() {
        local repo="$1"
        local version
        version=$(curl -s --fail --max-time 30 "https://api.github.com/repos/$repo/releases/latest" | \
                  grep -o '"tag_name": *"[^"]*"' | sed -E 's/.*"([^"]+)".*/\1/')
        if [ -z "$version" ]; then
            echo "错误：无法获取 $repo 的最新版本" >&2
            exit 1
        fi
        echo "$version"
    }
    NERDCTL_VERSION=$(get_latest_version "containerd/nerdctl")
fi
CONTAINERD_VERSION=$(get_latest_version "containerd/containerd")
RUNC_VERSION=$(get_latest_version "opencontainers/runc")

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

# 下载并安装 nerdctl
echo "下载 nerdctl $NERDCTL_VERSION..."
NERDCTL_TAR="nerdctl-$NERDCTL_VERSION-linux-$ARCH.tar.gz"
curl -L --fail "https://github.com/containerd/nerdctl/releases/download/$NERDCTL_VERSION/$NERDCTL_TAR" -o "$NERDCTL_TAR" || {
    echo "错误：下载 nerdctl 失败" >&2
    exit 1
}
tar -xzf "$NERDCTL_TAR" -C "$BIN_DIR" || {
    echo "错误：解压 nerdctl 失败" >&2
    exit 1
}
rm -f "$NERDCTL_TAR"

# 下载并安装 containerd
echo "下载 containerd $CONTAINERD_VERSION..."
CONTAINERD_TAR="containerd-$CONTAINERD_VERSION-linux-$ARCH.tar.gz"
curl -L --fail "https://github.com/containerd/containerd/releases/download/$CONTAINERD_VERSION/$CONTAINERD_TAR" -o "$CONTAINERD_TAR" || {
    echo "错误：下载 containerd 失败" >&2
    exit 1
}
tar -xzf "$CONTAINERD_TAR" -C "$BIN_DIR" || {
    echo "错误：解压 containerd 失败" >&2
    exit 1
}
rm -f "$CONTAINERD_TAR"

# 下载并安装 runc
echo "下载 runc $RUNC_VERSION..."
RUNC_TAR="runc.$ARCH"
curl -L --fail "https://github.com/opencontainers/runc/releases/download/$RUNC_VERSION/$RUNC_TAR" -o "$BIN_DIR/runc" || {
    echo "错误：下载 runc 失败" >&2
    exit 1
}
chmod +x "$BIN_DIR/runc"

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
        echo "export CONTAINERD_ADDRESS=\$HOME/.local/run/containerd.sock" >> "$config_file"
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
    echo "export CONTAINERD_ADDRESS=\$HOME/.local/run/containerd.sock"
fi

# 验证安装
echo "安装完成，验证..."
echo "验证 nerdctl..."
if ! nerdctl --version; then
    echo "警告：nerdctl 验证失败" >&2
fi

echo "验证 containerd..."
if ! containerd --version; then
    echo "警告：containerd 验证失败" >&2
fi

echo "验证 runc..."
if ! runc --version; then
    echo "警告：runc 验证失败" >&2
fi

# 测试运行（新增交互式选项）
echo
echo "是否运行测试容器（nerdctl run --rm hello-world）？(Y/n)"
read -r answer

if [[ -z "$answer" || "$answer" =~ ^[Yy]$ ]]; then
    echo "正在运行测试容器..."
    if ! nerdctl run --rm hello-world; then
        echo "警告：测试容器运行失败，但安装可能仍然成功" >&2
    fi
else
    echo "跳过测试容器。"
fi

# 新增功能：是否将 nerdctl 软链接为 docker
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

echo
echo "安装完成。"