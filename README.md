# ⚡ FinFlash

**核心文件**：[`prompt.md`](prompt.md) — 一份自包含的 AI 指令，发给任意支持联网搜索的 AI 即可自动生成当日财经快报。

## 🌐 在线版

**🔗 [https://yutnskoxm-commits.github.io/morning-brief/](https://yutnskoxm-commits.github.io/morning-brief/)**

打开即看，每天自动更新。可分享到微信给朋友使用。

## 🚀 使用方式

### 主要用法：发送 prompt.md 给任意 AI

1. 打开 [`prompt.md`](prompt.md)
2. 全文复制
3. 粘贴到任意支持联网搜索的 AI 模型（Claude、ChatGPT、Gemini 等）
4. AI 自动搜索 7 大板块最新信息 → 汇总输出快报

> 💡 这就是整个项目的核心逻辑——prompt.md 就是「FinFlash App」的源代码。

### 辅助用法

| 方式 | 说明 |
|------|------|
| Claude 定时任务 | 已在 Claude Code 配置工作日 8:03 AM 自动触发（重启后需重新设置） |
| Python 脚本 | `python3 morning_report.py` 生成基础版（仅量化数据，不含新闻摘要） |

## 📊 覆盖的 7 大板块

| # | 板块 | 内容 |
|---|------|------|
| 1 | 📊 大盘指数 | 上证、恒生、标普500、纳斯达克 |
| 2 | 🪙 加密货币 | BTC/ETH 价格、恐惧贪婪指数、行业动态 |
| 3 | 💹 活跃个股/板块 | 美股 + A股/港股 热门个股与板块 |
| 4 | 🌍 全球宏观 | 国际重大新闻、地缘政治、央行政策 |
| 5 | 🛢️ 大宗商品 | 黄金、原油、铜价格走势 |
| 6 | 🤖 科技/AI | AI 行业动态、科技公司新闻 |
| 7 | 🏠 房地产 | 中国房地产政策与市场数据 |

## 📁 文件说明

```
FinFlash/
├── prompt.md           # 🔑 核心：AI 指令文件（发给任意模型即可）
├── index.html          # 🌐 网页版（GitHub Pages 部署）
├── reports/            # 生成的报告存档
│   ├── YYYY-MM-DD.json  # 网页版数据源
│   └── YYYY-MM-DD.md    # Markdown 版
├── morning_report.py   # Python 回退脚本（仅量化数据）
└── README.md           # 本文件
```

## 🔧 自定义

直接编辑 [`prompt.md`](prompt.md) 即可：
- 增删板块（加一个搜索章节 + 对应的模板段落）
- 调整搜索关键词
- 修改语言偏好
- 改输出格式
