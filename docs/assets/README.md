# README 视觉素材

本目录提供 README 用的一套视觉素材，中文、英文各一套，文件名一一对应。

- `zh/`：简体中文；`en/`：英文。
- 全部为 SVG（`viewBox` 与 `width` / `height` 一致），无位图、无外部字体、无远程资源、无脚本。
- 深色底统一使用 `#090D14` → `#111927` 渐变，主色 `#5B8DFF`（蓝）、辅色 `#34D5A4`（薄荷绿），强调色 `#F0B45E`（琥珀）。
- 示例域名仅使用 `example.com` / `dkn.example.com` / `qq.example.com`，路径统一为 `/totp/v1/verify`，账户为 `alice` / `bob` / `carol` 占位示例，不含真实域名、密钥或账号。
- 四张界面图是**示意渲染**，不是真实截图；图内右上角已标注「示意渲染 · 非真实截图」/ "Illustrative rendering · not a screenshot"。

## 文件清单

| 文件（zh / en 同名） | 尺寸 | 用途 | 建议插入位置 |
| --- | --- | --- | --- |
| `banner.svg` | 1280 × 400 | 主视觉：项目名、一句话定位、六端图标 | README 顶部，标题与徽章下方、正文简介之前 |
| `workflow.svg` | 1280 × 800 | 工作流程：首次绑定 → 日常登录 → 计算并提交，强调提交目标只来自本地钉住地址 | 「协议一句话」或「工作原理」小节之后 |
| `platforms.svg` | 1280 × 720 | 六端能力总览：协议、服务端、扩展、Android、iOS、鸿蒙 | 「六端在哪」小节，可作为表格上方的总览图（与表格内容重复，二选一即可） |
| `ui-android.svg` | 1120 × 760 | Android 账户列表 + 扫码页示意 | 「界面示意」小节 2 × 2 网格 |
| `ui-ios.svg` | 1120 × 760 | iOS 账户列表 + 扫码页示意 | 同上 |
| `ui-harmony.svg` | 1120 × 760 | 鸿蒙账户列表 + 扫码页示意 | 同上 |
| `ui-extension.svg` | 1120 × 760 | 浏览器扩展弹窗 + 页内扫码示意 | 同上 |

> 全部为矢量图，任意缩放不失真；尺寸按 README 常规内容宽度设计，无需额外提供 PNG。

## 中文 README 引用片段

以下路径以仓库根目录为基准，直接粘到根目录的 README 即可。

```markdown
<p align="center">
  <img src="docs/assets/zh/banner.svg" alt="totpscan：扫到的二维码只用来核对地址，动态码只发往绑定时钉住的地址" width="100%">
</p>

## 工作流程

![工作流程：绑定阶段钉住 dom 与 path，登录时只向该地址提交动态码](docs/assets/zh/workflow.svg)

## 六端一览

![六端能力总览：协议、参考服务端、浏览器扩展、Android、iOS、鸿蒙](docs/assets/zh/platforms.svg)

## 界面示意

<table>
  <tr>
    <td width="50%"><img src="docs/assets/zh/ui-android.svg" alt="Android 账户列表与扫码页示意"></td>
    <td width="50%"><img src="docs/assets/zh/ui-ios.svg" alt="iOS 账户列表与扫码页示意"></td>
  </tr>
  <tr>
    <td width="50%"><img src="docs/assets/zh/ui-harmony.svg" alt="鸿蒙账户列表与扫码页示意"></td>
    <td width="50%"><img src="docs/assets/zh/ui-extension.svg" alt="浏览器扩展弹窗与页内扫码示意"></td>
  </tr>
</table>

> 上图为示意渲染，非真实截图；实际界面以各端构建为准。
```

## 英文 README 引用片段

```markdown
<p align="center">
  <img src="docs/assets/en/banner.svg" alt="totpscan: the scanned QR code is only a check; codes are submitted only to the address pinned at binding" width="100%">
</p>

## How it works

![Workflow: binding pins dom and path; sign-in posts only to that endpoint](docs/assets/en/workflow.svg)

## Six targets

![Six targets: protocol, reference server, browser extension, Android, iOS and HarmonyOS](docs/assets/en/platforms.svg)

## UI preview

<table>
  <tr>
    <td width="50%"><img src="docs/assets/en/ui-android.svg" alt="Android accounts and scanner mockup"></td>
    <td width="50%"><img src="docs/assets/en/ui-ios.svg" alt="iOS accounts and scanner mockup"></td>
  </tr>
  <tr>
    <td width="50%"><img src="docs/assets/en/ui-harmony.svg" alt="HarmonyOS accounts and scanner mockup"></td>
    <td width="50%"><img src="docs/assets/en/ui-extension.svg" alt="Extension popup and on-page scan mockup"></td>
  </tr>
</table>

> These are illustrative mockups, not actual screenshots. Real builds may differ.
```

## 对应关系

- 中文 README 使用 `docs/assets/zh/` 下全部 7 个文件；英文 README（或英文段落）使用 `docs/assets/en/` 下同名 7 个文件。
- `banner.svg` 对应各语言 README 的第一屏；`workflow.svg` 对应流程说明；`platforms.svg` 对应端/目录总览；四张 `ui-*.svg` 对应界面示意。
- 两套素材的文字各自撰写，不是逐字翻译：中文用「动态码 / 扫码登录 / 钉住地址」，英文用 "verification code / sign-in / pinned endpoint"。

## 修改建议

- 改主题色：在 SVG 中替换 `#5B8DFF`（主色）与 `#34D5A4`（辅色）即可，其余为中性色。
- 改文案：直接编辑 SVG 内的 `<text>` 文本；修改后请同时检查中英文两套，保持文件名与内容结构一致。
- 不要在图内加入新域名或真实账号；新增示例请继续使用 `example.com` 系列。
