#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ag-split 配置生成器

从本机 v2rayN 的节点库读取「干净出口」节点的凭据，生成一份 xray 配置：
Google 系域名走干净出口，其余全部转给 v2rayN（原线路）。

用法
----
    # 1) 先列出本机有哪些节点，挑出「干净出口」那一个
    python gen-config.py --list

    # 2) 用它的 IndexId 生成配置
    python gen-config.py --node <IndexId>

环境变量（都有默认值，路径不同才需要设）
----
    V2RAYN_DIR               v2rayN 安装目录，默认 D:\\TOOL\\v2rayN
    AG_SPLIT_PORT            分流器监听端口，默认 10810
    AG_SPLIT_UPSTREAM_PORT   非 Google 流量的上游端口（v2rayN 本地入站），默认 10808

产出
----
    <V2RAYN_DIR>\\ag-split\\config.json

注意：节点凭据变化（订阅更新、改端口等）后需要重新运行本脚本并重启分流器。
"""
import argparse
import json
import os
import sqlite3
import sys

V2RAYN_DIR = os.environ.get('V2RAYN_DIR', r'D:\TOOL\v2rayN')
DB_PATH = os.path.join(V2RAYN_DIR, 'guiConfigs', 'guiNDB.db')
OUT_DIR = os.path.join(V2RAYN_DIR, 'ag-split')
OUT_PATH = os.path.join(OUT_DIR, 'config.json')

LISTEN_PORT = int(os.environ.get('AG_SPLIT_PORT', '10810'))
UPSTREAM_ADDR = '127.0.0.1'
UPSTREAM_PORT = int(os.environ.get('AG_SPLIT_UPSTREAM_PORT', '10808'))

# 走干净出口的域名（后缀匹配）。
# 刻意不含 youtube.com / googlevideo.com —— 避免把大带宽视频流量挪到较慢的线路。
GOOGLE_DOMAINS = [
    'domain:googleapis.com',
    'domain:google.com',
    'domain:google',
    'domain:gstatic.com',
    'domain:googleusercontent.com',
    'domain:withgoogle.com',
    'domain:gvt1.com',
    'domain:ggpht.com',
    'domain:google.dev',
]


def _open_db():
    if not os.path.exists(DB_PATH):
        sys.exit('找不到 v2rayN 数据库：%s\n请设置环境变量 V2RAYN_DIR 指向实际安装目录。' % DB_PATH)
    con = sqlite3.connect(DB_PATH)
    con.row_factory = sqlite3.Row
    return con


def list_nodes():
    con = _open_db()
    rows = con.execute('select IndexId, Remarks, Address, Port from ProfileItem').fetchall()
    con.close()
    if not rows:
        sys.exit('节点库为空。')
    print('本机可用节点：')
    for r in rows:
        print('  %-20s  %-42s  %s:%s' % (r['IndexId'], r['Remarks'], r['Address'], r['Port']))
    print()
    print('先逐条实测出口（见 PROMPT.md 第 1 步），挑出 hosting / proxy 均为 false 的那一个，')
    print('然后运行： python gen-config.py --node <IndexId>')


def build(node_id):
    con = _open_db()
    row = con.execute('select * from ProfileItem where IndexId=?', (node_id,)).fetchone()
    con.close()
    if row is None:
        sys.exit('找不到节点 %s。先运行 python gen-config.py --list 查看本机节点。' % node_id)

    n = dict(row)
    extra = json.loads(n.get('ProtoExtra') or '{}')
    net = (n.get('Network') or 'tcp').lower()
    if net in ('raw', ''):
        net = 'tcp'

    stream = {
        'network': net,
        'security': (n.get('StreamSecurity') or 'none').lower(),
    }
    if stream['security'] == 'reality':
        stream['realitySettings'] = {
            'serverName': n.get('Sni') or n['Address'],
            'fingerprint': n.get('Fingerprint') or 'chrome',
            'publicKey': n.get('PublicKey'),
            'shortId': n.get('ShortId') or '',
            'spiderX': n.get('SpiderX') or '',
        }
    if n.get('Alpn'):
        stream['tlsSettings'] = {'alpn': [a for a in str(n['Alpn']).split(',') if a]}

    cfg = {
        'log': {'loglevel': 'warning'},
        'dns': {'servers': ['119.29.29.29']},
        'inbounds': [{
            'tag': 'in',
            'listen': '127.0.0.1',
            'port': LISTEN_PORT,
            'protocol': 'mixed',
            'settings': {'udp': True, 'auth': 'noauth'},
            'sniffing': {'enabled': True, 'destOverride': ['http', 'tls'], 'routeOnly': False},
        }],
        'outbounds': [
            {
                'tag': 'clean',
                'protocol': 'vless',
                'settings': {'vnext': [{
                    'address': n['Address'],
                    'port': int(n['Port']),
                    'users': [{
                        # v2rayN 把 VLESS 的 UUID 存在 Password 列，不是 Id 列
                        'id': n.get('Password'),
                        'encryption': extra.get('VlessEncryption', 'none'),
                        'flow': extra.get('Flow', ''),
                    }],
                }]},
                'streamSettings': stream,
            },
            {
                'tag': 'upstream',
                'protocol': 'socks',
                'settings': {'servers': [{'address': UPSTREAM_ADDR, 'port': UPSTREAM_PORT}]},
            },
            {'tag': 'block', 'protocol': 'blackhole'},
        ],
        'routing': {
            'domainStrategy': 'AsIs',
            'rules': [
                {'type': 'field', 'port': '443', 'network': 'udp', 'outboundTag': 'block'},
                {'type': 'field', 'domain': GOOGLE_DOMAINS, 'outboundTag': 'clean'},
                # 兜底规则必须带至少一个字段，否则 xray 报 this rule has no effective fields
                {'type': 'field', 'network': 'tcp,udp', 'outboundTag': 'upstream'},
            ],
        },
    }

    os.makedirs(OUT_DIR, exist_ok=True)
    with open(OUT_PATH, 'w', encoding='utf-8') as f:
        json.dump(cfg, f, ensure_ascii=False, indent=1)
    return n, cfg


def main():
    ap = argparse.ArgumentParser(description='生成 ag-split 分流器配置')
    ap.add_argument('--node', help='干净出口节点的 IndexId')
    ap.add_argument('--list', action='store_true', help='只列出本机节点')
    args = ap.parse_args()

    if args.list or not args.node:
        list_nodes()
        return

    node, cfg = build(args.node)
    print('节点      : %s  %s:%s' % (node['Remarks'], node['Address'], node['Port']))
    print('传输      : %s / %s / flow=%s' % (
        cfg['outbounds'][0]['streamSettings']['network'],
        cfg['outbounds'][0]['streamSettings']['security'],
        cfg['outbounds'][0]['settings']['vnext'][0]['users'][0]['flow']))
    print('监听      : 127.0.0.1:%d' % LISTEN_PORT)
    print('上游      : 127.0.0.1:%d' % UPSTREAM_PORT)
    print('Google 域名: %d 条' % len(GOOGLE_DOMAINS))
    print('写出      : %s (%d bytes)' % (OUT_PATH, os.path.getsize(OUT_PATH)))
    print()
    print('下一步：语法校验后重启分流器')
    print('  "%s" run -test -c "%s"' % (os.path.join(V2RAYN_DIR, 'bin', 'xray', 'xray.exe'), OUT_PATH))


if __name__ == '__main__':
    main()
