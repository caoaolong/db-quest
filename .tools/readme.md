# `.tools` 工具说明

本目录提供两个 Node.js 命令行小工具，用于生成测试用文件（关卡素材、磁盘读写等）。需本机已安装 Node.js。

在项目根目录执行。

## 尺寸写法

两个脚本共用同一套尺寸解析（**1024 进制**）：

| 写法 | 含义 |
|------|------|
| `512` | 512 字节（省略单位时默认 `B`） |
| `700B` | 700 字节 |
| `1KB` / `1K` / `1KiB` | 1024 字节 |
| `1.5MB` / `1.5M` | 1.5 × 1024² 字节 |
| `1GB` / `1G` | 1024³ 字节 |

也支持 `TB` / `TiB` 等更大单位。可用 `-h` / `--help` 查看用法。

---

## `create-zero-file.js`

生成指定大小的**全 0 二进制文件**。

```bash
node .tools/create-zero-file.js <大小> [输出路径]
```

- **大小**：字节数，或带单位（见上）
- **输出路径**：省略时在当前目录生成 `zero_<大小>.bin`

示例：

```bash
node .tools/create-zero-file.js 1KB
node .tools/create-zero-file.js 1.5MB ./assets/test/zero_1_5mb.bin
```

---

## `create-random-text-file.js`

生成指定长度的**随机字母数字文本文件**（字符集：`a-z`、`A-Z`、`0-9`）。

```bash
node .tools/create-random-text-file.js <长度> [输出路径]
```

- **长度**：字符数，或带单位（单位按字节/字符数理解，与上表相同）
- **输出路径**：省略时在当前目录生成 `random_<长度>.txt`

示例：

```bash
node .tools/create-random-text-file.js 512
node .tools/create-random-text-file.js 1KB ./assets/test/random_1kb.txt
```
