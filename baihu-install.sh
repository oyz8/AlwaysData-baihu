#!/bin/bash
set -euo pipefail

########################################
# AlwaysData 白虎面板安装脚本
########################################

BAIHU_USER=$(whoami)
BAIHU_HOME="/home/${BAIHU_USER}/www"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'

log_info() { echo -e "${CYAN}[INFO]${NC} $*"; }
log_ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_err()  { echo -e "${RED}[ERROR]${NC} $*"; }

echo ""
echo "=========================================="
echo "  AlwaysData 白虎面板简易安装"
echo "=========================================="
echo ""

# ---------- 版本选择 ----------
get_latest_version() {
    local api="https://api.github.com/repos/engigu/baihu-panel/releases/latest"
    local json
    json=$(curl -sSf "$api" 2>/dev/null) || return 1
    python3 -c "import sys,json; print(json.load(sys.stdin)['tag_name'])" <<< "$json" 2>/dev/null || \
    python -c "import sys,json; print(json.load(sys.stdin)['tag_name'])" <<< "$json"
}

get_release_list() {
    local api="https://api.github.com/repos/engigu/baihu-panel/releases?per_page=20"
    local json
    json=$(curl -sSf "$api" 2>/dev/null) || return 1
    python3 -c "import sys,json; [print(r['tag_name']) for r in json.load(sys.stdin)]" <<< "$json" 2>/dev/null || \
    python -c "import sys,json; [print(r['tag_name']) for r in json.load(sys.stdin)]" <<< "$json"
}

DEFAULT_VERSION="v1.0.45"   # 网络失败时的兜底版本
BAIHU_VERSION=""

echo "请选择安装版本:"
echo "  1) 最新版 (推荐)"
echo "  2) 从发布列表中选择"
echo "  3) 手动输入版本号 (例如 v1.0.45)"
read -p "请输入选项 [1]: " ver_choice
ver_choice=${ver_choice:-1}

case "$ver_choice" in
    1)
        log_info "正在获取最新版本..."
        BAIHU_VERSION=$(get_latest_version) || {
            log_warn "无法获取最新版本，使用默认版本 ${DEFAULT_VERSION}"
            BAIHU_VERSION="$DEFAULT_VERSION"
        }
        log_ok "选择版本: ${BAIHU_VERSION}"
        ;;
    2)
        log_info "正在获取版本列表..."
        mapfile -t versions < <(get_release_list || true)
        if [ ${#versions[@]} -eq 0 ]; then
            log_warn "获取列表失败，使用默认版本 ${DEFAULT_VERSION}"
            BAIHU_VERSION="$DEFAULT_VERSION"
        else
            echo "可用版本:"
            for i in "${!versions[@]}"; do
                printf "  %2d) %s\n" $((i+1)) "${versions[$i]}"
            done
            read -p "请输入序号 [1]: " idx
            idx=${idx:-1}
            if [[ "$idx" =~ ^[0-9]+$ ]] && [ "$idx" -ge 1 ] && [ "$idx" -le "${#versions[@]}" ]; then
                BAIHU_VERSION="${versions[$((idx-1))]}"
            else
                log_warn "序号无效，使用第一个版本 ${versions[0]}"
                BAIHU_VERSION="${versions[0]}"
            fi
            log_ok "选择版本: ${BAIHU_VERSION}"
        fi
        ;;
    3)
        read -p "请输入版本号 (如 v1.0.39): " BAIHU_VERSION
        if [[ ! "$BAIHU_VERSION" =~ ^v ]]; then
            log_err "版本号必须以 'v' 开头"
            exit 1
        fi
        ;;
    *)
        log_err "无效选项"
        exit 1
        ;;
esac

BAIHU_URL="https://github.com/engigu/baihu-panel/releases/download/${BAIHU_VERSION}/baihu-linux-amd64.tar.gz"

# ---------- 安装流程 ----------
log_info "准备安装环境..."
mkdir -p "$BAIHU_HOME"
cd "$BAIHU_HOME"

# ========== 增强防呆：检测已有程序和文件 ==========
EXISTING_BAIHU=false
EXISTING_CONFIG=false
EXISTING_DATA=false
EXISTING_LOGS=false

if [ -f "./baihu" ]; then
    EXISTING_BAIHU=true
fi
if [ -f "./configs/config.ini" ]; then
    EXISTING_CONFIG=true
fi
if [ -d "./data" ] && [ "$(ls -A ./data 2>/dev/null)" ]; then
    EXISTING_DATA=true
fi
if [ -d "./logs" ] && [ "$(ls -A ./logs 2>/dev/null)" ]; then
    EXISTING_LOGS=true
fi

if $EXISTING_BAIHU || $EXISTING_CONFIG || $EXISTING_DATA; then
    echo ""
    log_warn "检测到已有安装痕迹，当前状态："
    echo "  主程序 (baihu):      $($EXISTING_BAIHU && echo '存在' || echo '无')"
    echo "  配置文件 (config.ini): $($EXISTING_CONFIG && echo '存在' || echo '无')"
    echo "  数据目录 (data):      $($EXISTING_DATA && echo '存在（含文件）' || echo '无')"
    echo "  日志目录 (logs):      $($EXISTING_LOGS && echo '存在（含文件）' || echo '无')"
    echo ""
    echo "请选择操作："
    echo "  1) 覆盖安装（保留现有数据和配置，仅更新主程序）"
    echo "  2) 全新安装（备份旧目录后，删除所有旧文件）"
    echo "  3) 取消安装"
    read -p "请输入选项 [3]: " conflict_choice
    conflict_choice=${conflict_choice:-3}

    case "$conflict_choice" in
        1)
            log_info "将仅覆盖主程序，配置文件和数据目录保持不变。"
            ;;
        2)
            BACKUP_DIR="${BAIHU_HOME}_backup_$(date +%Y%m%d_%H%M%S)"
            log_info "备份旧目录到: ${BACKUP_DIR}"
            mkdir -p "$BACKUP_DIR"
            # 移动旧文件到备份目录（忽略错误）
            if $EXISTING_BAIHU; then
                mv ./baihu "$BACKUP_DIR/" 2>/dev/null || true
            fi
            if $EXISTING_CONFIG; then
                mv ./configs "$BACKUP_DIR/" 2>/dev/null || true
            fi
            if $EXISTING_DATA; then
                mv ./data "$BACKUP_DIR/" 2>/dev/null || true
            fi
            if $EXISTING_LOGS; then
                mv ./logs "$BACKUP_DIR/" 2>/dev/null || true
            fi
            rm -f baihu-linux-amd64.tar.gz 2>/dev/null || true
            log_ok "旧文件已备份，开始全新安装。"
            ;;
        3|*)
            log_info "已取消安装，保留现有文件。"
            rm -f baihu-linux-amd64.tar.gz 2>/dev/null || true
            exit 0
            ;;
    esac
fi

# 停止旧进程（如果正在运行）
if pgrep -f "baihu server" >/dev/null 2>&1; then
    log_warn "停止旧进程..."
    pkill -f "baihu server" 2>/dev/null || true
    sleep 3
    pgrep -f "baihu server" >/dev/null 2>&1 && pkill -9 -f "baihu server" 2>/dev/null || true
    sleep 1
fi

# 下载
log_info "下载白虎面板 ${BAIHU_VERSION}..."
rm -f baihu baihu-linux-amd64.tar.gz 2>/dev/null || true
if ! wget -q --show-progress -O baihu-linux-amd64.tar.gz "$BAIHU_URL"; then
    log_err "下载失败，请检查版本号或网络"
    exit 1
fi

# 解压
log_info "解压安装..."
tar -xzf baihu-linux-amd64.tar.gz
mv baihu-linux-amd64 baihu
chmod +x baihu
rm -f baihu-linux-amd64.tar.gz
log_ok "主程序就绪"

# 配置文件（仅在不存在时创建）
if [ ! -f "./configs/config.ini" ]; then
    log_info "生成配置文件..."
    mkdir -p configs logs
    cat > configs/config.ini << 'EOF'
[server]
port = 8100
host = 0.0.0.0
url_prefix =

[database]
type = sqlite
host = localhost
port = 3306
user = root
password = 
dbname = ql_panel
table_prefix = baihu_
EOF
    log_ok "配置已写入"
else
    log_info "检测到已有配置文件，将保留。"
fi

# 确保日志目录存在
mkdir -p logs

# 首次启动获取默认密码
log_info "首次启动，获取默认密码..."
nohup ./baihu server > logs/baihu-init.log 2>&1 &
BAIHU_PID=$!

DEFAULT_PASSWORD=""
RETRY=0
while [ $RETRY -lt 30 ]; do
    DEFAULT_PASSWORD=$(grep -oP '密\s*码:\s*\K[^,[:space:]]+' logs/baihu-init.log 2>/dev/null | tail -n 1 || true)
    [ -z "$DEFAULT_PASSWORD" ] && \
        DEFAULT_PASSWORD=$(grep -oP 'password:\s*\K\S+' logs/baihu-init.log 2>/dev/null | tail -n 1 || true)
    [ -n "$DEFAULT_PASSWORD" ] && break
    RETRY=$((RETRY + 1))
    sleep 2
done

# 停止进程（让 AlwaysData 站点配置管理启动）
kill "$BAIHU_PID" 2>/dev/null || true
wait "$BAIHU_PID" 2>/dev/null || true

# ========== 安装完成提示 ==========
echo ""
echo "=========================================="
echo "  🎉 安装完成！"
echo "=========================================="
echo ""

PROJECT_URL="https://${BAIHU_USER}.alwaysdata.net"

if [ -n "$DEFAULT_PASSWORD" ]; then
    echo "  👤 用户名: admin"
    echo "  🔑 密码:   ${DEFAULT_PASSWORD}"
else
    log_warn "未能自动获取密码，请查看日志:"
    echo "     tail ~/www/logs/baihu-init.log"
fi

echo ""
log_warn "请在 AlwaysData 控制台完成最后配置:"
echo ""
echo "  1. 打开: https://admin.alwaysdata.com/site/"
echo "  2. 点击站点 → web → Sites → 齿轮(Modify)"
echo "  3. 修改为:"
echo "     ┌────────────────────────────────────────┐"
echo "     │ Configuration:     User program        │"
echo "     │ Command:           ./baihu server      │"
echo "     │ Working directory: /home/${BAIHU_USER}/www        │"
echo "     └────────────────────────────────────────┘"
echo "  4. Submit 保存 → 返回上一页 Restart 刷新站点"
echo ""
echo "  🌐 访问: ${PROJECT_URL}"
echo ""
echo "=========================================="

# ---------- 保活选项 ----------
echo ""
echo ">>> 站点保活选项 <<<"
echo "AlwaysData 免费主机长时间无访问可能会休眠，需要定期访问以保活。"
echo "  1) 使用作者内置保活服务（自动通过 API 添加定时访问任务）"
echo "  2) 自行解决（稍后手动设置 cron 或其他监控服务）"
read -p "请选择 [1]: " keep_alive_choice
keep_alive_choice=${keep_alive_choice:-1}

case "$keep_alive_choice" in
    1)
        add_visit_task() {
            # 调用第三方保活 API，添加项目 URL
            if curl -s -X POST "https://trans.ct8.pl/add-url" \
                -H "Content-Type: application/json" \
                -d "{\"url\":\"$PROJECT_URL\"}" >/dev/null; then
                log_ok "自动保活任务添加成功！服务将定期访问 ${PROJECT_URL}"
            else
                log_err "添加自动保活任务失败，请稍后重试或选择手动保活方式。"
            fi
        }
        add_visit_task
        ;;
    2)
        echo ""
        echo "您可以自行设置保活，例如："
        echo "  - 在 AlwaysData 计划任务中添加 cron 定时访问："
        echo "    */5 * * * * curl -s -o /dev/null ${PROJECT_URL}"
        echo "  - 使用外部监控服务（如 UptimeRobot、Cron-job.org 等）定期访问上述地址。"
        echo ""
        ;;
    *)
        log_warn "无效选项，默认不启用自动保活。请按选项 2 的方式自行处理。"
        ;;
esac

echo ""
echo "=========================================="
echo "  安装脚本执行完毕，祝您使用愉快！"
echo "=========================================="
