#!/bin/bash
# smartRoute 一键启用/禁用/卸载
# 用法：./toggle.sh enable|disable|uninstall|status

CONFIG_FILE="$HOME/.codex/config.toml"
TRASH_DIR="$PWD/.trash"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

archive_file() {
  local src="$1"
  if [ -f "$src" ]; then
    mkdir -p "$TRASH_DIR"
    local base
    base="$(basename "$src")"
    mv "$src" "$TRASH_DIR/${base}_${TIMESTAMP}"
    echo "   已归档: $src -> $TRASH_DIR/${base}_${TIMESTAMP}"
  fi
}

backup_config() {
  if [ -f "$CONFIG_FILE" ]; then
    mkdir -p "$TRASH_DIR"
    cp "$CONFIG_FILE" "$TRASH_DIR/config.toml_${TIMESTAMP}.bak"
    echo "   已备份配置: $TRASH_DIR/config.toml_${TIMESTAMP}.bak"
  fi
}

case "${1:-status}" in
  enable)
    if grep -q "codexsaver" "$CONFIG_FILE" 2>/dev/null; then
      backup_config
      # 取消注释
      sed -i '' '/^# \[mcp_servers\.codexsaver\]/,/^# tool_timeout_sec/s/^# //' "$CONFIG_FILE"
      echo "✅ smartRoute 已启用"
    else
      echo "⚠️  未找到 smartRoute 配置，先运行 python cli.py install"
    fi
    ;;

  disable)
    if grep -q "\[mcp_servers.codexsaver\]" "$CONFIG_FILE" 2>/dev/null; then
      backup_config
      # 注释掉整个 codexsaver 段
      sed -i '' '/^\[mcp_servers\.codexsaver\]/,/^tool_timeout_sec/s/^/# /' "$CONFIG_FILE"
      echo "✅ smartRoute 已禁用（注释掉 MCP 配置）"
    else
      echo "ℹ️  smartRoute 已经是禁用状态或未安装"
    fi
    ;;

  uninstall)
    backup_config
    # 移除配置段
    if [ -f "$CONFIG_FILE" ]; then
      sed -i '' '/^\[mcp_servers\.codexsaver\]/,/^tool_timeout_sec/d' "$CONFIG_FILE"
    fi
    # 归档 launcher / 本地配置
    archive_file "$HOME/.codexsaver/codexsaver_mcp.py"
    archive_file "$HOME/.codexsaver/config.json"
    echo "✅ smartRoute 已卸载（MCP 配置已移除，launcher/本地配置已归档到 .trash）"
    ;;

  status)
    if grep -q "\[mcp_servers.codexsaver\]" "$CONFIG_FILE" 2>/dev/null; then
      echo "✅ smartRoute 已安装且启用"
      grep -A3 "\[mcp_servers.codexsaver\]" "$CONFIG_FILE"
    elif grep -q "# \[mcp_servers.codexsaver\]" "$CONFIG_FILE" 2>/dev/null; then
      echo "⏸️  smartRoute 已安装但已禁用（被注释）"
    else
      echo "❌ smartRoute 未安装"
    fi
    # 检查 launcher
    if [ -f "$HOME/.codexsaver/codexsaver_mcp.py" ]; then
      echo "   Launcher: 存在（~/.codexsaver/codexsaver_mcp.py）"
    else
      echo "   Launcher: 不存在"
    fi
    ;;

  *)
    echo "用法: $0 {enable|disable|uninstall|status}"
    exit 1
    ;;
esac
