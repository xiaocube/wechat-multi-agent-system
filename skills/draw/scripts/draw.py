#!/usr/bin/env python3
"""
画图脚本：调用智谱 cogview-4 文生图，下载 PNG 到当前 agent 的 workspace/media/，
输出 URL 和 PATH 两行（供 message 工具发送）。
用法:
  python3 skills/draw/scripts/draw.py "画面描述"
"""
import json
import os
import os
import sys
import urllib.request

API_KEY = os.environ.get("ZHIPU_API_KEY", "")
API_URL = "https://open.bigmodel.cn/api/paas/v4/images/generations"
MODEL = "cogview-4"


def generate(prompt, size="1024x1024"):
    body = json.dumps({"model": MODEL, "prompt": prompt, "size": size}).encode()
    req = urllib.request.Request(
        API_URL, data=body,
        headers={"Authorization": "Bearer " + API_KEY, "Content-Type": "application/json"},
        method="POST")
    with urllib.request.urlopen(req, timeout=180) as r:
        resp = json.loads(r.read().decode())
    return resp["data"][0]["url"]


def download(url, path):
    urllib.request.urlretrieve(url, path)
    return path


if __name__ == "__main__":
    prompt = sys.argv[1] if len(sys.argv) > 1 else "一只可爱的卡通机器狗"
    size = sys.argv[2] if len(sys.argv) > 2 else "1024x1024"
    # 输出到本脚本所属 agent 的 workspace/media/（skills/draw/scripts -> 上三级 = workspace）
    workspace = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
    out_dir = os.path.join(workspace, "media")
    os.makedirs(out_dir, exist_ok=True)
    out = os.path.join(out_dir, "draw.png")
    try:
        url = generate(prompt, size)
        download(url, out)
        print("URL:", url)
        print("PATH:", out)
    except Exception as e:
        print("ERROR: 生成失败 %s" % e)
        sys.exit(1)
