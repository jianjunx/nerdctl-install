#!/bin/bash
# nerdctl 完整卸载脚本
# 支持 root 用户（系统级）和普通用户（rootless）模式

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 检测用户类型
if [ "$(id -u)" -eq 0 ]; then
    IS_ROOT_USER="true"
    USER_NAME="${SUDO_USER:-root}"
    USER_HOME="${SUDO_HOME:-/root}"
    BIN_DIR="/usr/local/bin"
    CNI_DIR="/usr/local/lib/cni"
    SERVICE_FILE="/etc/systemd/system/containerd.service"
    ENV_FILE="/etc/profile.d/nerdctl.sh"
else
    IS_ROOT_USER="false"
    USER_NAME="$(whoami)"
    USER_HOME="$HOME"
    BIN_DIR="$USER_HOME/.local/bin"
    CNI_DIR="$USER_HOME/.local/lib/cni"
    SERVICE_FILE=""
    ENV_FILE=""
fi

echo -e "${BLUE}=========================================="
echo "🗑️  nerdctl 卸载脚本"
echo "=========================================="
echo -e "检测到的运行模式：${YELLOW}$([ "$IS_ROOT_USER" = "true" ] && echo "系统级 (root)" || echo "用户级 (rootless)")${NC}"
echo "用户：$USER_NAME"
echo "安装路径：$BIN_DIR"
echo -e "=========================================${NC}"

# 安全确认
echo
echo -e "${RED}⚠️  警告：此操作将完全卸载 nerdctl 及相关组件！${NC}"
echo
echo "将要删除的内容包括："
echo "• nerdctl、containerd、runc 等二进制文件"
echo "• CNI 插件和配置"
echo "• systemd 服务配置"
echo "• 环境变量配置"
echo "• 容器镜像和数据（如果存在）"
if [ "$IS_ROOT_USER" = "false" ]; then
    echo "• rootless 容器配置"
    echo "• 用户级 systemd 服务"
fi
echo
echo -e "${YELLOW}此操作不可逆转！${NC}"
echo
echo -n "确定要继续卸载吗？请输入 Y 确认: "
read -r confirm

if [ "$confirm" != "Y" ]; then
    echo "❌ 卸载已取消"
    exit 0
fi

echo
echo -e "${GREEN}开始卸载 nerdctl...${NC}"

# 停止相关服务
echo "=========================================="
echo "🛑 停止服务"
echo "=========================================="

if [ "$IS_ROOT_USER" = "true" ]; then
    # 系统级服务
    if systemctl is-active --quiet containerd 2>/dev/null; then
        echo "停止系统级 containerd 服务..."
        systemctl stop containerd || echo "⚠️  停止服务失败，继续..."
    fi
    
    if systemctl is-enabled --quiet containerd 2>/dev/null; then
        echo "禁用系统级 containerd 服务..."
        systemctl disable containerd || echo "⚠️  禁用服务失败，继续..."
    fi
else
    # 用户级服务
    echo "停止 rootless containerd 服务..."
    
    # 尝试使用 containerd-rootless-setuptool.sh 卸载
    if [ -f "$BIN_DIR/containerd-rootless-setuptool.sh" ]; then
        echo "使用 containerd-rootless-setuptool.sh 卸载..."
        "$BIN_DIR/containerd-rootless-setuptool.sh" uninstall || echo "⚠️  rootless 卸载失败，继续手动清理..."
    fi
    
    # 手动停止用户服务
    systemctl --user stop containerd.service 2>/dev/null || true
    systemctl --user disable containerd.service 2>/dev/null || true
    
    # 禁用 linger
    if command -v loginctl >/dev/null 2>&1; then
        echo "禁用 linger..."
        sudo loginctl disable-linger "$USER_NAME" 2>/dev/null || echo "⚠️  禁用 linger 失败，继续..."
    fi
fi

# 删除二进制文件
echo "=========================================="
echo "🗂️  删除二进制文件"
echo "=========================================="

BINARIES="nerdctl containerd runc rootlesskit rootlesskit-docker-proxy containerd-rootless-setuptool.sh containerd-rootless.sh buildctl buildkitd fuse-overlayfs slirp4netns docker"

for binary in $BINARIES; do
    if [ -f "$BIN_DIR/$binary" ]; then
        echo "删除 $BIN_DIR/$binary"
        rm -f "$BIN_DIR/$binary" || echo "⚠️  删除 $binary 失败"
    fi
done

# 删除 CNI 插件
echo "=========================================="
echo "🌐 删除 CNI 插件"
echo "=========================================="

if [ -d "$CNI_DIR" ]; then
    echo "删除 CNI 目录: $CNI_DIR"
    rm -rf "$CNI_DIR" || echo "⚠️  删除 CNI 目录失败"
fi

# 删除服务文件
echo "=========================================="
echo "⚙️  删除服务配置"
echo "=========================================="

if [ "$IS_ROOT_USER" = "true" ]; then
    if [ -f "$SERVICE_FILE" ]; then
        echo "删除系统服务文件: $SERVICE_FILE"
        rm -f "$SERVICE_FILE" || echo "⚠️  删除服务文件失败"
        systemctl daemon-reload || echo "⚠️  重载 systemd 失败"
    fi
else
    # 删除用户级服务文件
    USER_SERVICE_DIR="$USER_HOME/.config/systemd/user"
    if [ -f "$USER_SERVICE_DIR/containerd.service" ]; then
        echo "删除用户服务文件: $USER_SERVICE_DIR/containerd.service"
        rm -f "$USER_SERVICE_DIR/containerd.service" || echo "⚠️  删除用户服务文件失败"
        systemctl --user daemon-reload 2>/dev/null || true
    fi
fi

# 删除环境变量配置
echo "=========================================="
echo "🌍 删除环境变量配置"
echo "=========================================="

if [ "$IS_ROOT_USER" = "true" ]; then
    if [ -f "$ENV_FILE" ]; then
        echo "删除系统环境变量文件: $ENV_FILE"
        rm -f "$ENV_FILE" || echo "⚠️  删除环境变量文件失败"
    fi
else
    # 从用户配置文件中移除环境变量
    remove_env_vars() {
        local config_file="$1"
        if [ -f "$config_file" ]; then
            echo "从 $config_file 移除环境变量..."
            # 移除包含 nerdctl 相关的行
            sed -i '/nerdctl/d' "$config_file" 2>/dev/null || true
            sed -i '/CNI_PATH.*\.local\/lib\/cni/d' "$config_file" 2>/dev/null || true
            sed -i '/PATH.*\.local\/bin/d' "$config_file" 2>/dev/null || true
        fi
    }
    
    remove_env_vars "$USER_HOME/.bashrc"
    remove_env_vars "$USER_HOME/.zshrc"
fi

# 清理容器数据和配置
echo "=========================================="
echo "🗄️  清理容器数据"
echo "=========================================="

if [ "$IS_ROOT_USER" = "true" ]; then
    # 系统级数据目录
    DATA_DIRS="/var/lib/containerd /var/lib/nerdctl /var/lib/buildkit"
    CONFIG_DIRS="/etc/containerd /etc/nerdctl"
else
    # 用户级数据目录
    DATA_DIRS="$USER_HOME/.local/share/containerd $USER_HOME/.local/share/nerdctl $USER_HOME/.local/share/buildkit"
    CONFIG_DIRS="$USER_HOME/.config/containerd $USER_HOME/.config/nerdctl"
fi

for dir in $DATA_DIRS $CONFIG_DIRS; do
    if [ -d "$dir" ]; then
        echo "删除数据目录: $dir"
        rm -rf "$dir" || echo "⚠️  删除 $dir 失败"
    fi
done

# 清理 rootless 特定配置
if [ "$IS_ROOT_USER" = "false" ]; then
    echo "=========================================="
    echo "👤 清理 rootless 配置"
    echo "=========================================="
    
    # 清理 XDG 运行时目录
    RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    ROOTLESS_DIRS="$RUNTIME_DIR/containerd-rootless $RUNTIME_DIR/buildkit-rootless"
    
    for dir in $ROOTLESS_DIRS; do
        if [ -d "$dir" ]; then
            echo "删除 rootless 运行时目录: $dir"
            rm -rf "$dir" || echo "⚠️  删除 $dir 失败"
        fi
    done
    
    # 清理可能的网络命名空间
    if command -v ip >/dev/null 2>&1; then
        echo "清理网络命名空间..."
        ip netns list 2>/dev/null | grep -E "cni-|rootless" | while read -r ns; do
            echo "删除网络命名空间: $ns"
            sudo ip netns delete "$ns" 2>/dev/null || true
        done
    fi
fi

# 清理临时文件
echo "=========================================="
echo "🧹 清理临时文件"
echo "=========================================="

TEMP_DIRS="/tmp/nerdctl* /tmp/containerd* /tmp/buildkit*"
for pattern in $TEMP_DIRS; do
    if ls $pattern 2>/dev/null | head -1 >/dev/null; then
        echo "删除临时文件: $pattern"
        rm -rf $pattern 2>/dev/null || echo "⚠️  删除临时文件失败"
    fi
done

# 验证卸载结果
echo "=========================================="
echo "🔍 验证卸载结果"
echo "=========================================="

echo "检查残留文件..."
REMAINING_FILES=""

for binary in nerdctl containerd runc; do
    if command -v "$binary" >/dev/null 2>&1; then
        REMAINING_FILES="$REMAINING_FILES $binary"
    fi
done

if [ -n "$REMAINING_FILES" ]; then
    echo -e "${YELLOW}⚠️  检测到以下命令仍然可用:$REMAINING_FILES${NC}"
    echo "这些可能来自其他安装源（如包管理器）"
else
    echo "✅ 未检测到残留的 nerdctl 相关命令"
fi

# 最终提示
echo "=========================================="
echo -e "${GREEN}🎉 卸载完成！${NC}"
echo "=========================================="

echo "已清理的内容："
echo "• 所有二进制文件和可执行程序"
echo "• CNI 插件和网络配置"
echo "• 系统服务和用户服务"
echo "• 环境变量配置"
echo "• 容器镜像和数据"
echo "• 配置文件和缓存"
if [ "$IS_ROOT_USER" = "false" ]; then
    echo "• rootless 容器配置"
    echo "• 网络命名空间"
fi

echo
echo -e "${BLUE}💡 建议操作：${NC}"
if [ "$IS_ROOT_USER" = "true" ]; then
    echo "• 重启系统以确保所有更改生效"
else
    echo "• 重新登录以刷新环境变量"
    echo "• 如果使用了 shell 配置文件，请检查是否需要手动清理"
fi

echo
echo -e "${GREEN}感谢使用 nerdctl！${NC}"
echo "如有问题，请查看项目文档或提交 issue"
echo "=========================================="
