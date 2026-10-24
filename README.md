# rclone-directlink

**一句话**：给 `rclone` 的 TelDrive 后端打一个总共 +8 行的补丁——**上传完成的那一刻**就把服务端发回的**稳定直链**打印出来，而不是把它丢掉。

> **EN:** A patched `rclone` build (`v1.75.2-extra-11-g066443b4-directlink`, Windows amd64) on top of [gulp79/rclone-extra](https://github.com/gulp79/rclone-extra) that prints the stable direct link a patched TelDrive server returns in the upload-completion response.

本仓库是 TelDrive 直链方案的**客户端**部分。服务端补丁（签发直链的中间件）与部署步骤在 [teldrive-directlink](https://github.com/h897105167/teldrive-directlink)。

---

## 背景

TelDrive 原生的下载地址是 `/file/<fileId>`，要带会话/授权，不能直接贴给别人。直链方案在服务端加一层签名中间件：上传完成时，响应里多一个 `directUrl` 字段，形如

```
https://direct.example.org/<hmac-token>/<filename>
```

上游 rclone（以及 [gulp79/rclone-extra](https://github.com/gulp79/rclone-extra)）的 `backend/teldrive` 里：

- `api.FileInfo` **没有** `directUrl` 字段 → JSON 解码时这个字段被静默丢弃；
- `completeUpload` 拿到 `FileInfo` 之后只用来刷新对象元数据（`applyFileInfo`），随后就把结构体扔了。

所以想拿到直链，只能事后再去查一次 API。这个补丁就补这两处。

## 与上游的差异（全部改动，+8 行）

| 文件 | 改动 | 行数 |
| --- | --- | --- |
| `backend/teldrive/api/types.go` | `FileInfo` 增加 `DirectUrl`（json tag `directUrl,omitempty`） | +3 |
| `backend/teldrive/upload.go` | `completeUpload` 里 `applyFileInfo` 之后打印直链 | +5 |

完整补丁：[`patches/rclone-extra.diff`](patches/rclone-extra.diff)（1150 B）。

```go
// backend/teldrive/api/types.go
	// DirectUrl is stamped by a TelDrive server that publishes stable direct
	// links on upload completion. Older servers leave the field empty.
	DirectUrl string `json:"directUrl,omitempty"`
```

```go
// backend/teldrive/upload.go — completeUpload()
	o.applyFileInfo(&file)
	// Local patch: a patched TelDrive server returns the stable direct link in
	// the completion response, so print it instead of throwing it away.
	if file.DirectUrl != "" {
		fs.Logf(o, "Direct link: %s", file.DirectUrl)
	}
	return &file, nil
```

设计上刻意保持最小：**不碰任何读写路径**。服务端没打补丁时 `directUrl` 为空，行为与上游完全一致（只是多一个恒为空的字段）。

## 下载

| 资产 | 平台 | 大小 | sha256 |
| --- | --- | --- | --- |
| `rclone-v1.75.2-extra-11-g066443b4-directlink-windows-amd64.exe` | Windows x64 | 84,849,152 B | `76f535201fbfd71a474f157f333ee43fd4ce867bc545485c841b7698e002ac20` |

- 已实测 `rclone version` 输出 `rclone v1.75.2-extra-11-g066443b4-directlink`，`go1.27.2`、`CGO_ENABLED=0` 静态链接。
- exe **没有代码签名**，首次运行可能被 SmartScreen 拦：点「更多信息」→「仍要运行」。介意就按下面的步骤自己编。
- 包内**不含任何配置**。`rclone.conf` 要你自己 `rclone config` 生成；凭证永远不进仓库。

## 用法

```powershell
# 传到 TelDrive 远端（服务端已打 directlink 补丁）
rclone copy .\video.mp4 teldrive:uploads/ -v
```

带 `-v`（INFO 级）时，每传完一个文件就会多一行日志：

```
2026/10/23 13:01:03 INFO  : uploads/video.mp4: Direct link: https://direct.example.org/1f3a.../video.mp4
```

服务端没打补丁、或没配 `TELDRIVE_DIRECTLINK_BASE`，就照旧没有这一行，其它一切不变。

## 从源码构建

需要 Go（本版本用 **go1.27.2**）与 git。

**Windows（PowerShell）**

```powershell
.\scripts\build-windows.ps1            # 产物：out\rclone-windows-amd64.exe
```

**bash / 交叉编译**

```bash
./scripts/build.sh                     # 产物：out/rclone-windows-amd64.exe
```

两个脚本做的是同一件事：

1. 取上游 `gulp79/rclone-extra` 的 `066443b420e185d8795f832d29055174a68b7694`；
2. `git apply patches/rclone-extra.diff`；
3. `CGO_ENABLED=0 GOOS=windows GOARCH=amd64 go build -trimpath -ldflags "-s -w -X github.com/rclone/rclone/fs.Version=v1.75.2-extra-11-g066443b4-directlink"`。

要出别的平台，把 `GOOS`/`GOARCH` 换掉即可（补丁与平台无关）。

## 版本号怎么来的

`fs.Version` 不是 `git describe` 算的，而是构建时用 `-ldflags -X` **直接写死**的：

```
v1.75.2-extra-11-g066443b4-directlink
 └──┬───┘ └────┬────┘ └───┬────┘ └──┬───┘
 上游 rclone   rclone-extra   其 commit    本补丁标记
```

所以同一个二进制在任何机器上 `rclone version` 都报同一串。这也是用它区分「装的是不是打过补丁的那个」最省事的办法。

## 验证记录

- `patches/rclone-extra.diff` 对上游 `gulp79/rclone-extra@066443b4` 的**原始**工作树 `git apply --check` 通过，打完后两个文件的 SHA256 与本机编译时使用的树逐字节一致（见 [`docs/verification.md`](docs/verification.md)）。
- **可复现**：在另一个空目录里用 `scripts/build-windows.ps1` 从头 clone → 打补丁 → 编译，得到的 exe 与 release 里的**大小和 sha256 完全相同**（`-trimpath` + 固定工具链 go1.27.2）。
- 下载后 `Get-FileHash -Algorithm SHA256` 应等于上表的值。

## 已知限制

- 只在 **Windows x64** 上实测过（其它平台的编译路径相同，但未验证）。
- 直链是**服务端**签发的：客户端只负责「显示」。链接的有效期/是否可撤销由服务端策略决定，见 teldrive-directlink 的文档。
- 只改了 `backend/teldrive`，`rclone mount`、`serve` 等其它路径的行为与上游一致。
- 上游 `rclone-extra` 会继续前进；本仓库把构建**钉**在 `066443b4`，不自动跟。

## 相关仓库

| 仓库 | 作用 |
| --- | --- |
| [teldrive-directlink](https://github.com/h897105167/teldrive-directlink) | 服务端：签发直链的 teldrive 补丁、部署脚本、行为规格 |
| [gulp79/rclone-extra](https://github.com/gulp79/rclone-extra) | 上游 rclone fork（TelDrive 增强），本补丁的基线 |
| [rclone](https://github.com/rclone/rclone) | 原始项目 |

## 许可

补丁是 rclone（MIT）源码的两处小改动，随本仓库以 MIT 发布，见 [LICENSE](LICENSE)。
