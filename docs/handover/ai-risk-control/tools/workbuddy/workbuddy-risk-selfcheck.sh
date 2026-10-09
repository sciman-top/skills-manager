#!/usr/bin/env bash
# ============================================================
#  WorkBuddy 风控自检脚本（只读，不修改任何文件）
#
#  已验证环境：Windows + Git Bash（依赖 GNU 工具：grep/sed/awk/find/xargs -r -d '\n'）
#
#  ⚠ 为什么 xargs 必须带 -d '\n'：Windows 下路径形如 C:\Users\...\Temp\tmp.X，
#    xargs 默认把反斜杠当转义符吃掉，文件就找不到（表现为"明明有日志却报未命中"）。
#    必须显式指定分隔符为换行，禁止反斜杠转义。
#  用法：
#     bash workbuddy-risk-selfcheck.sh
#     bash workbuddy-risk-selfcheck.sh > selfcheck-report.txt 2>&1
#
#  可移植性：不绑定用户名、盘符与客户端版本。代理客户端若非 v2rayN，
#            用 V2RAY_CONFIG 指到对应配置文件，或忽略该项（其余检查照常）。
#
#  路径可用环境变量覆盖（供受控验收注入测试夹具使用）：
#     WB_AI_DIR        默认 $USERPROFILE/.workbuddy-ai
#     WB_APP_DIR       默认 $USERPROFILE/.workbuddy
#     HOSTS_FILE       默认 $WINDIR/System32/drivers/etc/hosts
#     V2RAY_CONFIG     默认自动探测；显式指定则只用它
#     WB_DB_FILE       默认 $WB_AI_DIR/workbuddy.db（活动自动化检查）
#     WB_REQ_DOMAINS   必需直连域名清单，默认 workbuddy.ai codebuddy.ai
#                      lkeap.cloud.tencent.com（检测到 .cn 版会自动补齐）
#     WB_BUILTIN_DIR   内置插件目录，默认 $WB_AI_DIR/plugins/cache/workbuddy-builtin
#                      （用于把内置插件的认证失败与自加连接器区分开）
#     FIX_REGOUT_FILE  注册表快照夹具（避免验收时读真实注册表）
#     WB_PY            指定 Python 解释器（读注册表用，默认自动探测）
#
#  退出码：0 = 无高危；1 = 存在高危项
# ============================================================

U="${USERPROFILE:-$HOME}"
U="$(echo "$U" | sed 's#\\#/#g')"
B="${WB_AI_DIR:-$U/.workbuddy-ai}"
L="${WB_APP_DIR:-$U/.workbuddy}"
HOSTS="${HOSTS_FILE:-${WINDIR:-C:/Windows}/System32/drivers/etc/hosts}"

H=0; M=0; P=0
say(){ printf '%s\n' "$1"; }

say "============================================================"
say "  WorkBuddy 风控自检报告"
say "  时间: $(date '+%Y-%m-%d %H:%M:%S')"
say "  用户: $(basename "$U")"
say "============================================================"

# --- 1. hosts 劫持 -------------------------------------------------
say ""
say "1. hosts 劫持检测"
if [ -f "$HOSTS" ]; then
  BAD=$(grep -v '^#' "$HOSTS" 2>/dev/null | grep -i -E 'workbuddy|codebuddy|tencent|qq\.com')
  if [ -z "$BAD" ]; then
    say "  [正常] 无 WorkBuddy/腾讯相关劫持条目"
    say "         灰产「积分充值」靠改 hosts 实现，此项正常说明未被劫持"
    P=$((P+1))
  else
    say "  [高危] hosts 中存在可疑条目:"
    echo "$BAD" | sed 's/^/           /'
    H=$((H+1))
  fi
else
  say "  [信息] 未找到 hosts 文件: $HOSTS"
fi

# --- 2. 自定义模型 / 反代 ------------------------------------------
say ""
say "2. 自定义模型 / 反代检测"
MJ=$(cat "$B/models.json" 2>/dev/null)
if [ "$MJ" = "[]" ] || [ "$MJ" = "{}" ] || [ -z "$MJ" ]; then
  say "  [正常] models.json 为空 —— 未配置自定义模型，即未接入反代/中转站"
  P=$((P+1))
else
  say "  [高危] models.json 存在自定义模型配置 —— 需核对模型来源是否官方"
  say "         （协议 8.3.2 允许合法来源的自定义模型并保留审查权；风险在来源不明接入与反代/中转用途）"
  say "         内容片段: $(printf '%s' "$MJ" | head -c 300)"
  H=$((H+1))
fi

SP=$(tasklist 2>/dev/null | grep -i -E 'workbuddy2api|workbuddy-proxy|wb2api|flowrebound')
if [ -z "$SP" ]; then
  say "  [正常] 未发现反代/Token 提取类进程"
  P=$((P+1))
else
  say "  [高危] 发现反代类进程:"
  echo "$SP" | sed 's/^/           /'
  say "         这类工具抓取客户端 Token 对外提供 API，官方已明确「一经发现做封号处理」"
  H=$((H+1))
fi

# --- 3. 客户端第三方指向 -------------------------------------------
say ""
say "3. 客户端配置第三方指向检测"
S="$B/settings.json"
if [ -f "$S" ]; then
  TH=$(grep -o -E '"(baseUrl|apiKey|endpoint)"' "$S" 2>/dev/null | sort -u | tr '\n' ' ')
  if [ -z "$TH" ]; then
    say "  [正常] settings.json 无 baseUrl/apiKey/endpoint —— 未指向第三方服务"
    P=$((P+1))
  else
    say "  [注意] settings.json 中出现字段: $TH"
    say "         请确认这些不是指向非官方服务的配置"
    M=$((M+1))
  fi
else
  say "  [信息] 未找到 settings.json"
fi

# --- 4. 账号与设备指纹 ---------------------------------------------
say ""
say "4. 账号与设备指纹"
say "  设备指纹 device-id: $(cat "$L/device-id" 2>/dev/null)"
ACC=$(find "$B" -maxdepth 1 -type d -regextype posix-extended \
      -regex '.*/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' 2>/dev/null)
ACN=$(echo "$ACC" | grep -c .)
if [ "$ACN" -eq 0 ]; then
  say "  [信息] 未发现账号目录 —— 无法判定登录账号数（0 ≠ 单账号，勿据此宣称无风险）"
elif [ "$ACN" -eq 1 ]; then
  say "  [正常] 本机登录过的账号数: 1 —— 单账号，无账号关联风险"
  P=$((P+1))
else
  say "  [注意] 本机登录过 $ACN 个账号，共用同一设备指纹"
  echo "$ACC" | sed 's#.*/#           - #'
  say "         同设备多账号是「账号关联/批量注册」的典型特征，新账号有被连坐的风险"
  say "         建议：不要在客户端里来回切换这些账号；不要再注册新账号"
  M=$((M+1))
fi

# --- 5. 代理与直连 -------------------------------------------------
say ""
say "5. 系统代理与 WorkBuddy 直连"
say "  客户端实际访问域名（按日志频次）:"
DOMCOUNT="$(grep -o -h -E 'https?://[a-zA-Z0-9._-]+' "$L/logs/"*/[a-z]*.log 2>/dev/null \
  | sed 's#https\?://##' | sort | uniq -c | sort -rn)"
printf '%s\n' "$DOMCOUNT" | head -5 | sed 's/^/           /'
CLIENT_DOMAINS="$(printf '%s\n' "$DOMCOUNT" | awk 'NF{print $NF}')"

# .cn 域名只出现在 ~/.workbuddy-ai/logs 一侧（实测 ~/.workbuddy/logs 419 条域名记录里
# 一条 .cn 都没有 —— 只扫它会漏检）。注意：**.cn 出现 ≠ 国内版** —— 国际版客户端同样
# 会访问 www.workbuddy.cn / www.codebuddy.cn / SSO / 静态资源（实测 102/53 次），
# 这些域名若不在例外表里就会走代理出口，所以按"实际访问到"补，而不是按"版本"补。
CN_FOUND=0
for _root in "$L/logs" "$B/logs"; do
  [ -d "$_root" ] || continue
  if grep -r -q -E '(workbuddy|codebuddy)\.cn' "$_root" 2>/dev/null; then CN_FOUND=1; fi
done
if [ "$CN_FOUND" -eq 1 ]; then
  say "  检测到客户端访问 .cn 域名（workbuddy.cn / codebuddy.cn）—— 例外表需同时覆盖 .cn"
  CLIENT_DOMAINS="$CLIENT_DOMAINS workbuddy.cn codebuddy.cn"
fi

# 客户端渲染层实际代理路径（main.log resolveProxy）。WorkBuddy（Electron）带 HTTP_PROXY
# 时硬编码 setProxy 且 bypass 固定 localhost —— 例外表/NO_PROXY 对它全部失效，因此
# 「例外表检查通过」不等于「流量直连」，必须看这条记录本身。
MAINLOGS=""
for _m in "$L/logs/main.log" "$B/logs/main.log"; do
  [ -f "$_m" ] && MAINLOGS="$MAINLOGS $_m"
done
if [ -n "$MAINLOGS" ]; then
  RULES=$(cat $MAINLOGS 2>/dev/null | tail -500 \
    | grep -o -E 'resolveProxy .*rule=\\"[^\\]+\\"' \
    | sed 's/.*rule=\\"//; s/\\"$//' | sort | uniq -c | sort -rn | head -3)
  if [ -n "$RULES" ]; then
    say "  [注意] 客户端渲染层代理解析记录 (resolveProxy):"
    printf '%s\n' "$RULES" | sed 's/^/           /'
    if printf '%s\n' "$RULES" | grep -qv 'PROXY 127\.0\.0\.1:10810'; then
      say "         含非本机分流器出口 = WorkBuddy 流量以代理出口 IP 访问服务端（历史 11140 账号风控形态）"
      say "         检查例外表与 HTTP_PROXY env，或让代理端对这些域名直连"
      M=$((M+1))
    else
      say "         均为 127.0.0.1:10810（ag-split 分流器）：五域由分流器 direct(freedom) 规则兜底直连"
      say "         用 ag-health-check.ps1 的『分流器 WorkBuddy 直连规则』项确认兜底在位"
      M=$((M+1))
    fi
  else
    say "  [正常] main.log 尾部未见代理解析记录 (resolveProxy)"
    P=$((P+1))
  fi
else
  say "  [信息] 未找到 main.log，无法观测渲染层代理路径"
fi

V2=""
if [ -n "$V2RAY_CONFIG" ]; then
  [ -f "$V2RAY_CONFIG" ] && V2="$V2RAY_CONFIG"
else
  # 多个副本并存时（常见于 Downloads 里的旧解压包），取最近修改的那个 = 真正在用的
  for c in "$U/AppData/Roaming/v2rayN/guiConfigs/guiNConfig.json" \
           "$U/AppData/Local/v2rayN/guiConfigs/guiNConfig.json" \
           "$U/Downloads/Compressed/v2rayN-windows-64/guiConfigs/guiNConfig.json" \
           "C:/v2rayN/guiConfigs/guiNConfig.json" \
           "D:/v2rayN/guiConfigs/guiNConfig.json" \
           "D:/TOOL/v2rayN/guiConfigs/guiNConfig.json"; do
    [ -f "$c" ] || continue
    if [ -z "$V2" ] || [ "$c" -nt "$V2" ]; then V2="$c"; fi
  done
fi

if [ -n "$V2" ]; then
  ST=$(grep -o -E '"SysProxyType": *[0-9]+' "$V2" 2>/dev/null | grep -o '[0-9]*$')
  case "$ST" in
    0) LBL="清除系统代理" ;;
    1) LBL="自动配置系统代理（系统代理开启）" ;;
    2) LBL="不改变系统代理" ;;
    3) LBL="PAC 模式" ;;
    *) LBL="未知" ;;
  esac
  say "  v2rayN SysProxyType=$ST  ->  $LBL"
  EX=$(grep -o -E '"SystemProxyExceptions": *"[^"]*"' "$V2" 2>/dev/null | sed 's/.*: *"//; s/"$//')
  for D in workbuddy codebuddy; do
    if echo "$EX" | grep -q "$D\.ai"; then
      say "  [正常] 代理例外含 *.$D.ai —— 该域名走直连"
      P=$((P+1))
    else
      say "  [注意] 代理例外缺 *.$D.ai"
      say "         若客户端访问 .cn 版，需补充 *.workbuddy.cn ; *.codebuddy.cn"
      M=$((M+1))
    fi
  done
  if echo "$EX" | grep -q 'lkeap\.cloud\.tencent\.com'; then
    say "  [正常] 代理例外含 *.lkeap.cloud.tencent.com —— MCP/腾讯云请求走直连"
    P=$((P+1))
  else
    say "  [注意] 代理例外缺 *.lkeap.cloud.tencent.com —— MCP/腾讯云请求可能走代理出口"
    M=$((M+1))
  fi
else
  say "  [信息] 未找到 v2rayN 配置"
  say "         若使用其它代理客户端，请在其规则中确认 WorkBuddy 域名走直连"
  say "         若确有 v2rayN 但装在别处，用 V2RAY_CONFIG=<路径> 重新运行"
fi

# --- 6. 代理例外覆盖缺口（WinINET vs 环境变量） ---------------------
#  Chromium 面读系统代理(WinINET ProxyOverride)，Node 面读 HTTP_PROXY/NO_PROXY。
#  两层例外语义不同，任一层漏域名 => 该层流量走代理出口。
say ""
say "6. 代理例外覆盖缺口"
say "  Chromium 侧走 WinINET 例外，Node 侧走环境变量例外，两层必须都覆盖"

REQ="${WB_REQ_DOMAINS:-workbuddy.ai codebuddy.ai lkeap.cloud.tencent.com}"
# 另一台机器可能装的是国内版；按客户端实际域名自动补齐
if printf '%s\n' "$CLIENT_DOMAINS" | grep -q 'workbuddy\.cn'; then
  REQ="$REQ workbuddy.cn codebuddy.cn"
fi

# 取注册表快照：优先夹具文件（受控验收用），否则调 Python，否则跳过
PYBIN=""
for c in "$WB_PY" python python3 "$U"/.workbuddy-ai/binaries/python/versions/*/python.exe; do
  [ -n "$c" ] || continue
  if { command -v "$c" >/dev/null 2>&1 || [ -x "$c" ]; } && "$c" -c "import sys" >/dev/null 2>&1; then
    PYBIN="$c"; break
  fi
done

REGOUT=""
if [ -n "$FIX_REGOUT_FILE" ] && [ -f "$FIX_REGOUT_FILE" ]; then
  REGOUT="$(cat "$FIX_REGOUT_FILE")"
  RESRC="夹具"
elif [ -n "$PYBIN" ]; then
  REGOUT="$("$PYBIN" - <<'PYEOF' 2>/dev/null
import winreg
IS = r"Software\Microsoft\Windows\CurrentVersion\Internet Settings"
def get(root, path, name):
    try:
        k = winreg.OpenKey(root, path)
        v, _ = winreg.QueryValueEx(k, name)
        return v
    except Exception:
        return ""
print("WININET_OVERRIDE=" + str(get(winreg.HKEY_CURRENT_USER, IS, "ProxyOverride")))
print("WININET_ENABLE=" + str(get(winreg.HKEY_CURRENT_USER, IS, "ProxyEnable")))
for n in ("HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY"):
    print("ENV_" + n + "=" + str(get(winreg.HKEY_CURRENT_USER, "Environment", n)))
PYEOF
)"
  RESRC="注册表"
fi

gv(){ printf '%s\n' "$REGOUT" | sed -n "s/^$1=//p" | head -1; }

if [ -z "$REGOUT" ]; then
  say "  [信息] 未能读取注册表（无 Python 且未提供夹具），本项跳过"
else
  WO="$(gv WININET_OVERRIDE)"
  WE="$(gv WININET_ENABLE)"
  NO="$(gv ENV_NO_PROXY)"
  HP="$(gv ENV_HTTP_PROXY)"; SP="$(gv ENV_HTTPS_PROXY)"; AP="$(gv ENV_ALL_PROXY)"

  # 6.1 WinINET 层覆盖
  WMISS=""
  for d in $REQ; do
    printf '%s' "$WO" | grep -q -E "(\*\.)?$d(;|$)" || WMISS="$WMISS $d"
  done
  if [ "$WE" = "1" ]; then
    if [ -z "$WMISS" ]; then
      say "  [正常] WinINET 例外覆盖全部必需域名（$RESRC）"
      P=$((P+1))
    else
      say "  [注意] WinINET 例外未覆盖:$WMISS"
      say "         这些域名的 Chromium 侧请求会走代理出口（可能落在境外 IP）"
      say "         修法：把 *.域名 加入系统代理例外（v2rayN -> 参数设置 -> 系统代理例外）"
      M=$((M+1))
    fi
  else
    say "  [正常] 系统代理未启用（ProxyEnable=$WE），无需例外"
    P=$((P+1))
  fi

  # 6.2 环境变量层覆盖
  NMISS=""
  for d in $REQ; do
    printf '%s' "$NO" | grep -q -E "(\*\.)?$d(,|$)" || NMISS="$NMISS $d"
  done
  if [ -z "$NMISS" ]; then
    say "  [正常] NO_PROXY 覆盖全部必需域名（$RESRC）"
    P=$((P+1))
  else
    say "  [注意] NO_PROXY 未覆盖:$NMISS"
    say "         修法：把域名补进用户级 NO_PROXY（注意用裸域名，别写 *.，否则部分客户端反而不匹配）"
    M=$((M+1))
  fi

  # 6.3 全局代理环境变量本身是否开启（混合出口的根源）
  if [ -n "$HP$SP$AP" ]; then
    say "  [注意] 全局代理环境变量已开启: HTTP_PROXY='$HP' HTTPS_PROXY='$SP' ALL_PROXY='$AP'"
    say "         认代理但不认 NO_PROXY 的组件会把流量送境外出口；"
    say "         能改则改为按需在具体工具里设，或确认 NO_PROXY 已覆盖全部必需域名"
    M=$((M+1))
  else
    say "  [正常] 未设置全局代理环境变量"
    P=$((P+1))
  fi
fi

# --- 7. 重启频率 ---------------------------------------------------
say ""
say "7. 客户端重启频率"
AL="$L/logs/automation.log"
if [ -f "$AL" ]; then
  N=$(grep -c "$(date '+%Y-%m-%d').*started" "$AL" 2>/dev/null)
  if [ "$N" -le 3 ]; then
    say "  [正常] 今日客户端启动 $N 次"
    P=$((P+1))
  elif [ "$N" -le 8 ]; then
    say "  [注意] 今日客户端启动 $N 次，偏频繁"
    say "         报错时请先停手，不要靠反复重启来试"
    M=$((M+1))
  else
    say "  [高危] 今日客户端启动 $N 次 —— 反复重启会被计入异常行为特征"
    H=$((H+1))
  fi
else
  say "  [信息] 未找到 automation.log"
fi

# --- 8. 实际服务错误日志（排除用户输入/命令回显/沙箱日志） ---------
#  真实 API 响应体在 */sdk/conversations/*.log（形如 runtime.applyStopReason
#  ... TURN_ERROR ... statusCode:403 / code:11140）。
#  logs/sandbox/*.log 记录的是本地工具输出回显，***必须排除***，否则会把
#  "自己 grep 过这些字符串"当成命中，造成大量假阳性。
say ""
say "8. 实际服务错误日志"
LOG_FILES=""
LOG_FILES_RECENT=""
for root in "$L/logs" "$B/logs"; do
  if [ -d "$root" ]; then
    while IFS= read -r f; do LOG_FILES="$LOG_FILES"$'\n'"$f"; done \
      < <(find "$root" -type f \( -name '*.log' -o -name '*.jsonl' -o -name '*.txt' \) ! -path '*/sandbox/*' 2>/dev/null)
    while IFS= read -r f; do LOG_FILES_RECENT="$LOG_FILES_RECENT"$'\n'"$f"; done \
      < <(find "$root" -type f \( -name '*.log' -o -name '*.jsonl' -o -name '*.txt' \) ! -path '*/sandbox/*' -mtime -3 2>/dev/null)
  fi
done

#  真实 API 响应只出现在 */sdk/conversations/*.log（runtime.applyStopReason
#  ... TURN_ERROR ... statusCode:403 / code:11140）。
#  普通会话日志会记录用户/AI 自己执行过的命令，里面同样含这些字符串 ——
#  若把 LOG_FILES 全量拿来搜，会把"自己 grep 过 403"当成命中（实测假阳性 >90%）。
API_LOGS=""
for root in "$L/logs" "$B/logs"; do
  [ -d "$root" ] || continue
  while IFS= read -r f; do API_LOGS="$API_LOGS"$'\n'"$f"; done \
    < <(find "$root" -type f -path '*/sdk/conversations/*.log' ! -path '*/sandbox/*' 2>/dev/null)
done
# 该目录不存在（客户端版本/安装差异）时退回全量，避免漏检。
# ⚠️ 但回退面**必须排除「会话日志」**（`<项目名>__<hex>.log`、`workbuddyMainThread__<hex>.log`）——
#    它们记录的是你自己执行过的命令与写过的文档，是自污染的唯一来源。
#    实测：写一份含 "429 Too Many Requests" 的报告后，计数从 14 涨到 27，全是自污染。
if [ -z "$(printf '%s' "$API_LOGS" | tr -d ' \n')" ]; then
  API_LOGS="$(printf '%s\n' "$LOG_FILES" | sed '/^$/d' | grep -v -E '__[0-9a-f]{8,}\.log$')"
fi

FILT='CREATE_ENTER|EB_SYNC_ADDED|BashTool|Sandbox|command=|title='
P403='bizCode=11140|httpStatus=403|403 request illegal|refusal classified'
#  错误体在日志里常以嵌套 JSON 出现（引号前带反斜杠转义），模式同时匹配裸/转义两种形式
P429='exceeded retry limit.*429|status:[[:space:]]*429|429 Too Many Requests|\\?"statusCode\\?":[[:space:]]*429'
hits(){ printf '%s\n' "$1" | sed '/^$/d' | xargs -r -d '\n' grep -h -i -E "$2" 2>/dev/null | grep -v -E "$FILT" | wc -l | tr -d ' '; }
#  命中行本体（供按天归因）：真实 API 日志行以 ISO 时间戳开头，夹具/无时间戳行没有
hit_lines(){ printf '%s\n' "$1" | sed '/^$/d' | xargs -r -d '\n' grep -h -i -E "$2" 2>/dev/null | grep -v -E "$FILT"; }

REAL_403=0; REAL_403_ALL=0; REAL_429=0
L403_RECENT=""
API_RECENT=""
for f in $(printf '%s\n' "$API_LOGS" | sed '/^$/d'); do
  [ -n "$(find "$f" -mtime -3 -print 2>/dev/null)" ] && API_RECENT="$API_RECENT"$'\n'"$f"
done
if [ -n "$API_RECENT" ]; then L403_RECENT=$(hit_lines "$API_RECENT" "$P403"); REAL_403=$(printf '%s\n' "$L403_RECENT" | sed '/^$/d' | wc -l | tr -d ' '); fi
if [ -n "$API_LOGS" ]; then REAL_403_ALL=$(hits "$API_LOGS" "$P403"); fi
#  429 同样只能扫 API 响应面，不能扫全量日志：
#  普通会话日志会记录"你自己写过的文档/命令文本"，里面出现的
#  "429 Too Many Requests" 会被当成真实限流 —— 实测：写一份含该串的报告后，
#  计数从 14 直接涨到 27，全部是自污染。
if [ -n "$API_LOGS" ]; then REAL_429=$(hits "$API_LOGS" "$P429"); fi

#  命中算不算"当前复发"看最新命中日期，不看总数：换号/修复前的历史事故
#  （如旧账号风控期）会在 -mtime -3 窗口里停留 3 天，按总数报高危会造成
#  "修复成功后高危长期挂账"。最新命中 ≥2 天前 => 降级为历史记录。
#  无时间戳的命中行（如受控验收夹具）按当前复发处理（保守，维持高危）。
TODAY_403="$(date '+%Y-%m-%d')"
YDAY_403="$(date -d '1 day ago' '+%Y-%m-%d' 2>/dev/null)"
NEWEST_403="$(printf '%s\n' "$L403_RECENT" | grep -o -E '^2026-[0-9]{2}-[0-9]{2}' | sort -u | tail -1)"
DAYHIST_403="$(printf '%s\n' "$L403_RECENT" | grep -o -E '^2026-[0-9]{2}-[0-9]{2}' | sort | uniq -c | awk '{printf "%s×%s ", $2, $1}')"
if [ "$REAL_403" -gt 0 ]; then
  if [ -z "$NEWEST_403" ] || [ "$NEWEST_403" = "$TODAY_403" ] || { [ -n "$YDAY_403" ] && [ "$NEWEST_403" = "$YDAY_403" ]; }; then
    if [ -n "$NEWEST_403" ]; then
      say "  [高危] 实际日志命中 403/11140: $REAL_403 条（近 3 天，已排除沙箱回显与标题文本；最新 $NEWEST_403）"; H=$((H+1))
    else
      say "  [高危] 实际日志命中 403/11140: $REAL_403 条（近 3 天，已排除沙箱回显与标题文本）"; H=$((H+1))
    fi
  else
    say "  [注意] 实际日志命中 403/11140: $REAL_403 条（$DAYHIST_403）—— 最新命中在 2 天前且其后无复发，属历史事故记录（如换号前旧账号风控期），非当前复发"; M=$((M+1))
  fi
elif [ "$REAL_403_ALL" -gt 0 ]; then
  say "  [注意] 实际日志命中 403/11140: $REAL_403_ALL 条，但均为 3 天前（历史记录，未复发）"; M=$((M+1))
else
  say "  [正常] 实际日志未命中结构化 403/11140"; P=$((P+1))
fi
if [ "$REAL_429" -gt 0 ]; then
  say "  [注意] 实际日志命中 429/Too Many Requests: $REAL_429 条（不等于账号封禁，需结合 Retry-After/上游状态）"; M=$((M+1))
else
  say "  [正常] 实际日志未命中结构化 429"; P=$((P+1))
fi

# --- 9. 活动自动化与 MCP 认证重试 -------------------------------
say ""
say "9. 活动自动化与 MCP 认证重试"
DB="$WB_DB_FILE"
[ -n "$DB" ] || DB="$B/workbuddy.db"
ACTIVE_AUTOMATIONS=""
if [ -f "$DB" ]; then
  PYBIN2=""
  for c in "$WB_PY" python python3; do
    [ -n "$c" ] || continue
    if command -v "$c" >/dev/null 2>&1; then PYBIN2="$c"; break; fi
  done
  if [ -n "$PYBIN2" ]; then
    ACTIVE_AUTOMATIONS="$("$PYBIN2" - "$DB" <<'PYEOF' 2>/dev/null
import sqlite3, sys
try:
    con = sqlite3.connect("file:" + sys.argv[1] + "?mode=ro", uri=True)
    row = con.execute("select count(*) from automations where status='ACTIVE' and deleted_at is null").fetchone()
    print(row[0] if row else 0)
except Exception:
    print("unknown")
PYEOF
)"
  fi
fi
if [ -z "$ACTIVE_AUTOMATIONS" ]; then
  say "  [信息] 无法读取活动自动化数量（仅做本地只读检查）"
elif [ "$ACTIVE_AUTOMATIONS" = "unknown" ]; then
  say "  [信息] workbuddy.db 可见但自动化表读取失败"
elif [ "$ACTIVE_AUTOMATIONS" -gt 0 ] 2>/dev/null; then
  say "  [注意] 活动自动化数量: $ACTIVE_AUTOMATIONS —— 请确认频率、模型与失败重试策略"; M=$((M+1))
else
  say "  [正常] 活动自动化数量: 0"; P=$((P+1))
fi

#  只认真实连接器 id（custom-mcp:xxx / builtin:xxx / mcp:xxx），并按 id 去重。
#  不数行数 —— 会话日志会记录"你跑过的测试夹具与命令回显"，数行数会被自己污染
#  （实测：每跑一次受控验收，计数就 +18）。按 id 去重后，回显与真实失败折叠为同一条。
MCP_IDPAT='(custom-mcp|builtin|mcp):[a-z0-9._-]+'
mcp_ids(){
  [ -n "$1" ] || return 0
  printf '%s\n' "$1" | sed '/^$/d' | xargs -r -d '\n' \
    grep -h -o -E "\[MCP-ControllerState\] id=$MCP_IDPAT state=(error|unauthorized)" 2>/dev/null \
    | sed -E 's/.*id=([^ ]+) state=.*/\1/' | sort -u | tr '\n' ' '
}
#  重试必须**按 id 精确计数**：全局计数会把"别的连接器（尤其是内置插件）的重试"
#  算到自加连接器头上。实测踩过：ardot（内置）有 214 次重试，而 genie-baas / netdrive
#  重试为 0 —— 全局口径却把它们报成"含 335 次重试"的高危，完全误判。
mcp_retries_for(){
  local files="$1" ids="$2" total=0 c
  [ -n "$files" ] || { echo 0; return 0; }
  for _rid in $ids; do
    c=$(printf '%s\n' "$files" | sed '/^$/d' | xargs -r -d '\n' \
        grep -h -o -F "[MCP-Probe] retry scheduled id=$_rid" 2>/dev/null | wc -l | tr -d ' ')
    total=$((total + c))
  done
  echo "$total"
}

#  真实 MCP 状态只出现在客户端主线程日志 workbuddyMainThread__*.log；
#  项目会话日志（<项目名>__<hash>.log）记录的是"你自己执行过的命令"，
#  里面同样含这些字符串 —— 实测就是这样把测试夹具的 id 当成真实连接器的。
MCP_LOGS=""
for _root in "$L/logs" "$B/logs"; do
  [ -d "$_root" ] || continue
  while IFS= read -r f; do MCP_LOGS="$MCP_LOGS"$'\n'"$f"; done \
    < <(find "$_root" -type f -name 'workbuddyMainThread__*.log' ! -path '*/sandbox/*' 2>/dev/null)
done
# 找不到主线程日志（客户端版本/安装差异）时退回全量，避免漏检
if [ -z "$(printf '%s' "$MCP_LOGS" | tr -d ' \n')" ]; then MCP_LOGS="$LOG_FILES"; fi
MCP_RECENT=""
for f in $(printf '%s\n' "$MCP_LOGS" | sed '/^$/d'); do
  [ -n "$(find "$f" -mtime -3 -print 2>/dev/null)" ] && MCP_RECENT="$MCP_RECENT"$'\n'"$f"
done

MCP_FAIL_RECENT="$(mcp_ids "$MCP_RECENT")"
MCP_FAIL_ALL="$(mcp_ids "$MCP_LOGS")"

#  内置插件 vs 自加连接器必须分开判：内置插件（随客户端分发在
#  plugins/cache/workbuddy-builtin/ 下）在未配置令牌时返回
#  HTTP 422 {"code":10101,"msg":"access token not found"} —— 这是**预期行为**，
#  不是风控信号。把它判 [高危] 会造成"永久狼来了"，把真实高危淹没。
#  注意 id → 目录名不是固定变换（ardot→mcp-ardot-mcp-app，miora→mcp-miora），
#  因此用子串匹配而非精确拼接。
BUILTIN_DIR="${WB_BUILTIN_DIR:-$B/plugins/cache/workbuddy-builtin}"
is_builtin_conn(){
  [ -d "$BUILTIN_DIR" ] || return 1
  find "$BUILTIN_DIR" -maxdepth 1 -type d -iname "*$1*" 2>/dev/null | grep -q .
}
#  官方网关连接器同理必须降级：URL 落在自家域名下
#  （如 https://www.workbuddy.ai/console/agent-gateway/netdrive/mcp），
#  未授权只是没配令牌，返回 access_denied，属预期行为。
#  实测踩过：netdrive / genie-baas 被误判成「自加连接器认证失败」而长期
#  占据 [高危]，把真实高危淹没，造成"永久狼来了"。
#
#  ⚠ 探测面不能只取"近 3 天"：连接器→URL 的映射是长期不变的，而
#    MCP-Connect / OAuth target 行常常只出现在更早的日志或 daemon 日志里。
#    实测：netdrive 的 MCP-Connect 行只在 2026-09-24/25 的日志里，
#    genie-baas 的 target 行只在 daemon.log 里 —— 只看近 3 天会漏掉，
#    导致降级逻辑静默失效（表现为"改了却没用"）。
MCP_OFFICIAL_LOGS="$MCP_LOGS"
for _root in "$L/logs" "$B/logs"; do
  [ -d "$_root" ] || continue
  while IFS= read -r f; do MCP_OFFICIAL_LOGS="$MCP_OFFICIAL_LOGS"$'\n'"$f"; done \
    < <(find "$_root" -maxdepth 1 -type f -name 'daemon*.log' 2>/dev/null)
done
MCP_OFFICIAL_IDS=""
if [ -n "$(printf '%s' "$MCP_OFFICIAL_LOGS" | tr -d ' \n')" ]; then
  _og1=$(printf '%s\n' "$MCP_OFFICIAL_LOGS" | sed '/^$/d' | xargs -r -d '\n' \
    grep -h -o -E '\[MCP-Connect\] begin configId=[^ ]+.*url=https?://[^ ]+' 2>/dev/null \
    | sed -E 's/.*configId=([^ ]+).*url=https?:\/\/([^\/]+).*/\1 \2/' \
    | awk '{h=$2; if (h ~ /(^|\.)(workbuddy|codebuddy)\.(ai|cn)$/) print $1}')
  _og2=$(printf '%s\n' "$MCP_OFFICIAL_LOGS" | sed '/^$/d' | xargs -r -d '\n' \
    grep -h -o -E 'https?://([a-zA-Z0-9-]+\.)*(workbuddy|codebuddy)\.(ai|cn)/[^" ]*agent-gateway/[a-zA-Z0-9._-]+/' 2>/dev/null \
    | sed -E 's#.*agent-gateway/([a-zA-Z0-9._-]+)/.*#custom-mcp:\1#')
  MCP_OFFICIAL_IDS=$(printf '%s\n%s\n' "$_og1" "$_og2" | sed '/^$/d' | sort -u | tr '\n' ' ')
fi
is_official_conn(){
  [ -n "$MCP_OFFICIAL_IDS" ] || return 1
  printf '%s\n' $MCP_OFFICIAL_IDS | grep -qxF "$1"
}
MCP_BUILTIN=""; MCP_OFFICIAL=""; MCP_USER=""
for _id in $MCP_FAIL_RECENT; do
  if is_builtin_conn "${_id##*:}"; then
    MCP_BUILTIN="$MCP_BUILTIN $_id"
  elif is_official_conn "$_id"; then
    MCP_OFFICIAL="$MCP_OFFICIAL $_id"
  else
    MCP_USER="$MCP_USER $_id"
  fi
done
# 只统计**自加连接器**自身的重试（内置插件的重试不算在它们头上）
MCP_RETRY="$(mcp_retries_for "$MCP_RECENT" "$MCP_USER")"

MCP_ANY_RECENT="$(printf '%s' "$MCP_USER$MCP_BUILTIN$MCP_OFFICIAL" | tr -d ' ')"
if [ -n "$(printf '%s' "$MCP_USER" | tr -d ' ')" ]; then
  if [ "$MCP_RETRY" -gt 0 ]; then
    say "  [高危] MCP 认证失败（自加连接器）: $MCP_USER（近 3 天，含 $MCP_RETRY 次探测重试）—— 认证失败不应持续自动重试"; H=$((H+1))
  else
    say "  [注意] MCP 认证失败（自加连接器）: $MCP_USER（近 3 天，当前无重试）—— 需定位凭据来源后处理"; M=$((M+1))
  fi
fi
if [ -n "$(printf '%s' "$MCP_BUILTIN" | tr -d ' ')" ]; then
  say "  [注意] MCP 认证失败（内置插件，非风控信号）: $MCP_BUILTIN"
  say "         内置插件未配置令牌即返回 422 / code 10101，属预期行为；"
  say "         不要据此改网络例外或客户端状态（无因果证据）"
  M=$((M+1))
fi
if [ -n "$(printf '%s' "$MCP_OFFICIAL" | tr -d ' ')" ]; then
  say "  [注意] MCP 认证失败（官方网关连接器，非风控信号）: $MCP_OFFICIAL"
  say "         URL 落在 workbuddy.ai / codebuddy.ai 自家域名下（console/agent-gateway/…），"
  say "         未授权只是没配令牌（access_denied），属预期行为，不是风控信号，无需处理"
  M=$((M+1))
fi
if [ -z "$MCP_ANY_RECENT" ]; then
  if [ -n "$(printf '%s' "$MCP_FAIL_ALL" | tr -d ' ')" ]; then
    say "  [注意] MCP 历史认证失败: $MCP_FAIL_ALL（均为 3 天前，未复发）"; M=$((M+1))
  else
    say "  [正常] 未发现 MCP 认证失败"; P=$((P+1))
  fi
fi

# --- 汇总 ----------------------------------------------------------
say ""
say "============================================================"
say "  高危 $H 项  |  注意 $M 项  |  正常 $P 项"
if [ "$H" -gt 0 ]; then
  say "  >>> 存在高危项，请优先处理上面标 [高危] 的条目"
elif [ "$M" -gt 0 ]; then
  say "  >>> 无高危项，有若干注意项，建议按提示逐条确认"
else
  say "  >>> 全部检查通过，环境干净"
fi
say ""
say "  本脚本只读检测，不修改任何文件。"
say "  官方反馈：客户端 帮助 -> helpFeedback ；邮箱 workbuddy_ai@tencent.com"
say "============================================================"

if [ "$H" -gt 0 ]; then exit 1; fi
exit 0
