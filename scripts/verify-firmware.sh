#!/bin/bash
# =====================================================================
# 产物层校验 + 版本归档 (编译后执行)
#
# 为什么需要它:
#   diy-part2.sh 里的校验只看 .config, 属于"编译前"检查。
#   但 make defconfig 会在展开时收敛符号 —— 例如同时写多个
#   CONFIG_TARGET_*_DEVICE_*=y 时只保留最后一个, .config 看着没问题,
#   产物里根本没有目标 profile 的镜像 (TR3000 那次刷机报
#   "Device cudy,tr3000-v1 not supported by this image"就是这么来的)。
#   只有编译产物能证明最终固件真的对得上目标设备。
#
# 校验项:
#   1. 产物目录存在, 且有可刷写镜像 (*.itb / *.bin / *.img)
#   2. profiles.json 里存在期望的 profile id
#   3. 存在文件名含期望 profile 的镜像            <- 挡住 defconfig 收敛事故
#   4. (可选) 该 profile 的 supported_devices 含期望板名
#   5. (可选) *.manifest 里含全部关键包
#   6. (可选) 不允许出现的 profile 没有混进产物
#
# 归档 (写进产物目录, 随 artifact 一起上传):
#   build.config     defconfig 后实际生效的完整配置
#   SHA256SUMS       所有可刷写镜像的校验和
#   build-info.txt   源码 commit / 各 feed commit / 编译时间 / 镜像清单
#
# 用法 (由 workflow 调用):
#   SRC_DIR=openwrt \
#   EXPECT_PROFILE=nokia_xg-040g-md-ubi \
#   EXPECT_BOARD=nokia,xg-040g-md-ubi \
#   REQUIRED_PKGS=ponwrt-required-packages.txt \
#   SOURCE_URL=https://github.com/pbs05/ponwrt \
#   SOURCE_REF=<sha> \
#   bash scripts/verify-firmware.sh
#
# 任何一项失败 -> exit 1 -> 后续 upload-artifact / release 步骤全部跳过
# =====================================================================

set -u

SRC_DIR="${SRC_DIR:-openwrt}"
EXPECT_PROFILE="${EXPECT_PROFILE:?EXPECT_PROFILE 必填}"
EXPECT_BOARD="${EXPECT_BOARD:-}"
REQUIRED_PKGS="${REQUIRED_PKGS:-}"
FORBID_PROFILES="${FORBID_PROFILES:-}"
SOURCE_URL="${SOURCE_URL:-}"
SOURCE_REF="${SOURCE_REF:-}"

FAIL=0
note() { printf '%s\n' "$*"; }
# 同时输出 ::error:: —— GitHub 会把它变成注解, 不用翻几百 MB 日志也能在
# UI 和 check-runs annotations API 里直接看到失败原因
fail() { printf 'FATAL: %s\n' "$*"; printf '::error::%s\n' "$*"; FAIL=1; }

# --- 0. 定位产物目录 ---------------------------------------------------
TARGET_DIR="$(ls -d "$SRC_DIR"/bin/targets/*/* 2>/dev/null | head -1)"
if [ -z "$TARGET_DIR" ]; then
  fail "找不到 $SRC_DIR/bin/targets/*/* —— 编译很可能没产出镜像"
  exit 1
fi
note "产物目录: $TARGET_DIR"

# --- 1. 必须有可刷写镜像 -----------------------------------------------
# 不用 mapfile: macOS 自带 bash 3.2 没有, 本地调试也要能跑
IMAGES=()
while IFS= read -r f; do IMAGES+=("$f"); done < <(find "$TARGET_DIR" -maxdepth 1 -type f \
  \( -name '*.itb' -o -name '*.bin' -o -name '*.img' -o -name '*.img.gz' -o -name '*.trx' \) \
  | sort)
if [ "${#IMAGES[@]}" -eq 0 ]; then
  fail "产物目录里没有任何可刷写镜像"
  ls -l "$TARGET_DIR"
  exit 1
fi
note "镜像 ${#IMAGES[@]} 个:"
for f in "${IMAGES[@]}"; do note "  - $(basename "$f")"; done

# --- 2. profiles.json 必须含期望的 profile -----------------------------
PROFILES_JSON="$TARGET_DIR/profiles.json"
if [ ! -f "$PROFILES_JSON" ]; then
  fail "缺少 profiles.json, 无法确认实际构建目标"
else
  HAVE=$(python3 - "$PROFILES_JSON" "$EXPECT_PROFILE" <<'PY'
import json, sys
path, want = sys.argv[1], sys.argv[2]
try:
    data = json.load(open(path))
except Exception as e:
    print("PARSE_ERROR"); sys.exit(0)
profiles = data.get("profiles", data) if isinstance(data, dict) else data
# profiles.json 里 profiles 是 {device_id: {...}} 字典
# (见 scripts/json_add_image_info.py); 老版本可能是 [{"id":..},..] 列表。
# 两种都要支持 —— 早期按列表遍历字典, 拿到的是 key 字符串,
# isinstance(p, dict) 全 False, 导致永远判定 profile 不存在。
if isinstance(profiles, dict):
    ids = list(profiles.keys())
else:
    ids = [p.get("id", "") for p in profiles if isinstance(p, dict)]
print("YES" if want in ids else "NO")
PY
)
  if [ "$HAVE" != "YES" ]; then
    fail "profiles.json 中没有 profile '$EXPECT_PROFILE'"
    python3 -c "import json,sys;d=json.load(open('$PROFILES_JSON'));p=d.get('profiles',d);print('实际 profile:',[x.get('id') for x in p])" 2>/dev/null || true
  else
    note "profiles.json 含 '$EXPECT_PROFILE' ✓"
  fi

  # --- 4. supported_devices 含期望板名 ---
  if [ -n "$EXPECT_BOARD" ]; then
    BOARDS=$(python3 - "$PROFILES_JSON" "$EXPECT_PROFILE" <<'PY'
import json, sys
path, want = sys.argv[1], sys.argv[2]
data = json.load(open(path))
profiles = data.get("profiles", data)
entry = None
if isinstance(profiles, dict):
    entry = profiles.get(want)
else:
    for p in profiles:
        if isinstance(p, dict) and p.get("id") == want:
            entry = p
            break
print(" ".join((entry or {}).get("supported_devices", [])))
PY
)
    case " $BOARDS " in
      *" $EXPECT_BOARD "*) note "supported_devices 含 '$EXPECT_BOARD' ✓" ;;
      *) fail "profile '$EXPECT_PROFILE' 的 supported_devices 不含 '$EXPECT_BOARD' (实际: ${BOARDS:-<空>})。刷机时 sysupgrade 会拒绝该镜像" ;;
    esac
  fi
fi

# --- 3. 必须有文件名含期望 profile 的镜像 ------------------------------
MATCHING=0
for f in "${IMAGES[@]}"; do
  case "$(basename "$f")" in
    *"$EXPECT_PROFILE"*) MATCHING=$((MATCHING + 1)) ;;
  esac
done
if [ "$MATCHING" -eq 0 ]; then
  fail "没有任何镜像文件名包含 '$EXPECT_PROFILE' —— make defconfig 很可能把设备选择收敛到了别的 profile"
else
  note "含 '$EXPECT_PROFILE' 的镜像 $MATCHING 个 ✓"
fi

# --- 6. 禁止出现的 profile ---------------------------------------------
if [ -n "$FORBID_PROFILES" ]; then
  for bad in $FORBID_PROFILES; do
    for f in "${IMAGES[@]}"; do
      case "$(basename "$f")" in
        *"$bad"*) fail "产物中出现不该有的 profile '$bad': $(basename "$f")" ;;
      esac
    done
  done
fi

# --- 5. 关键包必须在 manifest 里 ---------------------------------------
if [ -n "$REQUIRED_PKGS" ] && [ -f "$REQUIRED_PKGS" ]; then
  MANIFEST="$(ls "$TARGET_DIR"/*"$EXPECT_PROFILE"*.manifest 2>/dev/null | head -1)"
  if [ -z "$MANIFEST" ]; then
    MANIFEST="$(ls "$TARGET_DIR"/*.manifest 2>/dev/null | head -1)"
  fi
  if [ -z "$MANIFEST" ]; then
    fail "找不到 *.manifest, 无法核对实际打进固件的软件包"
  else
    note "manifest: $(basename "$MANIFEST")"
    MISSING=""
    while read -r pkg; do
      case "$pkg" in ''|'#'*) continue ;; esac
      grep -q "^${pkg} " "$MANIFEST" || grep -q "^${pkg}$" "$MANIFEST" || MISSING="$MISSING $pkg"
    done < "$REQUIRED_PKGS"
    if [ -n "$MISSING" ]; then
      fail "以下关键包未出现在 manifest 中:$MISSING"
    else
      note "关键包全部命中 ✓"
    fi
  fi
fi

# --- 归档: build.config / SHA256SUMS / build-info.txt ------------------
[ -f "$SRC_DIR/.config" ] && cp "$SRC_DIR/.config" "$TARGET_DIR/build.config" \
  && note "已归档 build.config"

( cd "$TARGET_DIR" && sha256sum $(for f in "${IMAGES[@]}"; do basename "$f"; done) > SHA256SUMS ) \
  && note "已归档 SHA256SUMS"

{
  echo "build_time   $(date '+%Y-%m-%d %H:%M:%S %Z')"
  echo "source_url   ${SOURCE_URL:-<未设置>}"
  echo "source_ref   ${SOURCE_REF:-<未设置>}"
  echo "target_dir   $TARGET_DIR"
  echo "profile      $EXPECT_PROFILE"
  echo "board        ${EXPECT_BOARD:-<未校验>}"
  echo ""
  echo "--- feeds (feed<TAB>commit) ---"
  if [ -d "$SRC_DIR/feeds" ]; then
    for d in "$SRC_DIR"/feeds/*/; do
      n="$(basename "$d")"
      [ -d "$d/.git" ] || continue
      c="$(git -C "$d" rev-parse HEAD 2>/dev/null || echo '<unknown>')"
      printf '%s\t%s\n' "$n" "$c"
    done
  else
    echo "<feeds 目录不存在>"
  fi
  echo ""
  echo "--- images ---"
  for f in "${IMAGES[@]}"; do
    printf '%s\t%s\n' "$(basename "$f")" "$(stat -c %s "$f" 2>/dev/null || stat -f %z "$f")"
  done
} > "$TARGET_DIR/build-info.txt"
note "已归档 build-info.txt"

# --- 汇总 ---------------------------------------------------------------
echo ""
if [ "$FAIL" -ne 0 ]; then
  echo "=========== 产物校验失败: 不上传固件, 不发布 Release ==========="
  # 诊断信息: 校验失败时把现场摊开, 免得又要再跑几小时才能定位
  echo "--- 诊断: 产物目录 ---"
  ls -l "$TARGET_DIR" 2>/dev/null | head -40
  echo "--- 诊断: profiles.json 里实际有哪些 profile ---"
  if [ -f "$PROFILES_JSON" ]; then
    python3 - "$PROFILES_JSON" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); p = d.get("profiles", d)
print(list(p.keys()) if isinstance(p, dict) else [x.get("id") for x in p])
PY
  else
    echo "(profiles.json 不存在)"
  fi
  echo "--- 诊断: manifest 前 15 行 ---"
  if [ -n "${MANIFEST:-}" ] && [ -f "$MANIFEST" ]; then
    head -15 "$MANIFEST"
  else
    echo "(manifest 未定位到)"
  fi
  exit 1
fi
echo "=========== 产物校验通过 ==========="
exit 0
