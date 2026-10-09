#!/system/bin/sh
# =============================================
#           Android 分区工具箱
#           作者：勝豪
#           Q群：1022873156
# =============================================
# 功能：提取 / 刷入 Android 常用分区
# 环境：需要 root（su），或 recovery 环境
# 用法：把本脚本和 .img 文件放同目录，执行即可
# 二改请留名
# =============================================

WORKDIR="$(pwd)"
COMMON_BASES="boot init_boot vendor_boot recovery dtbo vbmeta"

# 自动探测 by-name 目录
detect_byname() {
  for p in \
    /dev/block/by-name \
    /dev/block/bootdevice/by-name \
    /dev/block/platform/*/by-name \
    /dev/block/platform/*/*/by-name
  do
    [ -d "$p" ] && { echo "$p"; return 0; }
  done
  return 1
}

BYNAME="$(detect_byname)"

# -------------------- 基础工具 --------------------

need_root() {
  if [ "$(id -u 2>/dev/null)" != "0" ]; then
    echo "✗ 需要 root 权限（请先 su）"
    return 1
  fi
  return 0
}

check_env() {
  if [ -z "$BYNAME" ] || [ ! -d "$BYNAME" ]; then
    echo "✗ 找不到 by-name 分区目录"
    echo "  请在 Android（root）或 recovery 中运行。"
    return 1
  fi
  return 0
}

part_exists() { [ -e "$BYNAME/$1" ]; }

pause() {
  printf "\n按回车返回主菜单..."
  read dummy
}

confirm_yes() {
  printf "⚠ %s\n确认请输入 YES： " "$1"
  read ans
  case "$ans" in
    YES|yes) return 0 ;;
    *) return 1 ;;
  esac
}

confirm_yn() {
  printf "%s [y/N]: " "$1"
  read ans
  case "$ans" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

human_size() {
  b="$1"
  [ -z "$b" ] && { echo "?"; return; }
  if [ "$b" -lt 1024 ]; then
    echo "${b}B"
  elif [ "$b" -lt 1048576 ]; then
    echo "$((b / 1024))K"
  elif [ "$b" -lt 1073741824 ]; then
    echo "$((b / 1048576))M"
  else
    echo "$((b / 1073741824))G"
  fi
}

# 获取分区字节大小（失败返回空）
get_part_size() {
  link="$BYNAME/$1"
  [ -e "$link" ] || return 1
  real=$(readlink -f "$link" 2>/dev/null)
  [ -z "$real" ] && return 1
  bn=$(basename "$real")
  sf="/sys/class/block/$bn/size"
  [ -r "$sf" ] || return 1
  blocks=$(cat "$sf" 2>/dev/null)
  [ -z "$blocks" ] && return 1
  echo $((blocks * 512))
}

list_all_parts() { ls "$BYNAME" 2>/dev/null | sort; }

show_parts() {
  i=1
  for p in $(list_all_parts); do
    printf "%3d) %s\n" "$i" "$p"
    i=$((i + 1))
  done
}

# 交互式选择分区，结果从 stdout 输出
choose_part() {
  prompt="$1"
  parts=$(list_all_parts)
  if [ -z "$parts" ]; then
    echo "✗ 分区列表为空" >&2
    return 1
  fi

  echo "---------- 可用分区 ----------" >&2
  i=1
  for p in $parts; do
    printf "%3d) %s\n" "$i" "$p" >&2
    i=$((i + 1))
  done
  echo "------------------------------" >&2

  printf "%s" "$prompt" >&2
  read idx

  case "$idx" in
    ''|*[!0-9]*) echo "✗ 无效输入" >&2; return 1 ;;
  esac

  i=1
  for p in $parts; do
    if [ "$i" = "$idx" ]; then
      echo "$p"
      return 0
    fi
    i=$((i + 1))
  done

  echo "✗ 编号超出范围" >&2
  return 1
}

# -------------------- 提取 --------------------

extract_one() {
  # $1 = 分区名  $2 = 输出文件（默认 <名>.img）
  pname="$1"
  out="${2:-${pname}.img}"

  if ! part_exists "$pname"; then
    echo "· 跳过：$pname 分区不存在"
    return 1
  fi

  if [ -e "$out" ]; then
    if ! confirm_yn "$out 已存在，覆盖？"; then
      echo "· 跳过：$pname"
      return 1
    fi
  fi

  echo "→ 提取 $pname → $out"
  dd if="$BYNAME/$pname" of="$out" 2>/dev/null
  st=$?
  if [ "$st" -eq 0 ]; then
    sz=$(wc -c < "$out" 2>/dev/null)
    [ -n "$sz" ] && echo "✓ $pname 完成（$(human_size $sz)）"
    return 0
  else
    echo "✗ $pname 提取失败（dd 返回 $st）"
    rm -f "$out" 2>/dev/null
    return 1
  fi
}

extract_series() {
  # $1 = 基础名（如 boot）  $2 = silent 时不存在不提示
  base="$1"
  silent="$2"

  any=0
  part_exists "$base"     && any=1
  part_exists "${base}_a" && any=1
  part_exists "${base}_b" && any=1

  if [ "$any" -eq 0 ]; then
    [ "$silent" != "silent" ] && echo "· 未找到 $base 相关分区"
    return 1
  fi

  echo ""
  echo "======= 提取 $base 系列 ======="
  part_exists "$base"     && extract_one "$base"     "${base}.img"
  part_exists "${base}_a" && extract_one "${base}_a" "${base}_a.img"
  part_exists "${base}_b" && extract_one "${base}_b" "${base}_b.img"
  sync
}

# -------------------- 刷入 --------------------

flash_one() {
  # $1 = 镜像  $2 = 目标分区名
  img="$1"
  pname="$2"

  if [ ! -f "$img" ]; then
    echo "· 跳过：镜像 $img 不存在"
    return 1
  fi
  if ! part_exists "$pname"; then
    echo "· 跳过：分区 $pname 不存在"
    return 1
  fi

  isz=$(wc -c < "$img" 2>/dev/null)
  psz=$(get_part_size "$pname")
  if [ -n "$isz" ] && [ -n "$psz" ] && [ "$isz" -gt "$psz" ]; then
    echo "✗ 镜像 $(human_size $isz) > 分区 $(human_size $psz)，拒绝刷入"
    return 1
  fi

  echo "→ 刷入 $img → $pname"
  [ -n "$isz" ] && echo "  镜像：$(human_size $isz)"
  [ -n "$psz" ] && echo "  分区：$(human_size $psz)"

  dd if="$img" of="$BYNAME/$pname" 2>/dev/null
  st=$?
  if [ "$st" -eq 0 ]; then
    sync
    echo "✓ $pname 刷入完成"
    return 0
  else
    echo "✗ $pname 刷入失败（dd 返回 $st）"
    return 1
  fi
}

flash_series() {
  base="$1"

  # 收集清单：优先用同名 img，否则回退到 <base>.img
  todo=""
  if part_exists "$base" && [ -f "${base}.img" ]; then
    todo="$todo ${base}.img|$base"
  fi
  if part_exists "${base}_a"; then
    if [ -f "${base}_a.img" ]; then
      todo="$todo ${base}_a.img|${base}_a"
    elif [ -f "${base}.img" ]; then
      todo="$todo ${base}.img|${base}_a"
    fi
  fi
  if part_exists "${base}_b"; then
    if [ -f "${base}_b.img" ]; then
      todo="$todo ${base}_b.img|${base}_b"
    elif [ -f "${base}.img" ]; then
      todo="$todo ${base}.img|${base}_b"
    fi
  fi

  if [ -z "$todo" ]; then
    echo "· 没有可刷入的 $base 分区或镜像"
    return 1
  fi

  echo ""
  echo "======= 刷入 $base 系列 ======="
  echo "将要执行："
  for item in $todo; do
    img="${item%%|*}"
    p="${item##*|}"
    echo "  $img  →  $p"
  done

  if ! confirm_yes "刷入分区可能导致设备无法启动，请确认已备份原分区！"; then
    echo "· 已取消"
    return 1
  fi

  for item in $todo; do
    img="${item%%|*}"
    p="${item##*|}"
    flash_one "$img" "$p"
  done
  echo "✓ $base 系列处理完毕"
}

# -------------------- 自定义菜单项 --------------------

menu_extract_custom() {
  p=$(choose_part "请输入要提取的分区编号：")
  if [ -z "$p" ]; then
    pause
    return
  fi
  extract_one "$p" "${p}.img"
  pause
}

menu_flash_custom() {
  printf "请输入要刷入的镜像文件（如 boot.img）："
  read img
  if [ -z "$img" ]; then
    echo "· 已取消"
    pause
    return
  fi
  if [ ! -f "$img" ]; then
    echo "✗ 找不到文件：$img"
    pause
    return
  fi

  p=$(choose_part "请输入目标分区编号：")
  if [ -z "$p" ]; then
    pause
    return
  fi

  echo ""
  echo "将刷入：$img → $p"
  if ! confirm_yes "刷入该分区可能导致设备无法启动，请确认已备份！"; then
    echo "· 已取消"
    pause
    return
  fi
  flash_one "$img" "$p"
  pause
}

# -------------------- 主菜单 --------------------

main_menu() {
  while true; do
    clear 2>/dev/null
    echo "====================================="
    echo "          Android 分区工具箱"
    echo "====================================="
    echo " 作者：勝豪    Q群：1022873156"
    echo "-------------------------------------"
    echo " 工作目录：$WORKDIR"
    echo " 分区目录：$BYNAME"
    echo "-------------------------------------"
    echo " 【提取】"
    echo "   1. 提取 boot 系列"
    echo "   2. 提取 init_boot 系列"
    echo "   3. 提取 vendor_boot 系列"
    echo "   4. 提取 recovery 系列"
    echo "   5. 提取 dtbo 系列"
    echo "   6. 提取 vbmeta 系列"
    echo "   7. 提取全部常见系列"
    echo "   8. 提取指定分区（自定义）"
    echo "-------------------------------------"
    echo " 【刷入】"
    echo "   9. 刷入 boot 系列"
    echo "  10. 刷入 init_boot 系列"
    echo "  11. 刷入 vendor_boot 系列"
    echo "  12. 刷入 recovery 系列"
    echo "  13. 刷入 dtbo 系列"
    echo "  14. 刷入 vbmeta 系列"
    echo "  15. 刷入指定分区（自定义）"
    echo "-------------------------------------"
    echo "  16. 查看全部可用分区"
    echo "   0. 退出"
    echo "====================================="
    printf "请选择："
    read choice

    case "$choice" in
      1)  extract_series boot ;;
      2)  extract_series init_boot ;;
      3)  extract_series vendor_boot ;;
      4)  extract_series recovery ;;
      5)  extract_series dtbo ;;
      6)  extract_series vbmeta ;;
      7)
        for b in $COMMON_BASES; do
          extract_series "$b" silent
        done
        sync
        echo ""
        echo "✓ 全部常见分区提取完成，文件在：$WORKDIR"
        ;;
      8)  menu_extract_custom; continue ;;
      9)  flash_series boot ;;
      10) flash_series init_boot ;;
      11) flash_series vendor_boot ;;
      12) flash_series recovery ;;
      13) flash_series dtbo ;;
      14) flash_series vbmeta ;;
      15) menu_flash_custom; continue ;;
      16) echo ""; show_parts ;;
      0)  echo "已退出。感谢使用，Q群：1022873156"; exit 0 ;;
      *)  echo "✗ 无效选择" ;;
    esac

    pause
  done
}

# -------------------- 入口 --------------------

need_root || exit 1
check_env  || exit 1
main_menu