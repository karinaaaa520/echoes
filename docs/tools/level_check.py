#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
《影迹 Echoes》关卡可解性验证器
================================
把 ASCII 关卡转成状态机，穷举所有输入序列（BFS），判断是否有通关路径。

用途：
  1. 策划审查期：证明第 1~4 关是否可解（本报告第 5 章的表格即由本脚本产出）
  2. 开发期：每次改完关卡跑一次，防止把图改死
     → 建议后续把本文件的 bfs_solve() 移植成 Godot 的调试场景（约 60 行 GDScript）

用法：
  python3 docs/tools/level_check.py

依赖：仅标准库。
"""

from collections import deque

# (dx, dy)，y 轴向下，与 ASCII 行序一致
DIRS = {'U': (0, -1), 'D': (0, 1), 'L': (-1, 0), 'R': (1, 0)}

MAX_DEPTH = 40          # 搜索深度上限（本作最短解均 < 15 拍）
WALL = '#'

# ---------------------------------------------------------------- 关卡数据
# 第 3、4 关为审查报告 P0-3 的"行宽修正版"
LEVELS = {
    '1 回声初醒': {
        'map': [
            "#######",
            "#P...E#",
            "#.....#",
            "#..S..#",
            "#######",
        ],
        'needs': [],                # 出口无条件
    },
    '2 两处微光': {
        'map': [
            "#########",
            "#P..a..E#",
            "#.......#",
            "#..S..b.#",
            "#########",
        ],
        'needs': ['a', 'b'],
    },
    '3 钥匙的回声（修正版）': {
        'map': [
            "##########",
            "#P..K#..E#",
            "#...D....#",
            "#..S.....#",
            "##########",
        ],
        'needs': [],
    },
    '4 双重回响（修正版）': {
        'map': [
            "############",
            "#P..K#....E#",
            "#...D..a...#",
            "#..........#",
            "#..S....b..#",
            "############",
        ],
        'needs': ['a', 'b'],
    },
}

# 原始（有排版错误的）地图，用于对照
ORIGINALS = {
    '2 原图': LEVELS['2 两处微光'],
}


class Level:
    def __init__(self, rows, needs):
        self.rows = rows
        self.w = max(len(r) for r in rows)
        self.h = len(rows)
        self.widths = sorted({len(r) for r in rows})
        self.needs = frozenset(needs)
        self.player = self.shadow = self.exit = None
        self.plates, self.doors, self.keys = {}, set(), set()
        for y, row in enumerate(rows):
            for x, ch in enumerate(row):
                p = (x, y)
                if ch == 'P':
                    self.player = p
                elif ch == 'S':
                    self.shadow = p
                elif ch in 'pab':
                    self.plates[ch] = p
                elif ch in 'D+':
                    self.doors.add(p)
                elif ch == 'K':
                    self.keys.add(p)
                elif ch == 'E':
                    self.exit = p

    def at(self, p):
        x, y = p
        if x < 0 or y < 0 or x >= self.w or y >= self.h:
            return WALL
        row = self.rows[y]
        if x >= len(row):           # 短行保护：视为越界
            return WALL
        return row[x]

    def blocked(self, p, doors_open, exit_open):
        c = self.at(p)
        if c == WALL:
            return True
        if c in 'D+' and p not in doors_open:
            return True
        if c == 'E' and not exit_open:
            return True
        return False


def initial_state(lv):
    # (本体, 影子, 待执行方向, 持钥, 已开门集合, 出口是否开, 剩余钥匙集合)
    return (lv.player, lv.shadow, None, False, frozenset(), not lv.needs, frozenset(lv.keys))


def step(lv, st, inp, rule):
    """执行一拍，返回新状态与事件标记。rule = {'order': 'seq'|'sim', 'latch': bool}"""
    p, s, pend, has_key, doors, exit_open, keys = st
    events = {'door': False}

    def move(pos, d):
        return (pos[0] + DIRS[d][0], pos[1] + DIRS[d][1])

    if rule['order'] == 'seq':
        # --- 1. 影子先结算（旧方向） ---
        ns = s
        if pend:
            t = move(s, pend)
            if not lv.blocked(t, doors, exit_open) and t != p:
                ns = t
        # --- 2. 本体后结算（新输入） ---
        np = p
        if inp:
            t = move(p, inp)
            if lv.at(t) in 'D+' and t not in doors:
                if has_key:                     # 本拍只开门，不移动
                    doors = doors | {t}
                    has_key = False
                    events['door'] = True
            elif not lv.blocked(t, doors, exit_open) and t != ns:
                np = t
    else:
        # --- 同时意图结算 ---
        s_t, p_t = s, p
        if pend:
            t = move(s, pend)
            if not lv.blocked(t, doors, exit_open):
                s_t = t
        door_hit = None
        if inp:
            t = move(p, inp)
            if lv.at(t) in 'D+' and t not in doors:
                if has_key:
                    door_hit = t
            elif not lv.blocked(t, doors, exit_open):
                p_t = t
        ns, np = s_t, p_t
        if s_t == p_t and (s_t != s or p_t != p):
            ns, np = s, p                     # 争同格：双双不动
        else:
            if s_t == p and p_t == p:         # 影子想进本体格而本体不动
                ns = s
            if p_t == s and s_t == s:         # 本体想进影子格而影子不动
                np = p
        if door_hit:
            doors = doors | {door_hit}
            has_key = False
            events['door'] = True

    # --- 3. 拾取（仅本体） ---
    if np in keys:
        keys = keys - {np}
        has_key = True

    # --- 4. 机关结算 ---
    lv_plates = set()
    for pid, cell in lv.plates.items():
        if cell == np or cell == ns:
            lv_plates.add(pid)
    if lv.needs and lv.needs <= lv_plates:
        exit_open = True
    elif lv.needs and not rule['latch']:
        exit_open = False

    return (np, ns, inp, has_key, doors, exit_open, keys), events


def bfs_solve(lv, rule):
    start = initial_state(lv)
    q = deque([(start, [])])
    seen = {start}
    inputs = list(DIRS.keys())
    while q:
        st, path = q.popleft()
        if len(path) >= MAX_DEPTH:
            continue
        for inp in inputs:
            nst, _ = step(lv, st, inp, rule)
            if nst == st:
                continue
            npath = path + [inp]
            if nst[0] == lv.exit and nst[5]:
                return npath
            if nst in seen:
                continue
            seen.add(nst)
            q.append((nst, npath))
    return None


def trace(lv, rule, inputs):
    st = initial_state(lv)
    print(f"    拍  输入 | 本体      影子      待执行 钥 出口 | 事件")
    print(f"     0   -   | {st[0]!s:<9} {st[1]!s:<9} {'-':<5} {int(st[3])}  {int(st[5])}  | 初始")
    for i, inp in enumerate(inputs, 1):
        st, ev = step(lv, st, inp, rule)
        p, s, pend, hk, doors, eopen, keys = st
        note = []
        if ev['door']: note.append('开门')
        if p in lv.plates.values(): note.append('本体压板')
        if s in lv.plates.values(): note.append('影子压板')
        if p == lv.exit: note.append('本体在出口')
        print(f"    {i:>2}   {inp:<3} | {p!s:<9} {s!s:<9} {str(pend or '-'):<5} {int(hk)}  {int(eopen)}  | {','.join(note)}")
        if p == lv.exit and eopen:
            print(f"    => 第 {i} 拍通关")
            return


def main():
    rules = {
        'V1 顺序 + 出口瞬时': {'order': 'seq', 'latch': False},
        'V2 顺序 + 出口锁存': {'order': 'seq', 'latch': True},
        'V3 同时 + 出口瞬时': {'order': 'sim', 'latch': False},
        'V4 同时 + 出口锁存': {'order': 'sim', 'latch': True},
    }

    print("=" * 78)
    print("《影迹 Echoes》关卡可解性验证")
    print("=" * 78)

    solutions = {}
    for name, cfg in LEVELS.items():
        lv = Level(cfg['map'], cfg['needs'])
        ok = len(lv.widths) == 1
        print(f"\n【{name}】 {lv.w}×{lv.h}  行宽={lv.widths} {'✅ 合法' if ok else '❌ 行宽不一致'}")
        print(f"  本体{lv.player} 影子{lv.shadow} 出口{lv.exit} 板{lv.plates} 门{sorted(lv.doors)} 钥{sorted(lv.keys)}")
        for rname, rule in rules.items():
            sol = bfs_solve(lv, rule)
            if sol:
                print(f"  {rname}: ✅ 最短 {len(sol):>2} 拍  {' '.join(sol)}")
                solutions.setdefault(name, sol)
            else:
                print(f"  {rname}: ❌ 全空间搜索无解")

    print("\n" + "=" * 78)
    print("逐拍追踪（V2 规则：顺序结算 + 出口锁存）")
    print("=" * 78)
    for name, sol in solutions.items():
        print(f"\n【{name}】")
        trace(Level(LEVELS[name]['map'], LEVELS[name]['needs']), rules['V2 顺序 + 出口锁存'], sol)


if __name__ == '__main__':
    main()
