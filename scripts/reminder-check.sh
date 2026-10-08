#!/bin/bash
# 小奇定时提醒检查脚本 v2（由 cron 每5分钟调用）
# 逻辑：
#   1. 有"待提醒"且到期的任务 → 调 agent 拟人化 → 输出（供投递），记入 pending
#   2. pending 已存在：查上次 cron 运行记录，若已送达 → 标记"已提醒"并清理 pending；未送达 → 20分钟后重试
#   3. 无任何到期任务 → 零输出（不打扰）
export PATH="${OPENCLAW_NODE_BIN:-$HOME/opt/node26/bin}:$PATH"
export OPENCLAW_GATEWAY_TOKEN=${OPENCLAW_GATEWAY_TOKEN}
JOB_ID="4ebd3f25-051b-45c2-b7dc-ff68830de324"
RETRY_MINUTES=20

python3 - "$HOME/.openclaw/workspace/REMINDERS.md" "$HOME/.openclaw/workspace/REMINDERS.pending" "$JOB_ID" "$RETRY_MINUTES" "$HOME/.openclaw/workspace/bot-config.json" <<'PY'
import sys, datetime, subprocess, os, json

md_path, pending_path, job_id, retry_minutes, cfg_path = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4]), sys.argv[5]
now = datetime.datetime.now()

def is_quiet(hour_f):
    try:
        cfg = json.load(open(cfg_path, encoding='utf-8'))
        qs = cfg.get("quietStart", "23:30")
        qe = cfg.get("quietEnd", "09:00")
    except Exception:
        qs, qe = "23:30", "09:00"
    try:
        hs = float(qs.split(":")[0]) + float(qs.split(":")[1]) / 60
        he = float(qe.split(":")[0]) + float(qe.split(":")[1]) / 60
    except Exception:
        hs, he = 23.5, 9.0
    if hs <= he:
        return hs <= hour_f < he
    return hour_f >= hs or hour_f < he

# 安静时段（睡觉）：不投递任何提醒，任务保持待提醒，安静期结束后自动补发
hour_f = now.hour + now.minute / 60
if is_quiet(hour_f):
    sys.exit(0)

def load_lines():
    try:
        return open(md_path, encoding='utf-8').read().splitlines()
    except FileNotFoundError:
        return []

def find_due(lines):
    for i, line in enumerate(lines):
        line = line.strip()
        if not line or line.startswith('#') or '待提醒' not in line or '|' not in line:
            continue
        parts = [p.strip() for p in line.split('|')]
        if len(parts) < 3:
            continue
        try:
            t = datetime.datetime.strptime(parts[0], '%Y-%m-%d %H:%M')
        except ValueError:
            continue
        if t <= now:
            return (i, parts[0], parts[1])
    return None

def last_delivered_since(since_iso):
    """查 cron 运行记录：自 pending 创建以来，最近一次有内容的运行是否已送达"""
    try:
        r = subprocess.run(["openclaw", "cron", "runs", job_id, "--json"],
                           capture_output=True, text=True, timeout=30, env=dict(os.environ))
        data = json.loads(r.stdout)
        entries = data.get("entries", [])
    except Exception:
        return False
    for e in entries:
        summary = (e.get("summary") or "").strip()
        if not summary:
            continue
        ts_iso = e.get("tsIso") or ""
        if ts_iso and since_iso and ts_iso < since_iso:
            continue
        return e.get("deliveryStatus") == "delivered"
    return False

def compose(content, ts):
    msg = ("用户有一条到期的提醒：「%s」（原定 %s）。把它整理成一句自然、像真人微信聊天的提醒"
           "（小奇人设，简短，1句话，不要客套），只输出这句话本身，不要加引号。" % (content, ts))
    try:
        # 必须在主会话运行（不能 --session-key 单独会话），否则用户回复时小奇不记得提醒内容
        r = subprocess.run(["openclaw", "agent", "--agent", "main",
                            "--message", msg],
                           capture_output=True, text=True, timeout=120, env=dict(os.environ))
        cands = [ln.strip() for ln in (r.stdout or "").splitlines() if ln.strip()]
        if cands:
            return cands[-1]
    except Exception:
        pass
    return ""

# ---- pending 处理 ----
pending = None
try:
    pending = json.load(open(pending_path, encoding='utf-8'))
except Exception:
    pass

if pending and isinstance(pending, dict):
    if last_delivered_since(pending.get("created_iso", "")):
        # 已送达：标记已提醒并清理
        lines = load_lines()
        li = pending.get("task_line", -1)
        if 0 <= li < len(lines):
            lines[li] = lines[li].replace("待提醒", "已提醒")
            open(md_path, 'w', encoding='utf-8').write('\n'.join(lines) + '\n')
        try:
            os.remove(pending_path)
        except OSError:
            pass
        sys.exit(0)
    # 未送达：按节奏重试
    try:
        last_attempt = datetime.datetime.strptime(pending.get("attempt_iso", ""), '%Y-%m-%d %H:%M:%S')
    except Exception:
        last_attempt = now - datetime.timedelta(minutes=999)
    if (now - last_attempt).total_seconds() >= retry_minutes * 60:
        pending["attempt_iso"] = now.strftime('%Y-%m-%d %H:%M:%S')
        json.dump(pending, open(pending_path, 'w', encoding='utf-8'), ensure_ascii=False)
        print(pending.get("composed", ""))
    sys.exit(0)

# ---- 无 pending：找新到期任务 ----
lines = load_lines()
due = find_due(lines)
if due is None:
    sys.exit(0)  # 零输出，不打扰

i, ts, content = due
composed = compose(content, ts)
if not composed or len(composed) > 200:
    composed = "提醒你一下：%s" % content

json.dump({"created_iso": now.strftime('%Y-%m-%d %H:%M:%S'),
           "attempt_iso": now.strftime('%Y-%m-%d %H:%M:%S'),
           "task_line": i,
           "composed": composed},
          open(pending_path, 'w', encoding='utf-8'), ensure_ascii=False)
print(composed)
PY
