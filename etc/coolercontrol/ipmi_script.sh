#!/bin/bash

# ============================================
# IPMI 状态信息提取及风扇控制脚本
# 用途：提取服务器状态信息并支持风扇转速控制
# 版本：2.3
# ============================================

# ============================================
# 配置项（可根据需要修改）
# ============================================

# IPMI 连接配置
IPMI_HOST="192.168.0.110"
IPMI_USER="root"
IPMI_PASS="DELLR730"
IPMI_BASE="ipmitool -I lanplus -H ${IPMI_HOST} -U ${IPMI_USER} -P ${IPMI_PASS}"

# 风扇配置
FAN_COUNT=6                    # 风扇个数
FAN_SPEED_MIN=0                # 最小转速（十进制）
FAN_SPEED_MAX=100              # 最大转速（十进制）

# 目录配置（统一在 /tmp/ipmi 下）
BASE_DIR="/tmp/ipmi"
OUTPUT_DIR="${BASE_DIR}/metrics"
CTRL_DIR="${BASE_DIR}/ctrl"
LAST_DIR="${CTRL_DIR}/last"

# 日志配置
LOG_FILE="/tmp/ipmi/control.log"
LOG_LEVEL=1                    # 0: ERROR only, 1: INFO, 2: DEBUG

# 全局状态文件
AUTO_MODE_FLAG="${BASE_DIR}/.auto_mode"

# ============================================
# 全局变量
# ============================================

UPDATE_INTERVAL=30             # 默认更新间隔（秒）
RUNNING=true                   # 运行标志
CURRENT_MODE=""                # 当前模式：auto 或 manual

# ============================================
# 初始化函数
# ============================================

init_directories() {
    mkdir -p "$OUTPUT_DIR"
    mkdir -p "$CTRL_DIR"
    chmod 777 "$CTRL_DIR" 2>/dev/null || log_message ERROR "Failed to set permissions for $CTRL_DIR"
    mkdir -p "$LAST_DIR"
    log_message INFO "Directories created: $BASE_DIR"
}

log_message() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    case $level in
        ERROR)
            echo "[$timestamp] ERROR: $message" | tee -a "$LOG_FILE"
            ;;
        INFO)
            if [ $LOG_LEVEL -ge 1 ]; then
                echo "[$timestamp] INFO: $message" | tee -a "$LOG_FILE"
            fi
            ;;
        DEBUG)
            if [ $LOG_LEVEL -ge 2 ]; then
                echo "[$timestamp] DEBUG: $message" | tee -a "$LOG_FILE"
            fi
            ;;
    esac
}

# 获取当前模式
get_current_mode() {
    if [ -f "$AUTO_MODE_FLAG" ]; then
        echo "auto"
    else
        echo "manual"
    fi
}

# 设置当前模式
set_current_mode() {
    local mode=$1
    if [ "$mode" = "auto" ]; then
        touch "$AUTO_MODE_FLAG"
        CURRENT_MODE="auto"
        log_message DEBUG "Set mode flag to auto"
    else
        rm -f "$AUTO_MODE_FLAG"
        CURRENT_MODE="manual"
        log_message DEBUG "Set mode flag to manual"
    fi
}

# ============================================
# IPMI 操作函数
# ============================================

# 获取 IPMI 传感器数据
get_ipmi_data() {
    ${IPMI_BASE} sdr list 2>/dev/null
    if [ $? -ne 0 ]; then
        log_message ERROR "Failed to execute ipmitool sdr list"
        return 1
    fi
    return 0
}

# 十进制转十六进制（0-100 -> 0x00-0x64）
dec2hex() {
    local dec=$1
    # 限制范围 0-100
    if [ $dec -lt 0 ]; then
        dec=0
    elif [ $dec -gt 100 ]; then
        dec=100
    fi
    printf "0x%02x" "$dec"
}

# 设置风扇为自动模式
set_auto_mode() {
    # 检查当前是否已经是自动模式
    if [ "$CURRENT_MODE" = "auto" ]; then
        log_message DEBUG "Already in auto mode, skipping command"
        return 0
    fi

    log_message INFO "Setting fans to automatic mode..."
    local cmd="${IPMI_BASE} raw 0x30 0x30 0x01 0x01"
    if $cmd > /dev/null 2>&1; then
        log_message INFO "✓ Fans set to auto mode"
        set_current_mode "auto"
        # 清空 last 目录，表示不再手动控制
        rm -f "${LAST_DIR}"/*
        return 0
    else
        log_message ERROR "✗ Failed to set auto mode"
        return 1
    fi
}

# 设置风扇为手动模式
set_manual_mode() {
    # 检查当前是否已经是手动模式
    if [ "$CURRENT_MODE" = "manual" ]; then
        log_message DEBUG "Already in manual mode, skipping command"
        return 0
    fi

    log_message INFO "Setting fans to manual mode..."
    local cmd="${IPMI_BASE} raw 0x30 0x30 0x01 0x00"
    if $cmd > /dev/null 2>&1; then
        log_message INFO "✓ Fans set to manual mode"
        set_current_mode "manual"
        return 0
    else
        log_message ERROR "✗ Failed to set manual mode"
        return 1
    fi
}

# 设置单个风扇转速
set_fan_speed() {
    local fan_num=$1
    local speed_dec=$2      # 转速 0-100

    # 验证风扇编号
    if [ $fan_num -lt 1 ] || [ $fan_num -gt $FAN_COUNT ]; then
        log_message ERROR "Invalid fan number $fan_num (must be 1-$FAN_COUNT)"
        return 1
    fi

    # 验证转速值范围
    if [ $speed_dec -lt 0 ] || [ $speed_dec -gt 100 ]; then
        log_message ERROR "Invalid speed $speed_dec (must be 0-100)"
        return 1
    fi

    # 转换为十六进制
    local speed_hex=$(dec2hex $speed_dec)

    # 构建并执行命令
    local cmd="${IPMI_BASE} raw 0x30 0x30 0x02 0xff ${speed_hex}"
    log_message DEBUG "Setting Fan$fan_num speed: ${speed_dec}% (${speed_hex})"

    if $cmd > /dev/null 2>&1; then
        log_message DEBUG "✓ Fan$fan_num set successfully"
        return 0
    else
        log_message ERROR "✗ Failed to set Fan$fan_num"
        return 1
    fi
}

# ============================================
# 数据提取函数
# ============================================

# 提取数值并写入文件
write_metric() {
    local data="$1"
    local pattern="$2"
    local value_field="$3"
    local filename="$4"
    local filter_ok="$5"

    local line=$(echo "$data" | grep -i "^$pattern" | head -1)
    if [ -z "$line" ]; then
        return 1
    fi

    # 检查状态
    if echo "$line" | grep -q "| ns"; then
        return 1
    fi

    if [ "${filter_ok:-true}" = "true" ] && ! echo "$line" | grep -q "| ok"; then
        return 1
    fi

    # 提取数值
    local raw_value=$(echo "$line" | awk -F'|' "{print \$$value_field}" | xargs)
    local numeric=$(echo "$raw_value" | grep -oE '[-]?[0-9]+(\.[0-9]+)?' | head -1)

    if [ -n "$numeric" ]; then
        echo "$numeric" > "$OUTPUT_DIR/$filename"
        return 0
    fi
    return 1
}

# 提取所有状态信息
extract_status() {
    local data="$1"
    local i

    log_message DEBUG "Extracting status information..."

    # 提取风扇转速
    for i in $(seq 1 $FAN_COUNT); do
        write_metric "$data" "Fan$i" 2 "fan${i}_rpm" true
        if [ -f "$OUTPUT_DIR/fan${i}_rpm" ]; then
            local rpm=$(cat "$OUTPUT_DIR/fan${i}_rpm")
            log_message DEBUG "  Fan$i: ${rpm} RPM"
        fi
    done

    # 提取温度
    write_metric "$data" "Inlet Temp" 2 "inlet_temp_c" true
    write_metric "$data" "Exhaust Temp" 2 "exhaust_temp_c" true
    write_metric "$data" "Temp" 2 "temp_c" true

    # 提取使用率
    write_metric "$data" "CPU Usage" 2 "cpu_usage_percent" true
    write_metric "$data" "IO Usage" 2 "io_usage_percent" true
    write_metric "$data" "MEM Usage" 2 "mem_usage_percent" true
    write_metric "$data" "SYS Usage" 2 "sys_usage_percent" true

    # 提取电源信息
    write_metric "$data" "Pwr Consumption" 2 "power_consumption_watts" true
    write_metric "$data" "Current 2" 2 "current_amps" true
    write_metric "$data" "Voltage 2" 2 "voltage_volts" true

    log_message DEBUG "Status extraction completed"
}

# 创建单位映射文件
create_units_file() {
    cat > "$OUTPUT_DIR/units.txt" << EOF
# 单位映射文件
# 格式：指标名|单位
Fan|RPM
Temp|degrees_C
Power|Watts
Current|Amps
Voltage|Volts
Usage|percent
EOF
}

# ============================================
# 风扇控制函数
# ============================================

# 应用风扇控制（从控制文件读取）
apply_fan_control() {
    local changed=0
    local i
    local has_manual_request=false
    local has_auto_request=false

    # 首先检查所有控制文件的请求
    for i in $(seq 1 $FAN_COUNT); do
        local ctrl_file="${CTRL_DIR}/fan${i}"
        if [ -f "$ctrl_file" ]; then
            local target_speed=$(cat "$ctrl_file" 2>/dev/null | xargs)

            # 检查是否有任何自动模式请求
            if [ "$target_speed" = "-1" ]; then
                has_auto_request=true
            fi

            # 检查是否有手动控制请求（0-100范围）
            if [[ "$target_speed" =~ ^[0-9]+$ ]] && [ $target_speed -ge 0 ] && [ $target_speed -le 100 ]; then
                has_manual_request=true
            fi
        fi
    done

    # 优先处理自动模式请求（如果有任何一个风扇请求自动模式，整个系统切换到自动）
    if [ "$has_auto_request" = true ]; then
        log_message DEBUG "Auto mode requested, checking current state..."
        if [ "$CURRENT_MODE" != "auto" ]; then
            log_message INFO "Switching to auto mode due to control file request"
            set_auto_mode
            # 清空控制文件的可选：避免重复触发
            for i in $(seq 1 $FAN_COUNT); do
                [ -f "${CTRL_DIR}/fan${i}" ] && rm -f "${CTRL_DIR}/fan${i}"
            done
        else
            log_message DEBUG "Already in auto mode, no action needed"
        fi
        return 0
    fi

    # 如果没有自动请求，但有手动请求
    if [ "$has_manual_request" = true ]; then
        # 确保在手动模式
        if [ "$CURRENT_MODE" != "manual" ]; then
            set_manual_mode
            sleep 1
        fi

        # 处理每个风扇的手动控制
        for i in $(seq 1 $FAN_COUNT); do
            local ctrl_file="${CTRL_DIR}/fan${i}"
            local last_file="${LAST_DIR}/fan${i}"

            # 检查控制文件是否存在
            if [ ! -f "$ctrl_file" ]; then
                continue
            fi

            # 读取目标转速
            local target_speed=$(cat "$ctrl_file" 2>/dev/null | xargs)

            # 只处理数字范围（0-100），忽略自动请求（已经在上面处理）
            if [[ "$target_speed" =~ ^[0-9]+$ ]] && [ $target_speed -ge 0 ] && [ $target_speed -le 100 ]; then
                # 读取上次设置的转速
                local last_speed=""
                if [ -f "$last_file" ]; then
                    last_speed=$(cat "$last_file" 2>/dev/null | xargs)
                fi

                # 比较是否改变
                if [ "$target_speed" != "$last_speed" ]; then
                    log_message INFO "Fan$i speed changed from ${last_speed:-none} to ${target_speed}%"

                    if set_fan_speed $i $target_speed; then
                        # 保存当前设置到 last 目录
                        echo "$target_speed" > "$last_file"
                        changed=1
                    fi
                else
                    log_message DEBUG "Fan$i speed unchanged: ${target_speed}%"
                fi
            fi
        done
    else
        # 没有任何控制请求
        log_message DEBUG "No control requests found"
    fi

    if [ $changed -eq 0 ] && [ "$has_manual_request" = true ]; then
        log_message DEBUG "No fan speed changes detected"
    fi
}

# ============================================
# 主循环函数
# ============================================

main_loop() {
    local interval=$1

    log_message INFO "========================================="
    log_message INFO "IPMI Monitor Started"
    log_message INFO "  Fan count: $FAN_COUNT"
    log_message INFO "  Speed range: $FAN_SPEED_MIN-$FAN_SPEED_MAX"
    log_message INFO "  Update interval: ${interval} seconds"
    log_message INFO "  Base directory: $BASE_DIR"
    log_message INFO "  Output directory: $OUTPUT_DIR"
    log_message INFO "  Control directory: $CTRL_DIR"
    log_message INFO "========================================="

    while $RUNNING; do
        local loop_start=$(date +%s)

        # 获取 IPMI 数据
        local ipmi_data=$(get_ipmi_data)
        if [ $? -eq 0 ] && [ -n "$ipmi_data" ]; then
            # 提取状态信息
            extract_status "$ipmi_data"

            # 应用风扇控制
            apply_fan_control
        else
            log_message ERROR "Failed to get IPMI data"
        fi

        # 计算需要等待的时间
        local loop_end=$(date +%s)
        local elapsed=$((loop_end - loop_start))
        local sleep_time=$((interval - elapsed))

        if [ $sleep_time -gt 0 ]; then
            log_message DEBUG "Sleeping for ${sleep_time} seconds"
            sleep $sleep_time
        fi
    done
}

# ============================================
# 信号处理函数
# ============================================

cleanup() {
    log_message INFO "Received shutdown signal, cleaning up..."
    RUNNING=false
    exit 0
}

setup_signal_handlers() {
    trap cleanup SIGTERM SIGINT SIGHUP
}

# ============================================
# 帮助信息
# ============================================

show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

IPMI Server Monitor and Fan Control Script

Directories:
    Base directory: /tmp/ipmi
    Metrics:        /tmp/ipmi/metrics
    Control:        /tmp/ipmi/ctrl
    Last applied:   /tmp/ipmi/ctrl/last

Options:
    -i, --interval SECONDS    Update interval in seconds (default: 30)
    -c, --count NUM          Number of fans (default: 6)
    -h, --help               Show this help message

Control Files:
    /tmp/ipmi/ctrl/fan1 - /tmp/ipmi/ctrl/fanN    Write target speed (0-100 or -1 for auto)

Important Notes:
    - Any fan control file with value "-1" will switch the ENTIRE system to auto mode
    - To manually control individual fans, ensure NO fan has "-1" in its control file
    - The script remembers current mode and won't send duplicate commands

Examples:
    $0                           # Run with default settings (30s interval)
    $0 -i 10                     # Run with 10 second interval
    $0 --interval 5 --count 8    # Run with 5s interval and 8 fans
    $0 -i 60 &                   # Run in background with 60s interval

To control fan speed:
    # Switch to auto mode
    echo "-1" > /tmp/ipmi/ctrl/fan1

    # Manual control (all fans)
    echo "50" > /tmp/ipmi/ctrl/fan1
    echo "60" > /tmp/ipmi/ctrl/fan2
    echo "70" > /tmp/ipmi/ctrl/fan3

    # Remove control files to stop applying
    rm /tmp/ipmi/ctrl/fan*

To view metrics:
    cat /tmp/ipmi/metrics/fan1_rpm
    cat /tmp/ipmi/metrics/inlet_temp_c

To stop the script:
    killall ipmi_script.sh
    or press Ctrl+C

EOF
}

# ============================================
# 命令行参数解析
# ============================================

parse_arguments() {
    while [ $# -gt 0 ]; do
        case $1 in
            -i|--interval)
                UPDATE_INTERVAL="$2"
                shift 2
                ;;
            -c|--count)
                FAN_COUNT="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # 验证参数
    if ! [[ "$UPDATE_INTERVAL" =~ ^[0-9]+$ ]] || [ $UPDATE_INTERVAL -lt 1 ]; then
        echo "ERROR: Invalid interval: $UPDATE_INTERVAL (must be >= 1)"
        exit 1
    fi

    if ! [[ "$FAN_COUNT" =~ ^[0-9]+$ ]] || [ $FAN_COUNT -lt 1 ]; then
        echo "ERROR: Invalid fan count: $FAN_COUNT (must be >= 1)"
        exit 1
    fi
}

# ============================================
# 主程序入口
# ============================================

main() {
    # 解析命令行参数
    parse_arguments "$@"

    # 初始化
    init_directories
    create_units_file

    # 读取当前模式状态
    CURRENT_MODE=$(get_current_mode)
    log_message INFO "Current mode: $CURRENT_MODE"

    setup_signal_handlers

    # 启动主循环
    main_loop $UPDATE_INTERVAL
}

# 运行主程序
main "$@"
