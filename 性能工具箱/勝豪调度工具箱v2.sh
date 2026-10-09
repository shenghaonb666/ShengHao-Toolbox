#!/system/bin/sh
# =====================================================
#          Android 性能调度优化工具箱 v2.0
#          作者：勝豪
#          Q群：1022873156
# =====================================================
# 更新：增加设备自动识别，生成专属调优建议
# 环境：需要 root（su）
# 注意：部分参数因内核/机型不同可能不存在，会自动跳过
# =====================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROFILE_DIR="$SCRIPT_DIR/profiles"

# 全局设备信息变量
DEV_BRAND="未知"
DEV_MODEL="未知"
SOC_PLATFORM="未知"
DEV_HARDWARE="未知"
SOC_VENDOR="通用"
CPU_TOPOLOGY="未知"
CPU_MAX_FREQ="0"
HAS_SUGGEST="0"

pause() {
  printf "\n按回车返回..."
  read dummy
}

confirm_yes() {
  printf "⚠ %s\n确认请输入 YES： " "$1"
  read a
  case "$a" in YES|yes) return 0 ;; *) return 1 ;; esac
}

require_root() {
  if [ "$(id -u 2>/dev/null)" != "0" ]; then
    echo "✗ 需要 root 权限"
    return 1
  fi
  return 0
}

wr() {
  if [ -e "$1" ]; then
    echo "$2" > "$1" 2>/dev/null && return 0
  fi
  return 1
}

cpu_list() { ls -d /sys/devices/system/cpu/cpu[0-9]* 2>/dev/null; }

# =====================================================
#                 设备识别与建议模块
# =====================================================

detect_device() {
  DEV_BRAND=$(getprop ro.product.brand)
  DEV_MODEL=$(getprop ro.product.model)
  SOC_PLATFORM=$(getprop ro.board.platform)
  DEV_HARDWARE=$(getprop ro.hardware)
  ANDROID_VER=$(getprop ro.build.version.release)

  [ -z "$DEV_BRAND" ] && DEV_BRAND="未知"
  [ -z "$DEV_MODEL" ] && DEV_MODEL="未知"
  [ -z "$SOC_PLATFORM" ] && SOC_PLATFORM=$(getprop ro.hardware)
  [ -z "$SOC_PLATFORM" ] && SOC_PLATFORM="未知"

  # 判断厂商
  case "$SOC_PLATFORM" in
    sm*|msm*|kona*|lahaina*|waipio*|kalama*|crow*|pineapple*|qcom*)
      SOC_VENDOR="Qualcomm" ;;
    mt*|dimensity*|helio*)
      SOC_VENDOR="MediaTek" ;;
    kirin*|hi3*|hi6*)
      SOC_VENDOR="HiSilicon" ;;
    exynos*|universal*)
      SOC_VENDOR="Samsung" ;;
    gs*|zuma*|cloudripper*)
      SOC_VENDOR="Google" ;;
    *)
      case "$DEV_HARDWARE" in
        qcom) SOC_VENDOR="Qualcomm" ;;
        mtk)  SOC_VENDOR="MediaTek" ;;
        kirin) SOC_VENDOR="HiSilicon" ;;
        exynos) SOC_VENDOR="Samsung" ;;
      esac
      ;;
  esac

  # 获取最大主频
  local max_freq=$(cat /sys/devices/system/cpu/cpu7/cpufreq/cpuinfo_max_freq 2>/dev/null)
  [ -z "$max_freq" ] && max_freq=$(cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq 2>/dev/null)
  if [ -n "$max_freq" ]; then
    CPU_MAX_FREQ="$((max_freq / 1000))MHz"
  fi

  # 简单判断核心架构
  local cores=$(grep -c '^processor' /proc/cpuinfo 2>/dev/null)
  if [ "$cores" = "8" ] && [ -e /sys/devices/system/cpu/cpu7 ]; then
    local cpu7_max=$(cat /sys/devices/system/cpu/cpu7/cpufreq/cpuinfo_max_freq 2>/dev/null)
    local cpu0_max=$(cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq 2>/dev/null)
    if [ -n "$cpu7_max" ] && [ "$cpu7_max" -gt "$cpu0_max" ]; then
      CPU_TOPOLOGY="1+3+4 (超大核+大核+小核)"
    else
      CPU_TOPOLOGY="4+4 (大小核)"
    fi
  else
    CPU_TOPOLOGY="共 ${cores} 核"
  fi

  HAS_SUGGEST="1"
}

show_device_info() {
  echo "========================================"
  echo "            设备识别信息"
  echo "========================================"
  echo " 品牌     : $DEV_BRAND"
  echo " 型号     : $DEV_MODEL"
  echo " 平台代号 : $SOC_PLATFORM"
  echo " 处理器厂商: $SOC_VENDOR"
  echo " 核心架构 : $CPU_TOPOLOGY"
  echo " 最高主频 : $CPU_MAX_FREQ"
  echo " Android  : $ANDROID_VER"
  echo "========================================"
}

show_suggestions() {
  echo "========================================"
  echo "            专属调优建议"
  echo "========================================"
  
  if [ "$HAS_SUGGEST" != "1" ]; then
    echo "· 未识别到具体设备，以下是通用建议："
  else
    show_device_info
  fi

  echo ""
  echo "【基于硬件的分析】"
  case "$SOC_VENDOR" in
    Qualcomm)
      echo " 检测到高通骁龙平台，GPU 通常为 Adreno。"
      echo " 调度建议：日常使用 schedutil 或 walt，游戏可切 performance。"
      echo " 温控建议：高通旗舰功耗较高，建议保留温控（菜单 6-2 可关闭，但需谨慎）。"
      echo " GPU 建议：可使用菜单 2-4 进行 Adreno 一键调优。"
      ;;
    MediaTek)
      echo " 检测到联发科天玑/Helio平台，GPU 通常为 Mali。"
      echo " 调度建议：联发科对 schedutil 适配较好，建议保留默认调度。"
      echo " 注意：联发科部分节点限制较多，部分参数可能无法写入。"
      echo " GPU 建议：可通过 devfreq 节点调节 GPU 频率（菜单 2-2/2-3）。"
      ;;
    HiSilicon)
      echo " 检测到华为麒麟平台。"
      echo " 调度建议：华为系统调度机制封闭，建议保持默认 schedutil。"
      echo " 注意：部分内核节点被锁定，切勿强改。"
      ;;
    Samsung)
      echo " 检测到三星 Exynos 平台。"
      echo " 调度建议：建议使用 schedutil 或 interactive。"
      echo " 注意：Exynos 对温控较敏感，请谨慎调节温控与充电电流。"
      ;;
    Google)
      echo " 检测到 Google Tensor 平台。"
      echo " 调度建议：Tensor 功耗较高，强烈建议使用均衡模式。"
      echo " 注意：温控节点敏感，不建议关闭温控。"
      ;;
    *)
      echo " 暂未匹配到该处理器厂商的专属建议。"
      ;;
  esac

  echo ""
  echo "【根据当前 CPU 架构 ($CPU_TOPOLOGY) 的建议】"
  case "$CPU_TOPOLOGY" in
    *1+3+4*)
      echo " 该架构包含超大核（如 cpu7，$CPU_MAX_FREQ）。"
      echo " ⚠ 不要将 cpu7 单独设置为 performance，极易触发过热降频。"
      echo " 建议：cpu0-6 设为 schedutil 或 walt，cpu7 保持 schedutil。"
      echo " 游戏模式：可尝试将 cpu7 设为 performance，配合散热背夹。"
      ;;
    *4+4*)
      echo " 大小核架构，调度相对简单。"
      echo " 建议：全核 schedutil，或大核 performance、小核 powersave。"
      ;;
    *)
      echo " 建议使用 schedutil 作为全核调度器。"
      ;;
  esac

  echo ""
  echo "【推荐操作顺序】"
  echo " 1. 先进入菜单 4 -> 1，查看当前内存与 VM 状态"
  echo " 2. 进入菜单 3 -> 3，执行一键 I/O 优化"
  echo " 3. 进入菜单 5 -> 2，执行一键网络优化"
  echo " 4. 进入菜单 8 -> 2，进行熵池优化"
  echo " 5. 想打游戏时，回主菜单使用 9 -> 4 游戏模式"
  echo ""
  echo "========================================"
}

# =====================================================
#                     CPU 模块 (略，与原版一致)
# =====================================================

cpu_show() {
  echo "=========== CPU 当前状态 ==========="
  for c in $(cpu_list); do
    n=$(basename "$c")
    cur=$(cat "$c/cpufreq/scaling_cur_freq" 2>/dev/null)
    min=$(cat "$c/cpufreq/scaling_min_freq" 2>/dev/null)
    max=$(cat "$c/cpufreq/scaling_max_freq" 2>/dev/null)
    gov=$(cat "$c/cpufreq/scaling_governor" 2>/dev/null)
    [ -n "$cur" ] && cur="$((cur / 1000))MHz"
    [ -n "$min" ] && min="$((min / 1000))MHz"
    [ -n "$max" ] && max="$((max / 1000))MHz"
    echo "  $n  当前:$cur  最小:$min  最大:$max  调度:$gov"
  done
  echo ""
  echo "在线核心: $(cat /sys/devices/system/cpu/online 2>/dev/null)"
  echo "可用调度:"
  cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors 2>/dev/null
}

cpu_set_governor() {
  echo "可选调度器："
  cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors 2>/dev/null
  printf "\n请输入要设置的调度器："
  read g
  [ -z "$g" ] && return 1
  for c in $(cpu_list); do
    wr "$c/cpufreq/scaling_governor" "$g"
  done
  echo "✓ 已尝试设置 governor = $g"
}

cpu_set_freq() {
  printf "请输入频率值（kHz，如 1804800）："
  read f
  [ -z "$f" ] && return 1
  printf "1) 设为最大频率  2) 设为最小频率："
  read m
  for c in $(cpu_list); do
    case "$m" in
      1) wr "$c/cpufreq/scaling_max_freq" "$f" ;;
      2) wr "$c/cpufreq/scaling_min_freq" "$f" ;;
    esac
  done
  echo "✓ 已设置"
}

cpu_online_all() {
  for c in $(cpu_list); do
    n=$(basename "$c")
    case "$n" in cpu0) continue ;; esac
    echo 1 > "$c/online" 2>/dev/null
  done
  echo "✓ 已尝试全部上线"
}

cpu_offline_big() {
  echo "当前核心："
  for c in $(cpu_list); do
    n=$(basename "$c")
    max=$(cat "$c/cpufreq/cpuinfo_max_freq" 2>/dev/null)
    [ -n "$max" ] && echo "  $n  max=$((max / 1000))MHz"
  done
  printf "输入要下线的核心（如 cpu7）："
  read c
  [ -z "$c" ] && return 1
  echo 0 > "/sys/devices/system/cpu/$c/online" 2>/dev/null \
    && echo "✓ $c 已下线" || echo "✗ 无法下线"
}

cpu_tune_governor() {
  printf "请输入调度器名称（schedutil/interactive/ondemand）："
  read g
  [ -z "$g" ] && return 1
  for c in $(cpu_list); do
    d="$c/cpufreq/$g"
    [ -d "$d" ] || continue
    case "$g" in
      interactive|ondemand)
        wr "$d/above_hispeed_delay" "20000"
        wr "$d/boost" "1"
        wr "$d/boostpulse_duration" "80000"
        wr "$d/go_hispeed_load" "90"
        wr "$d/hispeed_freq" "$(cat $c/cpufreq/cpuinfo_max_freq 2>/dev/null)"
        wr "$d/io_is_busy" "1"
        wr "$d/min_sample_time" "20000"
        wr "$d/target_loads" "90 1000000:95"
        wr "$d/timer_rate" "20000"
        wr "$d/timer_slack" "20000"
        ;;
      schedutil)
        wr "$d/up_rate_limit_us" "1000"
        wr "$d/down_rate_limit_us" "10000"
        wr "$d/iowait_boost_enable" "1"
        ;;
    esac
  done
  echo "✓ 已应用 $g 参数"
}

# =====================================================
#                     GPU / I/O / 内存 / 网络 / 电源 模块 (略，沿用原版)
# =====================================================

gpu_show() {
  echo "=========== GPU 信息 ==========="
  for d in /sys/class/kgsl/kgsl-3d0 /sys/class/devfreq/*gpu* /sys/kernel/gpu; do
    [ -d "$d" ] || continue
    echo "路径：$d"
    for f in cur_freq max_freq min_freq governor available_governors max_gpuclk gpu_available_frequencies devfreq/cur_freq devfreq/min_freq devfreq/max_freq devfreq/governor; do
      [ -r "$d/$f" ] && echo "  $f = $(cat $d/$f 2>/dev/null)"
    done
    echo ""
  done
}

gpu_set_governor() {
  printf "请输入 GPU 调度器（如 msm-adreno-tz / simple_ondemand / performance）："
  read g
  [ -z "$g" ] && return 1
  found=0
  for d in /sys/class/kgsl/kgsl-3d0 /sys/class/devfreq/*gpu* /sys/kernel/gpu; do
    [ -d "$d" ] || continue
    [ -e "$d/devfreq/governor" ] && wr "$d/devfreq/governor" "$g" && found=1
    [ -e "$d/governor" ] && wr "$d/governor" "$g" && found=1
  done
  [ "$found" = "1" ] && echo "✓ 已设置" || echo "✗ 未找到 GPU 节点"
}

gpu_set_freq() {
  printf "请输入 GPU 频率（Hz，如 585000000）："
  read f
  [ -z "$f" ] && return 1
  printf "1) 最小  2) 最大  3) 固定："
  read m
  for d in /sys/class/kgsl/kgsl-3d0 /sys/class/devfreq/*gpu*; do
    [ -d "$d" ] || continue
    case "$m" in
      1) wr "$d/devfreq/min_freq" "$f"; wr "$d/min_freq" "$f" ;;
      2) wr "$d/devfreq/max_freq" "$f"; wr "$d/max_freq" "$f" ;;
      3) wr "$d/devfreq/min_freq" "$f"; wr "$d/devfreq/max_freq" "$f" ;;
    esac
  done
  echo "✓ 已设置"
}

gpu_tune_adreno() {
  printf "请输入 GPU 调度器（默认 msm-adreno-tz）："
  read g
  [ -z "$g" ] && g="msm-adreno-tz"
  d=/sys/class/kgsl/kgsl-3d0
  [ -d "$d" ] || { echo "✗ 非 Adreno / 无节点"; return 1; }
  wr "$d/devfreq/governor" "$g"
  wr "$d/idle_timer" "80"
  wr "$d/thermal_pwrlevel" "0"
  wr "$d/max_pwrlevel" "0"
  wr "$d/min_pwrlevel" "5"
  wr "$d/force_clk_on" "0"
  wr "$d/force_bus_on" "0"
  wr "$d/force_rail_on" "0"
  echo "✓ Adreno 参数已应用"
}

io_show() {
  echo "=========== I/O 状态 ==========="
  for q in /sys/block/*/queue; do
    b=$(basename $(dirname "$q"))
    echo "$b:"
    for f in scheduler nr_requests read_ahead_kb rotational iostats rq_affinity nomerges add_random; do
      [ -r "$q/$f" ] && echo "  $f = $(cat $q/$f 2>/dev/null)"
    done
  done
}

io_set_sched() {
  printf "请输入调度器（cfq/deadline/noop/bfq/kyber/mq-deadline/none）："
  read s
  [ -z "$s" ] && return 1
  for q in /sys/block/*/queue/scheduler; do
    [ -e "$q" ] || continue
    echo "$s" > "$q" 2>/dev/null
  done
  echo "✓ 已设置"
}

io_tune() {
  for q in /sys/block/*/queue; do
    wr "$q/read_ahead_kb" "2048"
    wr "$q/nr_requests" "128"
    wr "$q/rq_affinity" "2"
    wr "$q/iostats" "0"
    wr "$q/nomerges" "0"
    wr "$q/add_random" "0"
    wr "$q/rotational" "0"
  done
  echo "✓ I/O 参数已优化"
}

mem_show() {
  echo "=========== 内存 / VM ==========="
  for f in /proc/sys/vm/swappiness /proc/sys/vm/dirty_ratio /proc/sys/vm/dirty_background_ratio /proc/sys/vm/vfs_cache_pressure /proc/sys/vm/min_free_kbytes /proc/sys/vm/overcommit_memory /proc/sys/vm/extra_free_kbytes /proc/sys/vm/stat_interval; do
    [ -r "$f" ] && echo "  $(basename $f) = $(cat $f)"
  done
  echo ""
  echo "  ZRAM:"
  if [ -r /proc/swaps ]; then cat /proc/swaps; fi
  have_cmd() { command -v "$1" >/dev/null 2>&1; }
  have_cmd zramctl && zramctl 2>/dev/null
}

mem_tune() {
  wr /proc/sys/vm/swappiness "60"
  wr /proc/sys/vm/dirty_ratio "20"
  wr /proc/sys/vm/dirty_background_ratio "5"
  wr /proc/sys/vm/vfs_cache_pressure "100"
  wr /proc/sys/vm/overcommit_memory "0"
  wr /proc/sys/vm/overcommit_ratio "50"
  wr /proc/sys/vm/extra_free_kbytes "12000"
  echo "✓ VM 参数已优化"
}

mem_aggressive() {
  wr /proc/sys/vm/swappiness "100"
  wr /proc/sys/vm/dirty_ratio "15"
  wr /proc/sys/vm/dirty_background_ratio "3"
  wr /proc/sys/vm/vfs_cache_pressure "200"
  echo "✓ 激进内存策略已应用"
}

mem_drop_caches() {
  confirm_yes "释放 pagecache/dentries/inodes ？" || return 1
  sync
  wr /proc/sys/vm/drop_caches "3"
  echo "✓ 已释放"
}

mem_compact() {
  if [ -w /proc/sys/vm/compact_memory ]; then
    echo 1 > /proc/sys/vm/compact_memory 2>/dev/null && echo "✓ 已触发内存压缩"
  else
    echo "✗ 内核不支持 compact_memory"
  fi
}

zram_show() {
  echo "=========== ZRAM ==========="
  for z in /sys/block/zram*; do
    [ -d "$z" ] || continue
    echo "$(basename $z):"
    for f in disksize comp_algorithm mem_used_total; do
      [ -r "$z/$f" ] && echo "  $f = $(cat "$z/$f" 2>/dev/null)"
    done
  done
}

zram_set_algorithm() {
  printf "请输入压缩算法（lz4 / lzo / zstd / lz4hc）："
  read a
  [ -z "$a" ] && return 1
  for z in /sys/block/zram*; do
    [ -d "$z" ] || continue
    echo "$a" > "$z/comp_algorithm" 2>/dev/null
  done
  echo "✓ 已尝试设置"
}

net_show() {
  echo "=========== TCP / 网络 ==========="
  for f in /proc/sys/net/ipv4/tcp_congestion_control /proc/sys/net/ipv4/tcp_low_latency /proc/sys/net/ipv4/tcp_timestamps /proc/sys/net/ipv4/tcp_sack /proc/sys/net/ipv4/tcp_window_scaling /proc/sys/net/ipv4/tcp_fastopen /proc/sys/net/ipv4/tcp_ecn /proc/sys/net/ipv4/tcp_syncookies /proc/sys/net/ipv4/tcp_tw_reuse /proc/sys/net/ipv4/tcp_fin_timeout /proc/sys/net/ipv4/tcp_keepalive_time /proc/sys/net/ipv4/ip_forward /proc/sys/net/core/rmem_max /proc/sys/net/core/wmem_max /proc/sys/net/core/netdev_max_backlog; do
    [ -r "$f" ] && echo "  $(basename $f) = $(cat $f)"
  done
  echo ""
  echo "可用拥塞算法:"
  cat /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null
}

net_tune() {
  wr /proc/sys/net/ipv4/tcp_congestion_control "bbr"
  wr /proc/sys/net/ipv4/tcp_low_latency "1"
  wr /proc/sys/net/ipv4/tcp_timestamps "0"
  wr /proc/sys/net/ipv4/tcp_sack "1"
  wr /proc/sys/net/ipv4/tcp_window_scaling "1"
  wr /proc/sys/net/ipv4/tcp_fastopen "3"
  wr /proc/sys/net/ipv4/tcp_ecn "0"
  wr /proc/sys/net/ipv4/tcp_syncookies "1"
  wr /proc/sys/net/ipv4/tcp_tw_reuse "1"
  wr /proc/sys/net/ipv4/tcp_fin_timeout "30"
  wr /proc/sys/net/ipv4/tcp_keepalive_time "600"
  wr /proc/sys/net/core/rmem_max "262144"
  wr /proc/sys/net/core/wmem_max "262144"
  wr /proc/sys/net/core/netdev_max_backlog "3000"
  echo "✓ 网络参数已优化"
}

net_set_congestion() {
  echo "可用:"
  cat /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null
  printf "\n请输入："
  read c
  [ -z "$c" ] && return 1
  wr /proc/sys/net/ipv4/tcp_congestion_control "$c" && echo "✓ 已设置"
}

net_dns_set() {
  printf "请输入 DNS（如 1.1.1.1,8.8.8.8）："
  read d
  [ -z "$d" ] && return 1
  setprop net.dns1 "${d%%,*}"
  setprop net.dns2 "${d##*,}"
  echo "✓ 已尝试设置"
}

pwr_show() {
  echo "=========== 电源 / 温控 ==========="
  echo "Power supply:"
  for p in /sys/class/power_supply/*; do
    [ -d "$p" ] || continue
    echo "  $(basename $p):"
    for f in capacity status health temp current_now voltage_now online; do
      [ -r "$p/$f" ] && echo "    $f = $(cat "$p/$f")"
    done
  done
  echo ""
  echo "温控 zone:"
  for z in /sys/class/thermal/thermal_zone*; do
    [ -r "$z/temp" ] || continue
    t=$(cat "$z/temp")
    n=$(cat "$z/type" 2>/dev/null)
    echo "  $n = $((t / 1000))°C"
  done
}

pwr_toggle_thermal() {
  printf "1) 关闭温控  2) 开启温控："
  read m
  case "$m" in
    1)
      confirm_yes "关闭温控可能导致过热，继续？" || return 1
      for z in /sys/class/thermal/thermal_zone*; do
        [ -e "$z/mode" ] && echo "disabled" > "$z/mode" 2>/dev/null
      done
      echo "✓ 已尝试关闭"
      ;;
    2)
      for z in /sys/class/thermal/thermal_zone*; do
        [ -e "$z/mode" ] && echo "enabled" > "$z/mode" 2>/dev/null
      done
      echo "✓ 已开启"
      ;;
  esac
}

pwr_set_charge_limit() {
  printf "请输入充电电流上限（μA，如 3000000）："
  read v
  [ -z "$v" ] && return 1
  found=0
  for p in /sys/class/power_supply/*; do
    [ -e "$p/constant_charge_current_max" ] && wr "$p/constant_charge_current_max" "$v" && found=1
    [ -e "$p/input_current_limit" ] && wr "$p/input_current_limit" "$v" && found=1
  done
  [ "$found" = "1" ] && echo "✓ 已设置" || echo "✗ 节点不存在"
}

disp_show() {
  echo "=========== 显示 ==========="
  echo "分辨率: $(wm size 2>/dev/null)"
  echo "密度  : $(wm density 2>/dev/null)"
  echo "刷新率:"
  for f in /sys/class/drm/*/modes /sys/class/graphics/fb0/modes /sys/class/display/mode /sys/devices/platform/*/refresh_rate; do
    [ -r "$f" ] && echo "  $f = $(cat "$f" 2>/dev/null)"
  done
  dumpsys SurfaceFlinger 2>/dev/null | grep -E 'refresh|FPS' | head -5
}

disp_set_refresh() {
  printf "请输入刷新率（Hz，如 90/120）："
  read hz
  [ -z "$hz" ] && return 1
  found=0
  for f in /sys/class/graphics/fb0/refresh_rate /sys/devices/platform/*/refresh_rate /sys/class/display/refresh_rate; do
    [ -e "$f" ] && wr "$f" "$hz" && found=1
  done
  if [ "$found" = "0" ]; then
    have_cmd service && service call SurfaceFlinger 1035 i32 "$hz" >/dev/null 2>&1 && found=1
  fi
  [ "$found" = "1" ] && echo "✓ 已尝试设置 ${hz}Hz" || echo "✗ 未找到节点"
}

disp_anim_off() {
  settings put global window_animation_scale 0.5
  settings put global transition_animation_scale 0.5
  settings put global animator_duration_scale 0.5
  echo "✓ 动画已调为 0.5x"
}

disp_anim_default() {
  settings put global window_animation_scale 1
  settings put global transition_animation_scale 1
  settings put global animator_duration_scale 1
  echo "✓ 动画已恢复 1x"
}

touch_set_sample() {
  printf "请输入触控采样率（部分机型支持）："
  read v
  [ -z "$v" ] && return 1
  found=0
  for f in /sys/class/touch/*/sample_rate /sys/class/touchscreen/*/sampling_rate; do
    [ -e "$f" ] && wr "$f" "$v" && found=1
  done
  [ "$found" = "1" ] && echo "✓ 已设置" || echo "✗ 节点不存在"
}

touch_set_sensitivity() {
  found=0
  for f in /sys/class/touch/*/sensitivity; do
    [ -e "$f" ] && wr "$f" "1" && found=1
  done
  [ "$found" = "1" ] && echo "✓ 已设置高灵敏度" || echo "✗ 不支持"
}

kernel_show() {
  echo "=========== 内核参数 ==========="
  for f in /proc/sys/kernel/random/read_wakeup_threshold /proc/sys/kernel/random/write_wakeup_threshold /proc/sys/kernel/sched_latency_ns /proc/sys/kernel/sched_min_granularity_ns /proc/sys/kernel/sched_wakeup_granularity_ns /proc/sys/kernel/panic /proc/sys/kernel/panic_on_oops /proc/sys/kernel/printk; do
    [ -r "$f" ] && echo "  $(basename $f) = $(cat $f)"
  done
  echo ""
  echo "熵池: $(cat /proc/sys/kernel/random/entropy_avail 2>/dev/null)"
}

kernel_entropy_boost() {
  wr /proc/sys/kernel/random/read_wakeup_threshold "128"
  wr /proc/sys/kernel/random/write_wakeup_threshold "256"
  echo "✓ 熵池阈值已调"
}

kernel_sched_tune() {
  wr /proc/sys/kernel/sched_latency_ns "10000000"
  wr /proc/sys/kernel/sched_min_granularity_ns "1000000"
  wr /proc/sys/kernel/sched_wakeup_granularity_ns "2000000"
  echo "✓ 调度延迟参数已优化"
}

kernel_panic_off() {
  wr /proc/sys/kernel/panic "0"
  wr /proc/sys/kernel/panic_on_oops "0"
  echo "✓ 崩溃重启已关闭"
}

sys_disable_anim() {
  settings put global window_animation_scale 0
  settings put global transition_animation_scale 0
  settings put global animator_duration_scale 0
  echo "✓ 动画已完全关闭"
}

sys_bg_limit() {
  printf "请输入后台进程数（0=默认，1~4 为激进）："
  read n
  [ -z "$n" ] && return 1
  settings put global background_process_limit "$n" 2>/dev/null
  echo "✓ 已设置（可能需要重启生效）"
}

sys_doze_off() {
  dumpsys deviceidle disable 2>/dev/null
  echo "✓ 已尝试关闭 Doze"
}

sys_doze_on() {
  dumpsys deviceidle enable 2>/dev/null
  echo "✓ 已尝试启用 Doze"
}

sys_selinux() {
  printf "1) Permissive  2) Enforcing  3) 查看当前："
  read m
  case "$m" in
    1) setenforce 0 && echo "✓ Permissive" ;;
    2) setenforce 1 && echo "✓ Enforcing" ;;
    3) getenforce ;;
  esac
}

sys_force_gpu_render() {
  settings put global force_gpu_rendering 1 2>/dev/null
  echo "✓ 已强制 GPU 渲染"
}

sys_fstrim() {
  confirm_yes "对 /data /cache 执行 fstrim ？" || return 1
  have_cmd() { command -v "$1" >/dev/null 2>&1; }
  have_cmd fstrim || { echo "✗ 无 fstrim"; return 1; }
  for m in /data /cache /system; do
    [ -d "$m" ] && fstrim -v "$m" 2>/dev/null
  done
  echo "✓ 完成"
}

# 一键模式
mode_performance() {
  echo ">>> 应用性能模式"
  for c in $(cpu_list); do
    av=$(cat "$c/cpufreq/scaling_available_governors" 2>/dev/null)
    for g in performance schedutil interactive ondemand; do
      case "$av" in *"$g"*) wr "$c/cpufreq/scaling_governor" "$g"; break ;; esac
    done
  done
  io_tune
  mem_tune
  net_tune
  kernel_entropy_boost
  settings put global window_animation_scale 0.5
  settings put global transition_animation_scale 0.5
  settings put global animator_duration_scale 0.5
  echo "✓ 性能模式已应用（重启后恢复）"
}

mode_balanced() {
  echo ">>> 应用均衡模式"
  for c in $(cpu_list); do
    av=$(cat "$c/cpufreq/scaling_available_governors" 2>/dev/null)
    for g in schedutil interactive ondemand conservative; do
      case "$av" in *"$g"*) wr "$c/cpufreq/scaling_governor" "$g"; break ;; esac
    done
  done
  mem_tune
  echo "✓ 均衡模式已应用"
}

mode_power_save() {
  echo ">>> 应用省电模式"
  for c in $(cpu_list); do
    av=$(cat "$c/cpufreq/scaling_available_governors" 2>/dev/null)
    for g in powersave conservative; do
      case "$av" in *"$g"*) wr "$c/cpufreq/scaling_governor" "$g"; break ;; esac
    done
  done
  wr /proc/sys/vm/swappiness "100"
  settings put global low_power 1 2>/dev/null
  echo "✓ 省电模式已应用"
}

mode_game() {
  echo ">>> 应用游戏模式"
  for c in $(cpu_list); do
    av=$(cat "$c/cpufreq/scaling_available_governors" 2>/dev/null)
    for g in performance schedutil interactive ondemand; do
      case "$av" in *"$g"*) wr "$c/cpufreq/scaling_governor" "$g"; break ;; esac
    done
  done
  gpu_tune_adreno
  io_tune
  net_tune
  settings put global window_animation_scale 0
  settings put global transition_animation_scale 0
  settings put global animator_duration_scale 0
  settings put global background_process_limit 1 2>/dev/null
  echo "✓ 游戏模式已应用"
}

save_profile() {
  mkdir -p "$PROFILE_DIR"
  printf "请输入配置名："
  read n
  [ -z "$n" ] && return 1
  f="$PROFILE_DIR/$n.sh"
  {
    echo "#!/system/bin/sh"
    echo "# 由勝豪工具箱生成 $(date)"
    echo "echo '恢复配置：$n'"
    for c in $(cpu_list); do
      g=$(cat "$c/cpufreq/scaling_governor" 2>/dev/null)
      ma=$(cat "$c/cpufreq/scaling_max_freq" 2>/dev/null)
      mi=$(cat "$c/cpufreq/scaling_min_freq" 2>/dev/null)
      [ -n "$g" ] && echo "echo $g > $c/cpufreq/scaling_governor"
      [ -n "$ma" ] && echo "echo $ma > $c/cpufreq/scaling_max_freq"
      [ -n "$mi" ] && echo "echo $mi > $c/cpufreq/scaling_min_freq"
    done
    for f in swappiness dirty_ratio dirty_background_ratio vfs_cache_pressure; do
      v=$(cat /proc/sys/vm/$f 2>/dev/null)
      [ -n "$v" ] && echo "echo $v > /proc/sys/vm/$f"
    done
    for q in /sys/block/*/queue; do
      s=$(cat "$q/scheduler" 2>/dev/null | sed 's/\[//;s/\]//')
      [ -n "$s" ] && echo "echo $s > $q/scheduler"
      ra=$(cat "$q/read_ahead_kb" 2>/dev/null)
      [ -n "$ra" ] && echo "echo $ra > $q/read_ahead_kb"
    done
  } > "$f"
  chmod +x "$f"
  echo "✓ 已保存：$f"
}

apply_profile() {
  mkdir -p "$PROFILE_DIR"
  ls "$PROFILE_DIR" 2>/dev/null
  printf "\n请输入配置文件名（含 .sh）："
  read n
  [ -z "$n" ] && return 1
  f="$PROFILE_DIR/$n"
  [ ! -f "$f" ] && { echo "✗ 不存在"; return 1; }
  sh "$f"
  echo "✓ 已应用"
}

# =====================================================
#                     菜单
# =====================================================

menu_cpu() {
  while true; do
    clear 2>/dev/null
    echo "========================================"
    echo "               CPU 调优"
    echo "========================================"
    echo "  1. 查看 CPU 当前状态"
    echo "  2. 设置调度器"
    echo "  3. 设置频率（最大/最小）"
    echo "  4. 全部核心上线"
    echo "  5. 下线指定核心"
    echo "  6. 调优调度器参数"
    echo "  0. 返回"
    echo "========================================"
    printf "选择："; read c
    case "$c" in
      1) cpu_show ;;
      2) cpu_set_governor ;;
      3) cpu_set_freq ;;
      4) cpu_online_all ;;
      5) cpu_offline_big ;;
      6) cpu_tune_governor ;;
      0) return ;;
    esac
    pause
  done
}

menu_gpu() {
  while true; do
    clear 2>/dev/null
    echo "========================================"
    echo "               GPU 调优"
    echo "========================================"
    echo "  1. 查看 GPU 信息"
    echo "  2. 设置 GPU 调度器"
    echo "  3. 设置 GPU 频率"
    echo "  4. Adreno 一键调优"
    echo "  0. 返回"
    echo "========================================"
    printf "选择："; read c
    case "$c" in
      1) gpu_show ;;
      2) gpu_set_governor ;;
      3) gpu_set_freq ;;
      4) gpu_tune_adreno ;;
      0) return ;;
    esac
    pause
  done
}

menu_io() {
  while true; do
    clear 2>/dev/null
    echo "========================================"
    echo "               I/O 调优"
    echo "========================================"
    echo "  1. 查看 I/O 状态"
    echo "  2. 设置 I/O 调度器"
    echo "  3. 一键 I/O 优化"
    echo "  0. 返回"
    echo "========================================"
    printf "选择："; read c
    case "$c" in
      1) io_show ;;
      2) io_set_sched ;;
      3) io_tune ;;
      0) return ;;
    esac
    pause
  done
}

menu_mem() {
  while true; do
    clear 2>/dev/null
    echo "========================================"
    echo "              内存 / VM"
    echo "========================================"
    echo "  1. 查看内存 / VM 参数"
    echo "  2. 一键 VM 优化"
    echo "  3. 激进内存策略"
    echo "  4. 释放缓存"
    echo "  5. 内存整理"
    echo "  6. 查看 ZRAM"
    echo "  7. 设置 ZRAM 压缩算法"
    echo "  0. 返回"
    echo "========================================"
    printf "选择："; read c
    case "$c" in
      1) mem_show ;;
      2) mem_tune ;;
      3) mem_aggressive ;;
      4) mem_drop_caches ;;
      5) mem_compact ;;
      6) zram_show ;;
      7) zram_set_algorithm ;;
      0) return ;;
    esac
    pause
  done
}

menu_net() {
  while true; do
    clear 2>/dev/null
    echo "========================================"
    echo "              网络调优"
    echo "========================================"
    echo "  1. 查看 TCP 参数"
    echo "  2. 一键网络优化"
    echo "  3. 设置拥塞控制算法"
    echo "  4. 设置 DNS"
    echo "  0. 返回"
    echo "========================================"
    printf "选择："; read c
    case "$c" in
      1) net_show ;;
      2) net_tune ;;
      3) net_set_congestion ;;
      4) net_dns_set ;;
      0) return ;;
    esac
    pause
  done
}

menu_pwr() {
  while true; do
    clear 2>/dev/null
    echo "========================================"
    echo "              电源 / 温控"
    echo "========================================"
    echo "  1. 查看电源 / 温控"
    echo "  2. 关闭/开启温控"
    echo "  3. 设置充电电流上限"
    echo "  4. 关闭 Doze"
    echo "  5. 开启 Doze"
    echo "  0. 返回"
    echo "========================================"
    printf "选择："; read c
    case "$c" in
      1) pwr_show ;;
      2) pwr_toggle_thermal ;;
      3) pwr_set_charge_limit ;;
      4) sys_doze_off ;;
      5) sys_doze_on ;;
      0) return ;;
    esac
    pause
  done
}

menu_disp() {
  while true; do
    clear 2>/dev/null
    echo "========================================"
    echo "              显示 / 触控"
    echo "========================================"
    echo "  1. 查看显示信息"
    echo "  2. 设置刷新率"
    echo "  3. 动画 0.5x"
    echo "  4. 动画 1x"
    echo "  5. 完全关闭动画"
    echo "  6. 强制 GPU 渲染"
    echo "  7. 设置触控采样率"
    echo "  8. 触控高灵敏度"
    echo "  0. 返回"
    echo "========================================"
    printf "选择："; read c
    case "$c" in
      1) disp_show ;;
      2) disp_set_refresh ;;
      3) disp_anim_off ;;
      4) disp_anim_default ;;
      5) sys_disable_anim ;;
      6) sys_force_gpu_render ;;
      7) touch_set_sample ;;
      8) touch_set_sensitivity ;;
      0) return ;;
    esac
    pause
  done
}

menu_kernel() {
  while true; do
    clear 2>/dev/null
    echo "========================================"
    echo "              内核 / 系统"
    echo "========================================"
    echo "  1. 查看内核参数"
    echo "  2. 熵池优化"
    echo "  3. 调度延迟优化"
    echo "  4. 关闭崩溃重启"
    echo "  5. SELinux 模式"
    echo "  6. 后台进程限制"
    echo "  7. fstrim"
    echo "  0. 返回"
    echo "========================================"
    printf "选择："; read c
    case "$c" in
      1) kernel_show ;;
      2) kernel_entropy_boost ;;
      3) kernel_sched_tune ;;
      4) kernel_panic_off ;;
      5) sys_selinux ;;
      6) sys_bg_limit ;;
      7) sys_fstrim ;;
      0) return ;;
    esac
    pause
  done
}

menu_mode() {
  while true; do
    clear 2>/dev/null
    echo "========================================"
    echo "              一键模式"
    echo "========================================"
    echo "  1. 性能模式（高帧率，耗电）"
    echo "  2. 均衡模式（默认推荐）"
    echo "  3. 省电模式（省电优先）"
    echo "  4. 游戏模式（低延迟 + 关动画）"
    echo "  0. 返回"
    echo "========================================"
    printf "选择："; read c
    case "$c" in
      1) mode_performance ;;
      2) mode_balanced ;;
      3) mode_power_save ;;
      4) mode_game ;;
      0) return ;;
    esac
    pause
  done
}

menu_profile() {
  while true; do
    clear 2>/dev/null
    echo "========================================"
    echo "              配置管理"
    echo "========================================"
    echo "  1. 保存当前配置"
    echo "  2. 应用已有配置"
    echo "  3. 列出配置目录"
    echo "  0. 返回"
    echo "========================================"
    printf "选择："; read c
    case "$c" in
      1) save_profile ;;
      2) apply_profile ;;
      3) ls -al "$PROFILE_DIR" 2>/dev/null ;;
      0) return ;;
    esac
    pause
  done
}

# =====================================================
#                     主菜单
# =====================================================

main_menu() {
  while true; do
    clear 2>/dev/null
    echo "========================================"
    echo "        Android 性能调度优化工具箱"
    echo "========================================"
    echo " 作者：勝豪    Q群：1022873156"
    echo "----------------------------------------"
    echo " 设备：$DEV_BRAND $DEV_MODEL ($SOC_VENDOR)"
    echo " 脚本目录：$SCRIPT_DIR"
    echo "----------------------------------------"
    echo "   1. CPU 调优"
    echo "   2. GPU 调优"
    echo "   3. I/O 调优"
    echo "   4. 内存 / VM"
    echo "   5. 网络调优"
    echo "   6. 电源 / 温控"
    echo "   7. 显示 / 触控"
    echo "   8. 内核 / 系统"
    echo "   9. 一键模式"
    echo "  10. 配置保存 / 应用"
    echo "  11. ⭐ 查看设备专属调优建议"
    echo "   0. 退出"
    echo "========================================"
    printf "选择："; read c
    case "$c" in
      1) menu_cpu ;;
      2) menu_gpu ;;
      3) menu_io ;;
      4) menu_mem ;;
      5) menu_net ;;
      6) menu_pwr ;;
      7) menu_disp ;;
      8) menu_kernel ;;
      9) menu_mode ;;
      10) menu_profile ;;
      11) show_suggestions ;;
      0) echo "已退出。感谢使用，Q群：1022873156"; exit 0 ;;
      *) echo "✗ 无效选择"; pause ;;
    esac
  done
}

# ==================== 入口 ====================
require_root || exit 1
detect_device
main_menu