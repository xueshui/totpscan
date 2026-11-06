# TOTP 认证器 · 商店页素材与文案（zh_CN / en / zh_TW / ja）

> **界面语言说明：扩展界面已支持四种语言（简体中文、English、繁體中文、日本語），可在设置页「外观 → 语言」中切换，默认跟随浏览器语言。** 四套素材右侧与设置页内都是对应语言的真实扩展界面（真实渲染，未做 P 图或伪造翻译）；画布左侧的标题、副标题与卖点同样按语言本地化。商店页面可以如实说明已支持多语言界面。
>
> 名称、简短说明与界面文案均取自 `extension/_locales/<lang>/messages.json`，与浏览器实际显示一致。语言回退规则：`zh-CN` / `zh-Hans` → 简体；`zh-TW` / `zh-HK` / `zh-Hant` → 繁體；`ja*` → 日本語；`en*` → English；其余（含 ko、ar、ru 等）→ 简体中文。
> 每套素材位于 `extension/store-v2/<lang>/`，共 7 张：`screenshot-1.png` ~ `screenshot-4.png`（1280×800）、`store-logo-300.png`（300×300）、`promo-small-440x280.png`（440×280）、`promo-marquee-1400x560.png`（1400×560）。
> 本文案目录由独立任务产出，未改动 `extension/` 下任何扩展代码、manifest、`_locales` 或 `dist` 包。

---

## zh_CN（简体中文）

**扩展名**：`TOTP 认证器`（8 字符，取自 `_locales/zh_CN`）

**简短说明**（58 字符，上限 132）：

> 本地计算标准 TOTP 动态码，支持页面二维码识别与扫码增强登录；密钥仅加密保存在本机，仅向账户固化地址提交验证码。

**详细描述**（681 字符，商店最小要求 250）：

TOTP 认证器是一款完全在本机运行的双重验证工具，遵循标准 TOTP（RFC 6238 / RFC 4226）。支持 SHA1、SHA256、SHA512 三种 HMAC 算法，6 位或 8 位动态码，30 秒或 60 秒周期；可通过 otpauth 链接、手动输入密钥或网页上的二维码添加账户，弹窗里直接显示动态码与倒计时环，点击即可填入当前输入框或复制。

扫码增强登录面向支持签名绑定二维码的网站：识别登录页二维码后，只有在本地存在账户、签发方与提交地址完全一致的增强型账户时，才会向该账户自己固化的地址提交一次性验证码。地址或账户有任何不匹配，都会在本机直接中止，不发出任何网络请求；增强型账户不展示动态码，也不允许复制或导出。

所有密钥在写入本机前都用 AES-GCM-256 加密，主密钥是不可导出的 WebCrypto 密钥，保存在扩展专属的 IndexedDB。没有账号体系、没有云同步、没有开发者服务器、没有遥测与广告，不收集、不出售、不上传任何个人数据；唯一的出站请求就是向已绑定的固化地址提交一次性验证码。

界面提供浅色、深色、跟随系统三档模式与自定义主题色，账户可以拖动排序、置顶，并添加仅保存在本机、不会上传也不会写入日志的备注。备份有三条独立路径：明文 JSON、口令加密 JSON（PBKDF2-SHA256 600000 次迭代 + AES-256-GCM）和 authenticator.txt；导入前会先预览，重复项可以选择跳过或覆盖，兼容 otpauth 链接与 Google Authenticator 迁移二维码。

**搜索词**（7 个，每个 ≤30 字符；独立词语 7 个，上限 21）：

`TOTP`、`2FA`、`双重验证`、`验证码`、`扫码登录`、`认证器`、`离线`

---

## en（English）

**Extension name**: `TOTP Authenticator`（18 characters, from `_locales/en`）

**Short description**（129 characters, limit 132）:

> Local TOTP codes with on-page QR scanning. Secrets stay encrypted on this device; codes go only to each account's fixed endpoint.

**Detailed description**（1759 characters, store minimum 250）:

TOTP Authenticator is a two-factor tool that runs entirely on your device and follows standard TOTP (RFC 6238 / RFC 4226). It supports SHA1, SHA256 and SHA512, 6 or 8 digit verification codes, and 30 or 60 second periods. Add accounts from an otpauth link, a typed secret, or a QR code on a page; the popup shows each verification code with a live countdown ring, ready to fill into the current field or copy.

Scan-enhanced QR sign-in is for sites that issue signed binding QR codes. When a QR code is detected on the login page, a one-time code is submitted only if a local enhanced account matches the account, issuer and submit URL exactly. If anything does not match, the extension stops locally and sends no request at all. Enhanced accounts never display a readable code and cannot be copied or exported.

Every secret is encrypted with AES-GCM-256 before it is written to disk, and the master key is a non-extractable WebCrypto key kept in the extension's own IndexedDB. There is no account system, no cloud sync, no developer server, no telemetry and no advertising: nothing is collected, sold or uploaded. The only outbound request is the one-time code posted to the fixed endpoint already bound to your account.

The interface offers light, dark and follow-system modes plus a custom accent color. Accounts can be dragged into order, pinned, and annotated with a note that stays on this device, is never uploaded and never written to logs. Backups come in three independent forms: plain JSON, password-encrypted JSON (PBKDF2-SHA256 with 600000 iterations plus AES-256-GCM) and authenticator.txt. Imports are previewed first, with a choice to skip or overwrite duplicates, and otpauth links and Google Authenticator migration QR codes are supported.

**Search terms**（7 terms, each ≤30 characters; 9 independent words, limit 21）:

`TOTP`、`2FA`、`authenticator`、`verification code`、`QR sign-in`、`offline`、`two-factor`

---

## zh_TW（繁體中文）

**擴充功能名稱**：`TOTP 驗證器`（8 字元，取自 `_locales/zh_TW`）

**簡短說明**（61 字元，上限 132）：

> 在本機計算標準 TOTP 動態碼，支援網頁 QR 碼辨識與掃碼強化登入；金鑰僅加密儲存在本機，僅向帳戶固定位址提交驗證碼。

**詳細描述**（697 字元，商店最小要求 250）：

TOTP 驗證器是一款完全在本機運作的雙重驗證工具，遵循標準 TOTP（RFC 6238 / RFC 4226）。支援 SHA1、SHA256、SHA512 三種 HMAC 演算法，6 位或 8 位驗證碼，30 秒或 60 秒週期；可透過 otpauth 連結、手動輸入金鑰或網頁上的 QR 碼新增帳戶，彈出視窗直接顯示驗證碼與倒數環，點一下即可填入目前輸入框或複製。

掃碼強化登入適用於提供簽章綁定 QR 碼的網站：在登入頁辨識 QR 碼後，只有本機存在帳戶、簽發方與提交位址完全相符的強化型帳戶時，才會向該帳戶自己固定的位址提交一次性驗證碼。帳戶或位址只要有任何不符，都會在本機直接終止，不發出任何網路請求；強化型帳戶不顯示驗證碼，也不允許複製或匯出。

所有金鑰在寫入本機前都會以 AES-GCM-256 加密，主金鑰為不可匯出的 WebCrypto 金鑰，存放在擴充功能專屬的 IndexedDB。沒有帳號系統、沒有雲端同步、沒有開發者伺服器、沒有遙測與廣告，不蒐集、不出售、不上傳任何個人資料；唯一的對外請求就是向已綁定的固定位址提交一次性驗證碼。

介面提供淺色、深色、跟隨系統三檔模式與自訂主題色，帳戶可以拖曳排序、置頂，並加上僅保存在本機、不會上傳也不會寫入日誌的備註。備份有三條獨立路徑：明文 JSON、口令加密 JSON（PBKDF2-SHA256 600000 次迭代 + AES-256-GCM）與 authenticator.txt；匯入前會先預覽，重複項目可選擇略過或覆寫，並相容 otpauth 連結與 Google Authenticator 遷移 QR 碼。

**搜尋詞**（7 個，每個 ≤30 字元；獨立詞語 7 個，上限 21）：

`TOTP`、`2FA`、`雙重驗證`、`驗證碼`、`掃碼登入`、`驗證器`、`離線`

---

## ja（日本語）

**拡張機能名**：`TOTP 認証アプリ`（10 文字、`_locales/ja` より）

**短い説明**（75 文字、上限 132）：

> 標準 TOTP コードを端末内で計算。ページ上の QR コード読み取りとスキャン強化ログインに対応し、シークレットは暗号化して端末内のみに保存します。

**詳細説明**（975 文字、ストアの最小要件 250）：

TOTP 認証アプリは、標準 TOTP（RFC 6238 / RFC 4226）に準拠し、すべてを端末内で処理する二段階認証ツールです。SHA1 / SHA256 / SHA512 の 3 種類の HMAC アルゴリズム、6 桁または 8 桁のワンタイムパスワード、30 秒 / 60 秒の周期に対応します。otpauth リンク、シークレットの手入力、ページ上の QR コードからアカウントを追加でき、ポップアップにはワンタイムパスワードとカウントダウンリングが表示され、クリックで入力欄への挿入またはコピーができます。

スキャン強化ログインは、署名付きバインディング QR コードを発行するサイト向けです。ログインページで QR コードを検出した後、アカウント・発行者・送信先 URL がすべて完全に一致する強化アカウントが端末内にある場合に限り、そのアカウント自身の固定エンドポイントへワンタイムパスワードを送信します。一致しない点が一つでもあれば端末内で中止し、ネットワークリクエストを一切送信しません。強化アカウントはコードを表示せず、コピーもエクスポートもできません。

シークレットは保存前に AES-GCM-256 で暗号化され、マスターキーはエクスポート不可の WebCrypto キーとして拡張機能専用の IndexedDB に保管されます。アカウント登録もクラウド同期も開発者サーバーもなく、テレメトリーや広告もありません。個人データの収集・販売・送信は行わず、外部への通信は、ユーザーが紐付けた固定エンドポイントへのワンタイムパスワード送信のみです。

ライト / ダーク / システム連動の 3 モードとアクセントカラーの変更に対応し、アカウントはドラッグで並べ替え、ピン留め、メモの追加ができます。メモは端末内だけに保存され、送信もログ出力もされません。バックアップは平文 JSON、パスワード暗号化 JSON（PBKDF2-SHA256 600000 回 + AES-256-GCM）、authenticator.txt の 3 通りで、読み込み前にはプレビューが表示され、重複はスキップか上書きを選べます。otpauth リンクと Google Authenticator の移行用 QR コードにも対応しています。

**検索キーワード**（7 件、各 30 文字以内、独立語 8 個、上限 21）：

`TOTP`、`2FA`、`二段階認証`、`ワンタイムパスワード`、`QR ログイン`、`認証アプリ`、`オフライン`
