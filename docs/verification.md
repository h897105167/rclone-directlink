# 验证记录

本文件记录 release 里那个 exe 是怎么被证明「等于 上游 `066443b4` + `patches/rclone-extra.diff`」的。
所有命令都在 Windows 11 (10.0.26200) + `go1.27.2 windows/amd64` 上跑过。

## 1. 补丁对上游原始树可干净应用

```powershell
git init _verify_clone
git -C _verify_clone remote add origin https://github.com/gulp79/rclone-extra.git
git -C _verify_clone fetch --depth 1 origin 066443b420e185d8795f832d29055174a68b7694
git -C _verify_clone checkout -q FETCH_HEAD
git -C _verify_clone apply --check patches/rclone-extra.diff
```

结果：

```
HEAD=066443b420e185d8795f832d29055174a68b7694
apply --check exit=0
```

即：补丁没有依赖本地未提交的其它改动，任何人在原始上游提交上都能直接套用。

## 2. 打上补丁后的文件与「实际拿去编译的树」逐字节一致

`git apply` 之后，与编译时使用的工作树比对 SHA256：

```
backend/teldrive/api/types.go   patched=2F0EA7203493  local=2F0EA7203493  identical=True
backend/teldrive/upload.go      patched=68A902F16678  local=68A902F16678  identical=True
```

`git status --porcelain` 只列出这两个文件：

```
 M backend/teldrive/api/types.go
 M backend/teldrive/upload.go
```

## 3. 反向可还原

把编译树里的改动导出成 diff 后，`git apply --check --reverse` 返回 0 —— 说明工作树里除了这份补丁**没有夹带别的东西**。

## 4. 二进制

| 项 | 值 |
| --- | --- |
| 文件 | `rclone-windows-amd64.exe` |
| 大小 | 84,849,152 B |
| sha256 | `76f535201fbfd71a474f157f333ee43fd4ce867bc545485c841b7698e002ac20` |

```
rclone v1.75.2-extra-11-g066443b4-directlink
- os/version: Microsoft Windows 11 Pro 25H2 (64 bit)
- os/type: windows
- os/arch: amd64
- go/version: go1.27.2
- go/linking: static
- go/tags: none
```

## 5. 可复现构建（实测 bit-for-bit 一致）

用仓库里发布的脚本，在**另一个空目录**里从头 clone、打补丁、编译：

```powershell
.\scripts\build-windows.ps1 -WorkDir ..\_build_test -OutDir ..\_build_test\out
```

输出与 release 里的文件逐字节相同：

```
size   : 84,849,152 B
sha256 : 76f535201fbfd71a474f157f333ee43fd4ce867bc545485c841b7698e002ac20
version: rclone v1.75.2-extra-11-g066443b4-directlink
```

之所以能一致：`-trimpath` 去掉了绝对路径、`CGO_ENABLED=0` 静态链接、版本号由 `-ldflags -X` 写死、工具链固定在 go1.27.2。你用自己的机器编译，只要 Go 版本相同，得到的 sha256 应当也能对得上。

## 6. 未验证项

- 其它平台（linux/arm64 等）的编译只验证了脚本能跑到 `go build`，没有实机跑过。
- `DirectUrl` 端到端（真机 teldrive + 真上传）的日志输出，验证点在对端仓库 [teldrive-directlink](https://github.com/h897105167/teldrive-directlink)。
