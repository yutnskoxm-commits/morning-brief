#!/usr/bin/env python3
"""
FinFlash 生成器 — Python 回退脚本
当 Claude 不在线时，可手动运行此脚本生成当日FinFlash 快报。

数据来源（免费，无需 API Key）：
  - CoinGecko API：加密货币价格
  - Yahoo Finance (yfinance)：股票指数
  - RSS 新闻源：全球新闻

用法：
  python3 morning_report.py           # 生成今天（周一至周五）的FinFlash 快报
  python3 morning_report.py --date 2026-07-01  # 指定日期
  python3 morning_report.py --output custom.md  # 自定义输出路径
"""

import argparse
import json
import os
import sys
import time
from datetime import datetime, timedelta
from pathlib import Path
from typing import Optional

import requests

# ── 路径配置 ──────────────────────────────────────────────
SCRIPT_DIR = Path(__file__).resolve().parent
REPORTS_DIR = SCRIPT_DIR / "reports"
REPORTS_DIR.mkdir(exist_ok=True)

# ── 数据获取 ──────────────────────────────────────────────

def fetch_coingecko() -> dict:
    """获取 BTC 和 ETH 最新价格（CoinGecko 免费 API）"""
    url = "https://api.coingecko.com/api/v3/simple/price"
    params = {
        "ids": "bitcoin,ethereum",
        "vs_currencies": "usd",
        "include_24hr_change": "true",
        "include_market_cap": "true",
    }
    try:
        r = requests.get(url, params=params, timeout=15)
        r.raise_for_status()
        data = r.json()
        return {
            "btc_price": data.get("bitcoin", {}).get("usd"),
            "btc_change_24h": data.get("bitcoin", {}).get("usd_24h_change"),
            "btc_market_cap": data.get("bitcoin", {}).get("usd_market_cap"),
            "eth_price": data.get("ethereum", {}).get("usd"),
            "eth_change_24h": data.get("ethereum", {}).get("usd_24h_change"),
            "eth_market_cap": data.get("ethereum", {}).get("usd_market_cap"),
        }
    except Exception as e:
        print(f"[WARN] CoinGecko API 请求失败: {e}", file=sys.stderr)
        return {}


def fetch_fear_greed() -> Optional[int]:
    """获取恐惧贪婪指数"""
    url = "https://api.alternative.me/fng/"
    try:
        r = requests.get(url, params={"limit": 1}, timeout=10)
        r.raise_for_status()
        data = r.json()
        return int(data["data"][0]["value"])
    except Exception as e:
        print(f"[WARN] Fear & Greed API 请求失败: {e}", file=sys.stderr)
        return None


def fetch_gold_price() -> Optional[float]:
    """获取黄金价格（美元/盎司）"""
    url = "https://api.metals.live/v1/spot/gold"
    try:
        r = requests.get(url, timeout=10)
        r.raise_for_status()
        data = r.json()
        return data[0].get("price")
    except Exception:
        # Fallback: goldapi.io free endpoint
        try:
            url2 = "https://www.goldapi.io/api/XAU/USD"
            headers = {"x-access-token": "goldapi-demo"}
            r2 = requests.get(url2, headers=headers, timeout=10)
            return r2.json().get("price")
        except Exception as e:
            print(f"[WARN] Gold price API 请求失败: {e}", file=sys.stderr)
            return None


def fetch_yfinance_indices() -> dict:
    """通过 yfinance 获取主要指数数据"""
    try:
        import yfinance as yf
    except ImportError:
        print("[WARN] yfinance 未安装，跳过指数数据。安装: pip install yfinance", file=sys.stderr)
        return {}

    tickers = {
        "上证指数": "000001.SS",
        "恒生指数": "^HSI",
        "标普500": "^GSPC",
        "纳斯达克": "^IXIC",
    }
    results = {}
    for name, symbol in tickers.items():
        try:
            t = yf.Ticker(symbol)
            hist = t.history(period="2d")
            if len(hist) >= 2:
                prev_close = hist["Close"].iloc[-2]
                current = hist["Close"].iloc[-1]
                change_pct = ((current - prev_close) / prev_close) * 100
                results[name] = {
                    "symbol": symbol,
                    "price": round(current, 2),
                    "change_pct": round(change_pct, 2),
                }
            elif len(hist) == 1:
                results[name] = {
                    "symbol": symbol,
                    "price": round(hist["Close"].iloc[-1], 2),
                    "change_pct": None,
                }
            time.sleep(0.3)
        except Exception as e:
            print(f"[WARN] yfinance {symbol} 失败: {e}", file=sys.stderr)
    return results


# ── 报告生成 ──────────────────────────────────────────────

WEEKDAY_CN = ["一", "二", "三", "四", "五", "六", "日"]


def format_change(val: Optional[float]) -> str:
    if val is None:
        return "—"
    sign = "+" if val >= 0 else ""
    return f"{sign}{val:.2f}%"


def format_price(val: Optional[float], prefix: str = "") -> str:
    if val is None:
        return "—"
    return f"{prefix}{val:,.2f}"


def fear_greed_label(val: int) -> str:
    if val <= 25:
        return "极度恐惧 (Extreme Fear)"
    elif val <= 45:
        return "恐惧 (Fear)"
    elif val <= 55:
        return "中性 (Neutral)"
    elif val <= 75:
        return "贪婪 (Greed)"
    else:
        return "极度贪婪 (Extreme Greed)"


def generate_report(date_str: str) -> str:
    """生成FinFlash 快报 markdown 内容"""
    dt = datetime.strptime(date_str, "%Y-%m-%d")
    weekday = WEEKDAY_CN[dt.weekday()]
    date_cn = f"{dt.year}年{dt.month}月{dt.day}日"

    print(f"🔍 正在获取 {date_cn} 数据...")

    # 获取数据
    crypto = fetch_coingecko()
    fg = fetch_fear_greed()
    gold = fetch_gold_price()
    indices = fetch_yfinance_indices()

    # ── 组装报告 ──
    lines = []
    lines.append(f"# ☀️ FinFlash 快报 — {date_cn} 星期{weekday}")
    lines.append("")
    lines.append("> ⚠️ *免责声明：本报告由 Python 脚本自动生成，仅供信息参考，不构成投资建议。*")
    lines.append("")
    lines.append("> 📭 标注「暂无数据」的板块表示 API 获取失败，可通过 Claude FinFlash 快报补充完整内容。")
    lines.append("")
    lines.append("---")
    lines.append("")

    # ── 1. 大盘指数 ──
    lines.append("## 📊 大盘指数")
    lines.append("")
    if indices:
        lines.append("| 指数 (Index) | 收盘 (Close) | 涨跌 (Change) |")
        lines.append("|-------------|-------------|--------------|")
        for name, data in indices.items():
            price_str = format_price(data.get("price"))
            change_str = format_change(data.get("change_pct"))
            lines.append(f"| {name} | {price_str} | {change_str} |")
    else:
        lines.append("📭 暂无数据（yfinance 获取失败）")
    lines.append("")

    # ── 2. 加密货币 ──
    lines.append("---")
    lines.append("")
    lines.append("## 🪙 加密货币")
    lines.append("")
    if crypto:
        lines.append("| 币种 | 价格 (Price) | 24h 涨跌 |")
        lines.append("|------|-------------|---------|")
        btc_p = format_price(crypto.get("btc_price"), "$")
        btc_c = format_change(crypto.get("btc_change_24h"))
        eth_p = format_price(crypto.get("eth_price"), "$")
        eth_c = format_change(crypto.get("eth_change_24h"))
        lines.append(f"| BTC | {btc_p} | {btc_c} |")
        lines.append(f"| ETH | {eth_p} | {eth_c} |")
        lines.append("")
        if fg is not None:
            lines.append(f"- 🎭 恐惧贪婪指数 (Fear & Greed Index)：**{fg}** — {fear_greed_label(fg)}")
    else:
        lines.append("📭 暂无数据（CoinGecko API 获取失败）")
    lines.append("")

    # ── 3. 大宗商品 ──
    lines.append("---")
    lines.append("")
    lines.append("## 🛢️ 大宗商品")
    lines.append("")
    if gold:
        lines.append(f"- 🥇 黄金 (Gold)：**${gold:,.2f}/oz**")
    else:
        lines.append("- 🥇 黄金：📭 暂无数据")
    lines.append("- 🛢️ 原油 (Crude Oil)：📭 暂无数据（需 API）")
    lines.append("- 🔩 铜 (Copper)：📭 暂无数据（需 API）")
    lines.append("")

    # ── 4-7. 新闻板块 ──
    for section, emoji, note in [
        ("💹 活跃个股 / 板块", "💹", "📭 请通过 Claude FinFlash 快报获取个股和板块数据"),
        ("🌍 全球宏观", "🌍", "📭 请通过 Claude FinFlash 快报获取全球新闻"),
        ("🤖 科技 / AI", "🤖", "📭 请通过 Claude FinFlash 快报获取科技新闻"),
        ("🏠 房地产", "🏠", "📭 请通过 Claude FinFlash 快报获取房地产新闻"),
    ]:
        lines.append("---")
        lines.append("")
        lines.append(f"## {section}")
        lines.append("")
        lines.append(note)
        lines.append("")

    now = datetime.now().strftime("%Y-%m-%d %H:%M")
    lines.append("---")
    lines.append("")
    lines.append(f"> 🤖 *Python 脚本自动生成于 {now} — 完整版请等待 Claude FinFlash 快报推送*")

    return "\n".join(lines)


# ── 主入口 ──────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="FinFlash 快报生成器")
    parser.add_argument(
        "--date",
        default=datetime.now().strftime("%Y-%m-%d"),
        help="日期 YYYY-MM-DD（默认今天）",
    )
    parser.add_argument("--output", help="输出文件路径（默认 reports/YYYY-MM-DD.md）")
    parser.add_argument("--print", action="store_true", help="打印到终端，不保存文件")
    args = parser.parse_args()

    # 验证日期
    try:
        dt = datetime.strptime(args.date, "%Y-%m-%d")
    except ValueError:
        print(f"❌ 日期格式错误: {args.date}，需要 YYYY-MM-DD", file=sys.stderr)
        sys.exit(1)

    # 生成报告
    report = generate_report(args.date)

    # 输出
    if args.print:
        print(report)
    else:
        out_path = Path(args.output) if args.output else REPORTS_DIR / f"{args.date}.md"
        out_path.write_text(report, encoding="utf-8")
        print(f"✅ FinFlash 快报已保存到: {out_path}")
        print(f"📄 共 {len(report)} 字符")


if __name__ == "__main__":
    main()
