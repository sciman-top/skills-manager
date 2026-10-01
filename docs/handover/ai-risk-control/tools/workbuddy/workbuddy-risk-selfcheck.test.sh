#!/usr/bin/env bash
# ============================================================
#  WorkBuddy 风控自检脚本 —— 受控验收
#
#  原理：为每个判定分支注入一个「已知风险状态」的测试夹具，
#        运行自检脚本，断言它报出预期的结论。
#        夹具全部建在临时目录，不触碰任何真实数据。
#
#  用法：bash workbuddy-risk-selfcheck.test.sh
#  退出码：0 = 全部通过；1 = 有失败
# ============================================================

HERE="$(cd "$(dirname "$0")" && pwd)"
CHECKER="$HERE/workbuddy-risk-selfcheck.sh"
TMP="$(mktemp -d)"
TODAY="$(date '+%Y-%m-%d')"

PASS=0; FAIL=0

cleanup(){ rm -rf "$TMP" 2>/dev/null; }
trap cleanup EXIT

# 建一个空白夹具目录，回显路径
mkfix(){
  local d="$TMP/$1"
  mkdir -p "$d/ai" "$d/app/logs"
  printf '# clean hosts\n' > "$d/hosts"
  printf '[]'              > "$d/ai/models.json"
  printf '{}'              > "$d/v2ray.json"
  printf '%s' "$d"
}

# run_case <名称> <期望命中的字符串> <环境变量...>
run_case(){
  local name="$1" expect="$2"; shift 2
  local out
  out=$(env "$@" bash "$CHECKER" 2>&1)
  if printf '%s' "$out" | grep -qF -- "$expect"; then
    printf '  [PASS] %-36s -> %s\n' "$name" "$expect"
    PASS=$((PASS+1))
  else
    printf '  [FAIL] %-36s 期望: %s\n' "$name" "$expect"
    FAIL=$((FAIL+1))
    printf '%s\n' "$out" | sed 's/^/           | /'
  fi
}

printf '%s\n' "============================================================"
printf '%s\n' "  自检脚本 受控验收"
printf '%s\n' "  时间: $(date '+%Y-%m-%d %H:%M:%S')"
printf '%s\n' "============================================================"

# ---------------- 分支 1：hosts 劫持 ----------------
printf '\n%s\n' "分支 1 · hosts 劫持"
D=$(mkfix t1); printf '1.2.3.4 www.workbuddy.ai\n' > "$D/hosts"
run_case "注入劫持条目" "[高危] hosts 中存在可疑条目" \
  WB_AI_DIR="$D/ai" WB_APP_DIR="$D/app" HOSTS_FILE="$D/hosts" V2RAY_CONFIG="$D/v2ray.json"

D=$(mkfix t2)
run_case "干净 hosts" "[正常] 无 WorkBuddy/腾讯相关劫持条目" \
  WB_AI_DIR="$D/ai" WB_APP_DIR="$D/app" HOSTS_FILE="$D/hosts" V2RAY_CONFIG="$D/v2ray.json"

# ---------------- 分支 2：自定义模型 ----------------
printf '\n%s\n' "分支 2 · 自定义模型 / 反代"
D=$(mkfix t3); printf '[{"name":"evil-model","baseUrl":"http://x"}]' > "$D/ai/models.json"
run_case "注入自定义模型" "[高危] models.json 存在自定义模型配置" \
  WB_AI_DIR="$D/ai" WB_APP_DIR="$D/app" HOSTS_FILE="$D/hosts" V2RAY_CONFIG="$D/v2ray.json"

D=$(mkfix t4)
run_case "空 models.json" "[正常] models.json 为空" \
  WB_AI_DIR="$D/ai" WB_APP_DIR="$D/app" HOSTS_FILE="$D/hosts" V2RAY_CONFIG="$D/v2ray.json"

# ---------------- 分支 3：第三方指向 ----------------
printf '\n%s\n' "分支 3 · 客户端第三方指向"
D=$(mkfix t5); printf '{"theme":"dark","baseUrl":"http://third-party"}' > "$D/ai/settings.json"
run_case "注入 baseUrl 字段" "[注意] settings.json 中出现字段" \
  WB_AI_DIR="$D/ai" WB_APP_DIR="$D/app" HOSTS_FILE="$D/hosts" V2RAY_CONFIG="$D/v2ray.json"

D=$(mkfix t6); printf '{"theme":"dark"}' > "$D/ai/settings.json"
run_case "干净 settings.json" "[正常] settings.json 无 baseUrl/apiKey/endpoint" \
  WB_AI_DIR="$D/ai" WB_APP_DIR="$D/app" HOSTS_FILE="$D/hosts" V2RAY_CONFIG="$D/v2ray.json"

# ---------------- 分支 4：账号数 ----------------
printf '\n%s\n' "分支 4 · 账号与设备指纹"
D=$(mkfix t7); mkdir -p "$D/ai/11111111-1111-1111-1111-111111111111"
run_case "单账号" "[正常] 本机登录过的账号数: 1" \
  WB_AI_DIR="$D/ai" WB_APP_DIR="$D/app" HOSTS_FILE="$D/hosts" V2RAY_CONFIG="$D/v2ray.json"

D=$(mkfix t8); mkdir -p "$D/ai/11111111-1111-1111-1111-111111111111" "$D/ai/22222222-2222-2222-2222-222222222222"
run_case "双账号共用设备指纹" "[注意] 本机登录过 2 个账号" \
  WB_AI_DIR="$D/ai" WB_APP_DIR="$D/app" HOSTS_FILE="$D/hosts" V2RAY_CONFIG="$D/v2ray.json"

D=$(mkfix t8b)
run_case "无账号目录时不妄断单账号" "[信息] 未发现账号目录" \
  WB_AI_DIR="$D/ai" WB_APP_DIR="$D/app" HOSTS_FILE="$D/hosts" V2RAY_CONFIG="$D/v2ray.json"

# ---------------- 分支 5：代理例外 ----------------
printf '\n%s\n' "分支 5 · 代理例外规则"
D=$(mkfix t9)
printf '{"SysProxyType":1,"SystemProxyExceptions":"localhost;*.workbuddy.ai;*.codebuddy.ai;*.lkeap.cloud.tencent.com;"}' > "$D/v2ray.json"
run_case "例外完整（workbuddy）" "[正常] 代理例外含 *.workbuddy.ai" \
  WB_AI_DIR="$D/ai" WB_APP_DIR="$D/app" HOSTS_FILE="$D/hosts" V2RAY_CONFIG="$D/v2ray.json"
run_case "例外完整（codebuddy）" "[正常] 代理例外含 *.codebuddy.ai" \
  WB_AI_DIR="$D/ai" WB_APP_DIR="$D/app" HOSTS_FILE="$D/hosts" V2RAY_CONFIG="$D/v2ray.json"
run_case "例外完整（lkeap）" "[正常] 代理例外含 *.lkeap.cloud.tencent.com" \
  WB_AI_DIR="$D/ai" WB_APP_DIR="$D/app" HOSTS_FILE="$D/hosts" V2RAY_CONFIG="$D/v2ray.json"

D=$(mkfix t10)
printf '{"SysProxyType":1,"SystemProxyExceptions":"localhost;127.*;"}' > "$D/v2ray.json"
run_case "例外缺失 workbuddy" "[注意] 代理例外缺 *.workbuddy.ai" \
  WB_AI_DIR="$D/ai" WB_APP_DIR="$D/app" HOSTS_FILE="$D/hosts" V2RAY_CONFIG="$D/v2ray.json"

D=$(mkfix t11)
printf '{"SysProxyType":2,"SystemProxyExceptions":"localhost;"}' > "$D/v2ray.json"
run_case "识别不改变系统代理模式" "v2rayN SysProxyType=2  ->  不改变系统代理" \
  WB_AI_DIR="$D/ai" WB_APP_DIR="$D/app" HOSTS_FILE="$D/hosts" V2RAY_CONFIG="$D/v2ray.json"

# 建一个注册表快照夹具（避免验收时读真实注册表）
# mkreg <文件名> <ProxyEnable> <ProxyOverride> <NO_PROXY> <HTTP_PROXY> <ALL_PROXY>
mkreg(){
  local f="$TMP/$1"
  {
    printf 'WININET_OVERRIDE=%s\n' "$3"
    printf 'WININET_ENABLE=%s\n'   "$2"
    printf 'ENV_HTTP_PROXY=%s\n'   "$5"
    printf 'ENV_HTTPS_PROXY=%s\n'  "$5"
    printf 'ENV_ALL_PROXY=%s\n'    "$6"
    printf 'ENV_NO_PROXY=%s\n'     "$4"
  } > "$f"
  printf '%s' "$f"
}

# ---------------- 分支 6：代理例外覆盖缺口 ----------------
printf '\n%s\n' "分支 6 · 代理例外覆盖（WinINET vs 环境变量）"
REQ_ALL="workbuddy.ai,codebuddy.ai,lkeap.cloud.tencent.com"

D=$(mkfix t16); R=$(mkreg r1 1 "localhost;*.workbuddy.ai;*.codebuddy.ai;*.lkeap.cloud.tencent.com" "$REQ_ALL" "" "")
run_case "WinINET 覆盖完整" "[正常] WinINET 例外覆盖全部必需域名" \
  WB_AI_DIR="$D/ai" WB_APP_DIR="$D/app" HOSTS_FILE="$D/hosts" V2RAY_CONFIG="$D/v2ray.json" FIX_REGOUT_FILE="$R"

D=$(mkfix t17); R=$(mkreg r2 1 "localhost;*.workbuddy.ai;*.codebuddy.ai" "$REQ_ALL" "" "")
run_case "WinINET 缺 lkeap" "[注意] WinINET 例外未覆盖: lkeap.cloud.tencent.com" \
  WB_AI_DIR="$D/ai" WB_APP_DIR="$D/app" HOSTS_FILE="$D/hosts" V2RAY_CONFIG="$D/v2ray.json" FIX_REGOUT_FILE="$R"

D=$(mkfix t18); R=$(mkreg r3 0 "localhost" "$REQ_ALL" "" "")
run_case "系统代理未启用则免检" "[正常] 系统代理未启用（ProxyEnable=0），无需例外" \
  WB_AI_DIR="$D/ai" WB_APP_DIR="$D/app" HOSTS_FILE="$D/hosts" V2RAY_CONFIG="$D/v2ray.json" FIX_REGOUT_FILE="$R"

D=$(mkfix t19); R=$(mkreg r4 1 "localhost;*.workbuddy.ai;*.codebuddy.ai;*.lkeap.cloud.tencent.com" "$REQ_ALL" "" "")
run_case "NO_PROXY 覆盖完整" "[正常] NO_PROXY 覆盖全部必需域名" \
  WB_AI_DIR="$D/ai" WB_APP_DIR="$D/app" HOSTS_FILE="$D/hosts" V2RAY_CONFIG="$D/v2ray.json" FIX_REGOUT_FILE="$R"

D=$(mkfix t20); R=$(mkreg r5 1 "localhost;*.workbuddy.ai;*.codebuddy.ai;*.lkeap.cloud.tencent.com" "workbuddy.ai" "" "")
run_case "NO_PROXY 缺失多个" "[注意] NO_PROXY 未覆盖: codebuddy.ai lkeap.cloud.tencent.com" \
  WB_AI_DIR="$D/ai" WB_APP_DIR="$D/app" HOSTS_FILE="$D/hosts" V2RAY_CONFIG="$D/v2ray.json" FIX_REGOUT_FILE="$R"

D=$(mkfix t21); R=$(mkreg r6 1 "localhost;*.workbuddy.ai;*.codebuddy.ai;*.lkeap.cloud.tencent.com" "$REQ_ALL" "http://127.0.0.1:10809" "socks5h://127.0.0.1:10808")
run_case "全局代理变量已开启" "[注意] 全局代理环境变量已开启" \
  WB_AI_DIR="$D/ai" WB_APP_DIR="$D/app" HOSTS_FILE="$D/hosts" V2RAY_CONFIG="$D/v2ray.json" FIX_REGOUT_FILE="$R"

D=$(mkfix t22); R=$(mkreg r7 1 "localhost;*.workbuddy.ai;*.codebuddy.ai;*.lkeap.cloud.tencent.com" "$REQ_ALL" "" "")
run_case "全局代理变量未开启" "[正常] 未设置全局代理环境变量" \
  WB_AI_DIR="$D/ai" WB_APP_DIR="$D/app" HOSTS_FILE="$D/hosts" V2RAY_CONFIG="$D/v2ray.json" FIX_REGOUT_FILE="$R"

# .cn 域名只出现在 workbuddy-ai/logs 一侧，必须查两个根才能检出
D=$(mkfix t22b); mkdir -p "$D/ai/logs/2026-09-30"
printf 'https://www.workbuddy.cn/foo\n' > "$D/ai/logs/2026-09-30/x.log"
R=$(mkreg r8 1 "localhost;*.workbuddy.ai;*.codebuddy.ai;*.lkeap.cloud.tencent.com" "$REQ_ALL" "" "")
run_case ".cn 域名检出并补齐例外" "[注意] WinINET 例外未覆盖: workbuddy.cn codebuddy.cn" \
  WB_AI_DIR="$D/ai" WB_APP_DIR="$D/app" HOSTS_FILE="$D/hosts" V2RAY_CONFIG="$D/v2ray.json" FIX_REGOUT_FILE="$R"

# ---------------- 分支 7：重启频率 ----------------
printf '\n%s\n' "分支 7 · 重启频率"
D=$(mkfix t12)
for i in 1 2 3 4 5 6 7 8 9 10; do
  printf '[%sT0%d:00:00.000Z] [INFO] [LocalAutomationScheduler] started tickMs=30000\n' "$TODAY" "$i" >> "$D/app/logs/automation.log"
done
run_case "10 次重启" "[高危] 今日客户端启动 10 次" \
  WB_AI_DIR="$D/ai" WB_APP_DIR="$D/app" HOSTS_FILE="$D/hosts" V2RAY_CONFIG="$D/v2ray.json"

D=$(mkfix t13)
for i in 1 2; do
  printf '[%sT0%d:00:00.000Z] [INFO] [LocalAutomationScheduler] started tickMode\n' "$TODAY" "$i" >> "$D/app/logs/automation.log"
done
run_case "2 次重启" "[正常] 今日客户端启动 2 次" \
  WB_AI_DIR="$D/ai" WB_APP_DIR="$D/app" HOSTS_FILE="$D/hosts" V2RAY_CONFIG="$D/v2ray.json"

# ---------------- 分支 8：退出码 ----------------
printf '\n%s\n' "分支 8 · 退出码契约"
D=$(mkfix t14); printf '1.2.3.4 www.workbuddy.ai\n' > "$D/hosts"
env WB_AI_DIR="$D/ai" WB_APP_DIR="$D/app" HOSTS_FILE="$D/hosts" V2RAY_CONFIG="$D/v2ray.json" \
  bash "$CHECKER" > /dev/null 2>&1
RC=$?
if [ "$RC" -eq 1 ]; then
  printf '  [PASS] %-36s -> 有高危时退出码 1\n' "退出码契约"; PASS=$((PASS+1))
else
  printf '  [FAIL] %-36s 期望 1 实得 %s\n' "退出码契约" "$RC"; FAIL=$((FAIL+1))
fi

D=$(mkfix t15)
env WB_AI_DIR="$D/ai" WB_APP_DIR="$D/app" HOSTS_FILE="$D/hosts" V2RAY_CONFIG="$D/v2ray.json" \
  bash "$CHECKER" > /dev/null 2>&1
RC=$?
if [ "$RC" -eq 0 ]; then
  printf '  [PASS] %-36s -> 无高危时退出码 0\n' "退出码契约"; PASS=$((PASS+1))
else
  printf '  [FAIL] %-36s 期望 0 实得 %s\n' "退出码契约" "$RC"; FAIL=$((FAIL+1))
fi

# ---------------- 分支 9：真实日志、活动自动化、MCP 认证重试 ----------
printf '\n%s\n' "分支 9 · 实际错误日志 / 自动化 / MCP"
D=$(mkfix t23)
printf '[Error] [ACP Agent] refusal classified: httpStatus=403, bizCode=11140\n' > "$D/app/logs/runtime.log"
printf '[CREATE_ENTER] title=用户粘贴 403 request illegal\n' >> "$D/app/logs/runtime.log"
run_case "结构化 403/11140" "[高危] 实际日志命中 403/11140" \
  WB_AI_DIR="$D/ai" WB_APP_DIR="$D/app" HOSTS_FILE="$D/hosts" V2RAY_CONFIG="$D/v2ray.json"

# 429 必须只在 API 响应面（*/sdk/conversations/*）上计数
D=$(mkfix t23b)
mkdir -p "$D/app/logs/2026-10-01/sdk/conversations"
printf '2026-10-01T01:00:00.000Z runtime.applyStopReason {"errorMessageMetaPreview":"{\\"statusCode\\":429,\\"message\\":\\"Quota exceeded: 429 usage exceeds frequency limit\\"}"}\n' \
  > "$D/app/logs/2026-10-01/sdk/conversations/c429.log"
run_case "API 面 429 计入" "[注意] 实际日志命中 429" \
  WB_AI_DIR="$D/ai" WB_APP_DIR="$D/app" HOSTS_FILE="$D/hosts" V2RAY_CONFIG="$D/v2ray.json"

# 反向用例：非 API 面的日志（会话日志里"你自己写过的文档/命令文本"）不得计入 429
D=$(mkfix t23c)
printf 'user wrote: 429 Too Many Requests should not be counted here\n' \
  > "$D/app/logs/skills-manager__82dee7359119e72fb3ef1caa6551578f.log"
run_case "非 API 面 429 不计入" "[正常] 实际日志未命中结构化 429" \
  WB_AI_DIR="$D/ai" WB_APP_DIR="$D/app" HOSTS_FILE="$D/hosts" V2RAY_CONFIG="$D/v2ray.json"

D=$(mkfix t24)
printf '[MCP-ControllerState] id=custom-mcp:acme-crm state=error error=HTTP 401: unauthorized\n' > "$D/app/logs/workbuddyMainThread__t24.log"
printf '[MCP-Probe] retry scheduled id=custom-mcp:acme-crm attempt=1 delayMs=2000\n' >> "$D/app/logs/workbuddyMainThread__t24.log"
run_case "自加连接器失败持续重试" "[高危] MCP 认证失败（自加连接器）" \
  WB_AI_DIR="$D/ai" WB_APP_DIR="$D/app" HOSTS_FILE="$D/hosts" V2RAY_CONFIG="$D/v2ray.json"

D=$(mkfix t24b)
mkdir -p "$D/ai/plugins/cache/workbuddy-builtin/mcp-ardot-mcp-app"
printf '[MCP-ControllerState] id=custom-mcp:ardot state=error error=HTTP 422: {"code":10101,"msg":"access token not found"}\n' > "$D/app/logs/workbuddyMainThread__t24b.log"
printf '[MCP-Probe] retry scheduled id=custom-mcp:ardot attempt=1 delayMs=2000\n' >> "$D/app/logs/workbuddyMainThread__t24b.log"
run_case "内置插件失败降为注意" "[注意] MCP 认证失败（内置插件，非风控信号）" \
  WB_AI_DIR="$D/ai" WB_APP_DIR="$D/app" HOSTS_FILE="$D/hosts" V2RAY_CONFIG="$D/v2ray.json"

# 重试必须按 id 计数：内置插件的重试不能算到自加连接器头上
D=$(mkfix t24c)
printf '[MCP-ControllerState] id=custom-mcp:acme-crm state=error error=HTTP 401: unauthorized\n' > "$D/app/logs/workbuddyMainThread__t24c.log"
printf '[MCP-Probe] retry scheduled id=custom-mcp:ardot attempt=1 delayMs=2000\n' >> "$D/app/logs/workbuddyMainThread__t24c.log"
run_case "自加连接器无重试则为注意" "[注意] MCP 认证失败（自加连接器）" \
  WB_AI_DIR="$D/ai" WB_APP_DIR="$D/app" HOSTS_FILE="$D/hosts" V2RAY_CONFIG="$D/v2ray.json"

# 官方网关连接器（URL 落在自家域名下）必须降级 —— 且**不能**因重试被判高危
D=$(mkfix t24d)
{
  printf '[MCP-Connect] begin configId=custom-mcp:netdrive order=stream-first handshakeTimeoutMs=60000 requestTimeoutMs=60000 url=https://www.workbuddy.ai/console/agent-gateway/netdrive/mcp\n'
  printf '[MCP-ControllerState] id=custom-mcp:netdrive state=unauthorized error=Streamable HTTP error: {"error":"access_denied","error_description":"not_authorized"}\n'
  printf '[MCP-Probe] retry scheduled id=custom-mcp:netdrive attempt=1 delayMs=2000\n'
} > "$D/app/logs/workbuddyMainThread__t24d.log"
run_case "官方网关连接器降为注意" "[注意] MCP 认证失败（官方网关连接器，非风控信号）" \
  WB_AI_DIR="$D/ai" WB_APP_DIR="$D/app" HOSTS_FILE="$D/hosts" V2RAY_CONFIG="$D/v2ray.json"

# 形态二：只有 OAuth target 地址、没有 MCP-Connect 行，同样要降级
D=$(mkfix t24e)
{
  printf '[MCP-ControllerState] id=custom-mcp:genie-baas state=unauthorized error=Streamable HTTP error: {"error":"access_denied","error_description":"not_authorized"}\n'
  printf '[MCP-Probe] retry scheduled id=custom-mcp:genie-baas attempt=1 delayMs=2000\n'
  printf '[MCP-Inspect] "responseTarget":"https://www.workbuddy.ai/console/agent-gateway/genie-baas/mcp","challengePresent":false\n'
} > "$D/app/logs/workbuddyMainThread__t24e.log"
run_case "官方网关(target 形态)降为注意" "[注意] MCP 认证失败（官方网关连接器，非风控信号）" \
  WB_AI_DIR="$D/ai" WB_APP_DIR="$D/app" HOSTS_FILE="$D/hosts" V2RAY_CONFIG="$D/v2ray.json"

# 反向用例：非官方 URL 的自加连接器仍必须判高危（防止降级逻辑过度放宽）
D=$(mkfix t24f)
{
  printf '[MCP-Connect] begin configId=custom-mcp:evil-svc order=stream-first url=https://evil.example.com/mcp\n'
  printf '[MCP-ControllerState] id=custom-mcp:evil-svc state=error error=HTTP 401: unauthorized\n'
  printf '[MCP-Probe] retry scheduled id=custom-mcp:evil-svc attempt=1 delayMs=2000\n'
} > "$D/app/logs/workbuddyMainThread__t24f.log"
run_case "非官方 URL 仍判高危" "[高危] MCP 认证失败（自加连接器）" \
  WB_AI_DIR="$D/ai" WB_APP_DIR="$D/app" HOSTS_FILE="$D/hosts" V2RAY_CONFIG="$D/v2ray.json"

# 跨时间窗（实测踩过的坑）：URL 证据只在很久以前的 daemon 日志里，
# 而错误与重试在近期主线程日志里。只扫「近 3 天」会让降级逻辑静默失效。
D=$(mkfix t24g)
{
  printf '[MCP-ControllerState] id=custom-mcp:netdrive state=unauthorized error=Streamable HTTP error: {"error":"access_denied","error_description":"not_authorized"}\n'
  printf '[MCP-Probe] retry scheduled id=custom-mcp:netdrive attempt=1 delayMs=2000\n'
} > "$D/app/logs/workbuddyMainThread__t24g.log"
printf '[MCP-Connect] begin configId=custom-mcp:netdrive order=stream-first url=https://www.workbuddy.ai/console/agent-gateway/netdrive/mcp\n' > "$D/app/logs/daemon.log"
touch -d '6 days ago' "$D/app/logs/daemon.log" 2>/dev/null
run_case "URL 仅在旧 daemon 日志仍降级" "[注意] MCP 认证失败（官方网关连接器，非风控信号）" \
  WB_AI_DIR="$D/ai" WB_APP_DIR="$D/app" HOSTS_FILE="$D/hosts" V2RAY_CONFIG="$D/v2ray.json"

D=$(mkfix t25); RDB="$D/workbuddy.db"
# The checker supports WB_PY/python/python3; keep the fixture test portable
# across Windows Git Bash, WSL, and hosts where only python3 is on PATH.
PYBIN_TEST="${WB_PY:-}"
if [ -z "$PYBIN_TEST" ]; then
  for _py in python python3; do
    if command -v "$_py" >/dev/null 2>&1; then PYBIN_TEST="$_py"; break; fi
  done
fi
if [ -z "$PYBIN_TEST" ]; then
  printf '  [FAIL] %-36s 需要 Python 3（可用 WB_PY 指定）\n' "活动自动化只读计数"
  FAIL=$((FAIL+1))
else
"$PYBIN_TEST" - "$RDB" <<'PYEOF'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
con.execute("create table automations (status text, deleted_at integer)")
con.execute("insert into automations(status, deleted_at) values ('ACTIVE', null)")
con.commit(); con.close()
PYEOF
run_case "活动自动化只读计数" "[注意] 活动自动化数量: 1" \
  WB_AI_DIR="$D/ai" WB_APP_DIR="$D/app" HOSTS_FILE="$D/hosts" V2RAY_CONFIG="$D/v2ray.json" WB_DB_FILE="$RDB"
fi

# ---------------- 汇总 ----------------
printf '\n%s\n' "============================================================"
printf '  受控验收结果:  PASS %d   FAIL %d\n' "$PASS" "$FAIL"
if [ "$FAIL" -eq 0 ]; then
  printf '%s\n' "  >>> 全部分支判定正确，脚本判定逻辑通过验收"
else
  printf '%s\n' "  >>> 存在失败分支，判定逻辑需要修正"
fi
printf '%s\n' "============================================================"

if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
