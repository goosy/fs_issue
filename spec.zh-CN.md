# 任务：全局 `create-issue` 命令（PowerShell）及自测试

构建一个供放入系统 `PATH` 的小型命令。它在项目根目录执行时，应在该项目的 `./issues/` 下创建一个 issue 文件｡

- 运行平台为 Windows 11，脚本只能使用 PowerShell 和 .NET 自带的能力。
- 运行平台为 linux 时, 脚本使用通用的库来完成｡

本项目要同时提供一个不依赖外部模块的测试脚本。

## 1. 命令行

```
create-issue <slug> [date]
```

- 以 `create-issue.ps1` 实现，经系统 `PATH`（直接或通过跳板脚本）以 `create-issue <slug> [date]` 调用。
- 测试可以显式以 `pwsh -NoProfile -File <path-to-create-issue.ps1> <slug> [date]` 调用脚本，但行为不得依赖安装脚本的目录；唯一例外是从该目录读取默认模板（第 4 节）。
- `slug` 为必填，且永远是第一个参数。它是便于文件列表阅读的简短小写 ASCII 描述。规则：`^[a-z0-9]+(-[a-z0-9]+)*$`，最长 60 个字符。其余情形（大写、下划线、空格、非 ASCII、首尾或连续连字符、空串、过长）一律拒绝，绝不静默修正。纯数字的 slug 合法；第一个参数永远不会被解释为日期。
- `date` 为可选的第二个参数，纯数字、无分隔符，按 **UTC** 解释。允许长度：

  | 长度 | 格式 | 缺省字段 |
  | :- | :- | :- |
  | 8 | `YYYYMMDD` | 时间为 `00:00:00.000` |
  | 12 | `YYYYMMDDHHMM` | 秒和毫秒为 0 |
  | 14 | `YYYYMMDDHHMMSS` | 毫秒为 0 |
  | 17 | `YYYYMMDDHHMMSSfff` | 无 |

- 未传入 `date` 时，打开时间为当前 UTC 时间，截断到毫秒。
- 无效输入（slug 缺失或不合规；`date` 中含非数字、其他长度、不可能的日期如月份 13 或 `20250230`、小时 24、早于 1970 的年份；多于两个参数）属于用法错误：不得写入任何内容（包括 `issues/` 目录），向 stderr 输出一行消息，退出码为 2。
- 成功时：仅向 stdout 输出所创建的文件名（例如 `ggkpa773-short-slug.md`），退出码为 0。运行时错误（无法写入、显式日期发生冲突）输出到 stderr，退出码为 1。

## 2. 文件位置

- 文件创建在**当前工作目录**下的 `./issues/<id>-<slug>.md`。本命令将当前目录视为项目根目录；不得写入脚本目录、搜索仓库根目录或调用 git。
- 当 `./issues/` 不存在时创建它。这是本命令唯一可以创建的项目内目录。
- 绝不覆盖已有文件。必须使用独占创建语义（`[System.IO.FileMode]::CreateNew`）；针对已有文件的 `IOException` 必须视为冲突。

## 3. ID

`id` 是打开时间的 8 字符摘要，应使相近时间创建的 issue 也具有完全不同的前缀。slug 不参与 id 的计算。

算法必须完全如下：

1. `ms` = 打开瞬间（UTC）的 Unix epoch 毫秒整数。
2. 输入字节 = `ms` 的 ASCII 十进制文本，无填充、无分隔符（如 `1792281811121`）。
3. 摘要 = 这些字节的 SHA-256；取前 5 字节（40 位），按大端解释为整数。
4. 将 40 位从最高位起分为八组 5 位；每组映射到以下字母表（小写 Crockford base32，移除 `i l o u`）：

   `0123456789abcdefghjkmnpqrstvwxyz`

5. 拼接为 8 个字符。

`opened` 字段必须以 UTC ISO-8601 写入，恰好三位小数且以 `Z` 结尾：`2026-10-18T00:03:31.121Z`。`id` 必须能由 `opened` 推导；这是后续工具会检查的完整性规则。

### 冲突处理

冲突的定义：`./issues/` 中已存在以 `<id>-` 开头并以 `.md` 结尾的文件（slug 为任意值，包括正在创建的 slug），或存在名为 `<id>.md` 的文件。id 才是身份，换一个 slug 不能避开冲突。`template.md` 不是 issue 文件，永远不算冲突。

- 传入显式 `date` 且发生冲突：报错、退出码 1，消息中包含已存在的文件名，不得改变任何内容。
- 未传入 `date` 且发生冲突：给打开时间加 1 ms，重新计算 id 后重试。最多 1000 次，之后以退出码 1 失败。

## 4. 文件内容与模板

项目内模板为当前工作目录下的 `./issues/template.md`。它存在时，复制其内容至新 issue，并替换 `{{id}}` 和 `{{opened}}`。

若 `./issues/template.md` 不存在，使用默认模板 `default-template.md`。它与 `create-issue.ps1` 位于同一目录（通过 `$PSScriptRoot` 定位，绝不通过当前目录），是普通 Markdown 文件，UTF-8 无 BOM、LF 换行，读取时显式指定 UTF-8 编码，绝不经过代码页解读；它不内嵌于脚本。默认模板使用英文；项目若需要其他语种或其他章节，自行提供对应语种的 `./issues/template.md`。需要它而它不存在时属于运行时错误：退出码 1，消息中写出缺失的文件，且不写入任何内容（包括 `issues/` 目录）。`./issues/template.md` 存在时不需要 `default-template.md`。

模板（项目模板或默认模板）按 UTF-8 读取，将 CRLF 规范化为 LF，替换 `{{id}}` 与 `{{opened}}`，再以 UTF-8 **无 BOM**、仅 LF 的形式写出。`template.md` 不是 issue 文件，命令不得修改它。

无论模板是否写了 `{{opened}}`，`opened` 字段都必须填写。替换占位符之后，若内容以 front matter 块开头（首行为 `---`，直到下一行 `---`），且该块中有以 `opened:` 开头的行，则将第一条这样的行改为 `opened: <opened>`，填入换算后的时间。该行末尾的 YAML 注释（空白后接 `#` 直到行尾）保留。值为 `{{opened}}`、为空或为其他内容时均如此处理。front matter 之外的行绝不改动；front matter 中没有 `opened:` 行时，也不新增。

`default-template.md` 的内容（完全一致）：

```
---
id: {{id}}
opened: {{opened}}
title:
status: open        # open | accepted | fixed | rejected | wontfix
fixed-in: []        # commit IDs, backfilled at version commit time
---

## Problem

## Proposal

## Decision
```

slug 不是标题：它只出现在文件名中，绝不写入文件内容。

## 5. 参考测试向量

以下值由独立 Python 实现计算。PowerShell 结果必须逐项完全一致；若不一致，PowerShell 代码有误，而不是此表有误。

| epoch ms | opened | id |
| -: | :- | :- |
| 0 | 1970-01-01T00:00:00.000Z | `bzpepsqz` |
| 1 | 1970-01-01T00:00:00.001Z | `de3b4wzz` |
| 1792281811121 | 2026-10-18T00:03:31.121Z | `ggkpa773` |
| 1792281811122 | 2026-10-18T00:03:31.122Z | `kymnq2en` |
| 1792281811123 | 2026-10-18T00:03:31.123Z | `ae16cpvt` |
| 1792281812121 | 2026-10-18T00:03:32.121Z | `m5s8m0xw` |
| 1792281871121 | 2026-10-18T00:04:31.121Z | `3q0vprjn` |

日期参数：

| 参数 | opened | id |
| :- | :- | :- |
| `20261018` | 2026-10-18T00:00:00.000Z | `jazq3ynk` |
| `202610180823` | 2026-10-18T08:23:00.000Z | `mz0rpmrq` |
| `20261018082311` | 2026-10-18T08:23:11.000Z | `amck341k` |
| `20261018082311121` | 2026-10-18T08:23:11.121Z | `tv5eqvx6` |
| `20240229` | 2024-02-29T00:00:00.000Z | `85gyraxj` |
| `19700101` | 1970-01-01T00:00:00.000Z | `bzpepsqz` |

无效 `date`（接在合法 slug 之后使用；必须退出码 2 且不创建任何文件）：`2026101`（7 位）、`2026101808231`（13 位）、`20251301`、`20250230`、`20261018240000`、`abc`、`20261018x`、`2026-10-18`、`""`（空字符串）。

无效 slug（必须退出码 2 且不创建任何文件）：完全没有参数、`""`、`Fix-Bug`、`fix_bug`、`fix bug`、`-fix`、`fix-`、`fix--bug`、含非 ASCII 字符的 slug、61 个字符的 slug。合法 slug：`a`、`fix-bug`、`x2`、`20261018`、恰好 60 个字符的 slug。第三个参数同样无效。

## 6. 约束

- 必须不作修改地运行于 PowerShell 7+（`pwsh`）和 Windows PowerShell 5.1（`powershell`）。避免使用 5.1 中缺少的 API（例如 `SHA256.HashData`；应使用 `SHA256.Create().ComputeHash`）。
- 脚本文件只含 ASCII、UTF-8 无 BOM、LF 换行。Windows PowerShell 5.1 按系统代码页读取无 BOM 的脚本，只含 ASCII 才能保证它与 `pwsh` 解析结果一致。非 ASCII 文本（例如其他语种的标题）放在项目的 `./issues/template.md` 中，绝不写入脚本。
- 不得使用模块、外部工具、网络、git 调用、Pester；不得修改执行策略或任何机器设置。
- 组织脚本以使逻辑无需启动子进程即可测试：必须具备以下函数：(a) 校验 slug，(b) 将日期参数解析为 epoch 毫秒，(c) 根据 epoch 毫秒计算 id，(d) 格式化 `opened`，(e) 按给定 slug、打开时间和允许 bump 标记创建文件。
- 仅在脚本被执行时运行命令行入口，而非 dot-source 时（`. ./create-issue.ps1`）；用 `$MyInvocation.InvocationName` 守卫。
- 遵循 `AGENTS.md` 的命名规则：标识符采用 snake_case，常量采用 UPPER_SNAKE_CASE，即便这与 PowerShell 的 Verb-Noun 约定不同。

## 7. 测试

`create-issue.tests.ps1` 是纯脚本，带一个极小断言帮助函数，不使用 Pester。它 dot-source `create-issue.ps1`，在全新的临时目录中工作、结束后清理；每项失败输出一行和汇总；仅当所有检查通过时退出码为 0。至少覆盖：

1. 第 5 节所有 id 向量（函数级）。
2. 所有合法与非法 slug、所有日期参数向量和无效日期（函数级）；并通过子进程确认非法情形的退出码为 2 且未创建 `issues/` 目录。
3. 从临时项目目录经子进程（`pwsh`，以及存在时的 `powershell`）进行端到端测试，使用 slug 和显式日期：恰好创建一个 `issues/<id>-<slug>.md`；stdout 恰为文件名；退出码 0；front matter 中的 `id` 等于文件名的前 8 个字符；从 `opened` 重新计算 id 得到相同值；有 `status: open`、三个标题；字节无 BOM 和 CR；脚本自身目录没有新增内容。
4. 使用同一显式日期、不同 slug 执行两次：第二次退出码为 1，stderr 中包含第一个文件名，不创建任何文件，且第一个文件字节不变。
5. 不传 date：创建一个文件，`opened` 距当前 UTC 时间不超过 5 秒，id 与 `opened` 匹配。
6. bump 规则（函数级）：预创建 ms `M` 对应的 `issues/<id>-other.md`，用新的 slug 并允许 bump 调用创建函数；结果为 `M + 1` 对应的文件，原文件不变。不允许 bump 时必须失败。
7. 脚本文件仅含 ASCII、无 BOM、无 CR；`default-template.md` 无 BOM、无 CR。
8. 已有的无关项目文件绝不被修改。
9. 模板选择：不存在 `issues/template.md` 时，issue 使用与 `default-template.md` 完全一致的内容，且该内容与第 4 节一致（与测试中写出的期望值比对，而非从该文件读取）；将 `create-issue.ps1` 单独复制到其他目录时，没有项目模板则退出码 1、stderr 中写出 `default-template.md` 且不创建任何内容，有项目模板则成功；存在带有明显不同 UTF-8 内容及两个占位符的 `issues/template.md` 时，创建的 issue 使用该内容并替换占位符，且 `template.md` 本身不变。项目模板 front matter 中的 `opened:` 未写 `{{opened}}` 时（值为空，以及值为其他内容并带注释），创建的 issue 中 `opened:` 行为换算后的时间且保留注释；front matter 之外的 `opened:` 行不变。

## 8. 交付物

在项目根目录中提供两个文件：

- `create-issue.ps1`
- `create-issue.sh`

默认模板 `default-template.md` 放在项目根目录，与 `create-issue.ps1` 同目录。

测试脚本 `create-issue.tests.ps1` 放在项目根目录下的 `test/` 目录中，从其上级目录定位 `create-issue.ps1`。

`issue-template.md` 不再是交付物：项目可选地提供 `./issues/template.md`，`default-template.md` 提供后备模板。完成后，以 `pwsh` 运行测试脚本；如存在 `powershell`，也以它运行，并报告实际结果。若 Windows PowerShell 5.1 不可用，应说明这一点，不得声称它通过。

测试文件单独在 test 目录下

## 9. 范围外

`list` 命令、id 前缀解析、根据标题生成 slug、重命名 slug、校验已有 issue 文件、状态变更、回填 `fixed-in`、git 操作，以及编辑技能或 `AGENTS.md`，均不在范围内。
