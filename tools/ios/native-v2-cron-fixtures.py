#!/usr/bin/env python3
"""以工作区已安装 APScheduler 3 验证原生构造器语料，不运行插件或后端任务。"""

import argparse
import hashlib
import inspect
import json
from pathlib import Path

import apscheduler
from apscheduler.triggers.cron import CronTrigger, expressions, fields


def generate():
    """逐项验证标准字段构造，记录输入/输出与调度器版本；不计算执行或访问外部服务。"""
    if not apscheduler.__version__.startswith("3."):
        raise ValueError("此语料必须核对现有 APScheduler 3 的星期语义")
    units = [("minute", 0, 59), ("hour", 0, 23), ("day", 1, 31), ("month", 1, 12), ("weekday", 0, 6)]
    weekdays = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
    cases = []
    for index, (unit, low, high) in enumerate(units):
        def token(value):
            """星期构造使用固定英文名，其它单位用十进制值。"""
            return weekdays[value] if unit == "weekday" else str(value)

        candidates = [("every", {}, "*")]
        candidates += [("values", {"values": [value]}, token(value)) for value in range(low, high + 1)]
        candidates += [("range", {"first": value, "last": high}, token(value) + "-" + token(high)) for value in range(low, high + 1)]
        candidates += [("step", {"start": None, "every": step},
                        ",".join(map(token, range(low, high + 1, step))) if unit == "weekday" else f"*/{step}")
                       for step in range(1, high - low + 1)]
        for start in range(low, high):
            for step in sorted({1, high - start}):
                output = ",".join(map(token, range(start, high + 1, step))) if unit == "weekday" else f"{start}/{step}"
                candidates.append(("step", {"start": start, "every": step}, output))
        if unit == "weekday":
            for mask in range(1, 128):
                values = [value for value in range(7) if mask & (1 << value)]
                candidates.append(("values", {"values": values}, ",".join(map(token, values))))
        if unit == "day":
            candidates.append(("lastDay", {}, "last"))
        for kind, arguments, output in candidates:
            parts = ["0", "0", "*", "*", "*"]
            parts[index] = output
            expression = " ".join(parts)
            CronTrigger.from_crontab(expression, timezone="UTC")
            cases.append({"unit": unit, "kind": kind, **arguments, "token": output, "expression": expression})
    return {
        "oracle": "APScheduler CronTrigger.from_crontab; parsing only, no jobs executed",
        "version": apscheduler.__version__,
        "source_sha256": {module.__name__: hashlib.sha256(inspect.getsource(module).encode()).hexdigest()
                          for module in [expressions, fields]},
        "cases": cases,
    }


def main():
    """显式写入可重放纯 JSON；Swift 测试消费语料不需要 Python 或服务器。"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    payload = generate()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n")
    print(f"Validated {len(payload['cases'])} constructors against APScheduler {payload['version']}")


if __name__ == "__main__":
    main()
