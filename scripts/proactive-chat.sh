#!/bin/bash
# 小奇主动聊天脚本（由 cron 每2小时±1小时随机触发）
# 逻辑：
#   1. 安静时段（睡觉）→ 不发
#   2. 随机沉默（活人感，默认40%）→ 不发
#   3. 让 agent 自己决定：上网搜有趣的事 / 提一句提醒 / 说点想说的；没话说就输出空 → 不发
export PATH="${OPENCLAW_NODE_BIN:-$HOME/opt/node26/bin}:$PATH"
export OPENCLAW_GATEWAY_TOKEN=${OPENCLAW_GATEWAY_TOKEN}

python3 - "$HOME/.openclaw/workspace/bot-config.json" "$HOME/.openclaw/workspace/REMINDERS.md" <<'PY'
import sys, json, datetime, subprocess, os, random

cfg_path, md_path = sys.argv[1], sys.argv[2]
now = datetime.datetime.now()
hour_f = now.hour + now.minute / 60

def load_cfg():
    try:
        return json.load(open(cfg_path, encoding='utf-8'))
    except Exception:
        return {}

cfg = load_cfg()
try:
    qs, qe = cfg.get("quietStart", "23:30"), cfg.get("quietEnd", "09:00")
    hs = float(qs.split(":")[0]) + float(qs.split(":")[1]) / 60
    he = float(qe.split(":")[0]) + float(qe.split(":")[1]) / 60
    quiet = (hs <= hour_f < he) if hs <= he else (hour_f >= hs or hour_f < he)
except Exception:
    quiet = False

# 1) 睡觉时间：绝不打扰
if quiet:
    sys.exit(0)

# 2) 随机沉默（活人感：不是每次都发）
silence = cfg.get("proactiveSilenceChance", 0.4)
if random.random() < silence:
    sys.exit(0)

# 3) 读取提醒清单（供 agent 参考，不强制）
reminders_note = ""
try:
    lines = [l.strip() for l in open(md_path, encoding='utf-8').read().splitlines()
             if l.strip() and not l.strip().startswith('#')]
    if lines:
        reminders_note = "\n提醒清单当前内容（可选参考，别硬提）：\n" + "\n".join(lines[:5])
except Exception:
    pass

prompt = ("小奇，现在是你的自由聊天时间，主动给用户发一条消息（像真人发微信：简短、口语、1~2句，"
          "不要客套、不要标题）。你可以："
          "1) 上网搜一件最近发生的、有趣的或值得一说的事来分享（用 web_search，搜到后挑最有趣的讲一点）；"
          "2) 单纯说点你想说的、或关心一下用户；"
          "3) 如果提醒清单里有今天稍后的事，也可以自然提一句。"
          "要求：内容要有意思、自然、短；如果你觉得实在没什么好说的，就什么都不输出（回复为空），"
          "不要为了发而发。%s" % reminders_note)

try:
    # 必须在主会话运行（不能 --session-key 单独会话），否则用户回复时小奇不知道自己发过
    r = subprocess.run(["openclaw", "agent", "--agent", "main",
                        "--message", prompt],
                       capture_output=True, text=True, timeout=180, env=dict(os.environ))
    cands = [ln.strip() for ln in (r.stdout or "").splitlines() if ln.strip()]
    if cands:
        out = cands[-1]
    else:
        out = ""
except Exception:
    out = ""

# 防御：空输出或超长都不发
if out and len(out) <= 200:
    print(out)
PY
