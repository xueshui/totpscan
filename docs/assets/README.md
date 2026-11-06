# README 视觉素材

本目录提供 README 用的一套视觉素材，中文、英文各一套，文件名一一对应。

- `zh/`：简体中文；`en/`：英文。
- 全部为 **2 倍 PNG**（按 2× 像素密度导出，README 中按原始逻辑宽度显示即可保持清晰）。
- 不再使用 SVG：GitHub 对 SVG 的渲染/消毒行为存在差异，PNG 不受影响，能稳定显示。
- 深色底统一使用 `#090D14` → `#111927` 渐变，主色 `#5B8DFF`（蓝）、辅色 `#34D5A4`（薄荷绿），强调色 `#F0B45E`（琥珀）。
- 示例域名仅使用 `example.com` / `dkn.example.com` / `qq.example.com`，路径统一为 `/totp/v1/verify`，账户为 `alice` / `bob` / `carol` 占位示例，不含真实域名、密钥或账号。
- 四张界面图是**示意渲染**，不是真实截图；图内右上角已标注「示意渲染 · 非真实截图」/ "Illustrative rendering · not a screenshot"。

## 文件清单

| 文件（zh / en 同名） | 像素尺寸（2×） | 显示尺寸 | 用途 | 建议插入位置 |
| --- | --- | --- | --- | --- |
| `banner.png` | 2560 × 800 | 1280 × 400 | 主视觉：项目名、一句话定位、六端图标 | README 顶部，标题与徽章下方、正文简介之前 |
| `workflow.png` | 2560 × 1600 | 1280 × 800 | 工作流程：首次绑定 → 日常登录 → 计算并提交，强调提交目标只来自本地钉住地址 | 「协议一句话」或「工作原理」小节之后 |
| `platforms.png` | 2560 × 1440 | 1280 × 720 | 六端能力总览：协议、服务端、扩展、Android、iOS、鸿蒙 | 「六端在哪」小节，可作为表格上方的总览图（与表格内容重复，二选一即可） |
| `ui-android.png` | 2240 × 1520 | 1120 × 760 | Android 账户列表 + 扫码页示意 | 「界面示意」小节 |
| `ui-ios.png` | 2240 × 1520 | 1120 × 760 | iOS 账户列表 + 扫码页示意 | 同上 |
| `ui-harmony.png` | 2240 × 1520 | 1120 × 760 | 鸿蒙账户列表 + 扫码页示意 | 同上 |
| `ui-extension.png` | 2240 × 1520 | 1120 × 760 | 浏览器扩展弹窗 + 页内扫码示意 | 同上 |

> PNG 已做无损尺寸校验与 256 色调色板压缩，单张约 220–440 KB。所有图按 2× 导出，GitHub 在普通内容宽度下会自动缩放，文字仍然清晰。

## 中文 README 引用片段

以下路径以仓库根目录为基准，直接粘到根目录的 README 即可。

```markdown
![totpscan：扫到的二维码只用来核对地址，动态码只发往绑定时钉住的地址](docs/assets/zh/banner.png)

## 工作流程

![工作流程：绑定阶段钉住 dom 与 path，登录时只向该地址提交动态码](docs/assets/zh/workflow.png)

## 六端一览

![六端能力总览：协议、参考服务端、浏览器扩展、Android、iOS、鸿蒙](docs/assets/zh/platforms.png)

## 界面示意

**Android** · 账户列表与扫码页

![Android 账户列表与扫码页示意](docs/assets/zh/ui-android.png)

**iOS** · 账户列表与扫码页

![iOS 账户列表与扫码页示意](docs/assets/zh/ui-ios.png)

**鸿蒙** · 账户列表与扫码页

![鸿蒙账户列表与扫码页示意](docs/assets/zh/ui-harmony.png)

**浏览器扩展** · 弹窗账户列表与页内扫码

![浏览器扩展弹窗与页内扫码示意](docs/assets/zh/ui-extension.png)

> 上图为示意渲染，非真实截图；实际界面以各端构建为准。
```

## 英文 README 引用片段

```markdown
![totpscan: the scanned QR code is only a check; codes are submitted only to the address pinned at binding](docs/assets/en/banner.png)

## How it works

![Workflow: binding pins dom and path; sign-in posts only to that endpoint](docs/assets/en/workflow.png)

## Six targets

![Six targets: protocol, reference server, browser extension, Android, iOS and HarmonyOS](docs/assets/en/platforms.png)

## UI preview

**Android** · accounts and scanner

![Android accounts and scanner mockup](docs/assets/en/ui-android.png)

**iOS** · accounts and scanner

![iOS accounts and scanner mockup](docs/assets/en/ui-ios.png)

**HarmonyOS** · accounts and scanner

![HarmonyOS accounts and scanner mockup](docs/assets/en/ui-harmony.png)

**Extension** · popup accounts and on-page scan

![Extension popup and on-page scan mockup](docs/assets/en/ui-extension.png)

> These are illustrative mockups, not actual screenshots. Real builds may differ.
```

## 对应关系

- 中文 README 使用 `docs/assets/zh/` 下全部 7 个 PNG；英文 README（或英文段落）使用 `docs/assets/en/` 下同名 7 个 PNG。
- `banner.png` 对应各语言 README 的第一屏；`workflow.png` 对应流程说明；`platforms.png` 对应端/目录总览；四张 `ui-*.png` 对应界面示意。
- 两套素材的文字各自撰写，不是逐字翻译：中文用「动态码 / 扫码登录 / 钉住地址」，英文用 "verification code / sign-in / pinned endpoint"。

## 修改建议

- 本目录以 2× PNG 作为最终交付格式；如需改文案或配色，请重新导出同等逻辑宽度（banner 1280、流程图 1280、总览 1280、界面图 1120）的 2× PNG 后整体替换，不要直接放大已有位图。
- 改主题色：主色 `#5B8DFF`、辅色 `#34D5A4`，其余为中性色。
- 不要在图内加入新域名或真实账号；新增示例请继续使用 `example.com` 系列。
