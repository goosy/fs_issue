# issues：问题与决定记录系统规格（草案）

本文件是草案，英文版为 `spec.md`，两者内容保持同步。现有 `create-issue.ps1` 的规格见 `spec-create-issue.md`（英文）。

## 0. 定位

### 动机

本方案的目的，是在项目的源文件中包含一套轻量的 issue 处理机制，并让它成为 issue 的唯一数据源（source of truth），使项目文件本身更完整。

GitHub 等平台的 issue 功能虽然完善，但 issue 存放在网站上，离开平台就无法访问，项目本身的文件中也看不到它们：克隆下来的仓库里看不出存在哪些问题、做过哪些裁定，迁移平台时还需要另行导出。把 issue 作为文件放进仓库，issue 就随代码一起被克隆、分支、合并和审阅，并与代码共享同一份 git 历史；平台或第三方工具只作为可选的展示层和讨论场所。

### 定位：问题与决定的记录

本系统定位为**问题与决定的记录**，而不是 issue 跟踪系统：

- GitHub 等平台继续负责收集问题、讨论、通知和指派；本系统不取代这些功能。
- 仓库中的 issue 文件负责保存权威的结论：问题是什么，提议了什么，裁定是什么。
- 这与 ADR（Architecture Decision Records）以及 Rust RFC、Python PEP 等做法一致：讨论在别处进行，仓库中只保留定稿的内容。
- 附加工具 `issue-github`（第 10 节）是两者之间的桥梁。

### 概要

一个轻量但完整的、基于文件和命令行的问题与决定记录系统：

- issue 以 Markdown 文件的形式存放在项目的 `issues/` 目录中，随代码一起纳入 git。**文件就是唯一的数据源**，不存在另一个数据库，也不存在“渲染产物”。
- 命令行程序 `issue`（Rust 实现）负责新建、列出、查看、修改和校验 issue，并以 JSON 形式向第三方提供结构化数据。
- issue 文件只记录**当前**的表述；表述随时间的变化由 git 历史体现。
- GUI、WebUI、讨论本身及其原始存档都由第三方实现，不在本系统内。
- 附加工具 `issue-github`（第 10 节）从 GitHub 导入 issue，并把 GitHub 上的讨论同步到 `## 讨论经过`；三段正文仍由人或 AI 助手改写。它是独立的程序，`issue` 本身绝不访问网络。

现有的 `create-issue.ps1` 保持不变，作为 `issue new` 的过渡实现，其行为以 `spec-create-issue.md` 为准。`issue` 完成后再决定是否让它退役。原计划的 `create-issue.sh` 不再需要：`issue` 同时支持 Linux。

### 设计取舍

- **为什么不用单个 JSON/YAML 数据库文件**：所有 issue 放在一个文件里，并行分支修改不同 issue 时容易产生合并冲突；正文是多行自由文本，放进 JSON 后 diff 难以审阅；如果再从数据库渲染 md，人直接改 md 的内容会在下次渲染时丢失。
- **为什么每个 issue 用 md 而不是 yaml 文件**：YAML 同样是为人读写而设计的，但 md 能被 GitHub 等平台和本地的 Markdown 阅读软件直接渲染成文档，YAML 没有这样的渲染支持。正文本身就是 Markdown，放在 md 文件中也最自然。
- **为什么 md 仍然便于结构化**：结构化字段全部放在 front matter，格式是严格限定的 YAML 子集，解析成本很低；正文只按固定的三个二级标题切分。第三方不需要自己解析，可以直接调用 `issue ... --json`。

## 1. 术语

- **项目根目录**：当前工作目录，或 `-C <dir>` 指定的目录。不向上搜索，不调用 git。
- **issues 目录**：`<项目根目录>/issues/`。
- **issue 文件**：issues 目录下符合第 3.2 节命名规则的 `.md` 文件。
- **项目模板**：`issues/template.md`，不是 issue 文件。
- **三段正文**：problem（问题描述）、proposal（解决提案）、decision（裁定）。
- **关闭状态**：`fixed`、`rejected`、`wontfix`。**活动状态**：`open`、`accepted`。

## 2. 内容原则

- problem、proposal、decision 三段合起来必须反映**最终**的决定：问题最终被如何理解，提议了什么，裁定是什么。
- 被否决的提案可以保留在 issue 文件中，例如在 proposal 中列出曾考虑的方案及否决理由，前提是三段内容读下来能清楚得出最终的决定，不会把被否决的方案误读为现行方案。
- 讨论过程、评论、投票不写进三段正文。它们的存档属于第三方系统；第三方以 id 引用 issue。
- 三段正文之后可以有附加段落（第 3.4 节），例如 `issue-github` 写入并同步的 `## 讨论经过`。`issue` 不读取、不校验、也不修改附加段落的内容；是否保留由作者决定。
- 被否决（`rejected`）或不予处理（`wontfix`）的 issue 同样保留，不删除。
- 表述改变时直接改写对应段落，不按时间顺序追加“更新：……”之类的记录；每一版表述保留在 git 历史中。

## 3. 存储格式

### 3.1 编码

- UTF-8 无 BOM，LF 换行。`issue` 写出的文件始终满足这一点。
- 读取时容忍 CRLF（按 LF 处理），但 `check` 将 CR 和 BOM 报告为错误。

### 3.2 文件名

- `issues/<id>-<slug>.md`。`id` 见第 4 节；`slug` 规则同 `spec-create-issue.md`：`^[a-z0-9]+(-[a-z0-9]+)*$`，最长 60 字符。
- slug 只用于文件列表的可读性，可以改名；id 是身份，永不改变。
- issues 目录中除 issue 文件和 `template.md` 外，不应有其他条目；`check` 对其他条目给出警告，其他命令忽略它们。

### 3.3 front matter

文件以 front matter 开头：第一行为 `---`，直到下一行 `---`。其中可以出现的键和写法如下（`labels`、`remote` 和三个标题声明可以省略，其余必填）。键的顺序不作规定；模板和工具写出时采用下列推荐顺序：

```
---
id: <id>
opened: <opened>
title: <title>
status: <status>
fixed_in: [<commit>, ...]
labels: [<label>, ...]
remote: <remote>
problem_title: <text>
proposal_title: <text>
decision_title: <text>
---
```

- 键名一律使用标识符形式（小写字母、数字和下划线）。每个键一行，不允许重复的键、其他键、空行或注释行。键的顺序不影响解析。
- 每行的值之后可以有 YAML 行尾注释（空白后接 `#` 直到行尾）。`issue` 修改某个值时保留该行的注释。
- front matter 必须是合法 YAML，且只使用下面规定的子集，以便第三方用任意 YAML 解析器得到同样的结果：
  - `id`：8 个字符，字母表见第 4 节。
  - `opened`：`YYYY-MM-DDTHH:MM:SS.fffZ`，UTC，恰好三位小数。
  - `title`：单行文本，可以为空。读取时接受 YAML 普通标量或双引号字符串（转义规则同 JSON）。写出时，满足以下全部条件就写成普通标量，否则写成双引号字符串：首字符不是 `` -?:,[]{}#&*!|>'"%@` `` 之一；不含 `: ` 和 ` #`；首尾没有空白。不支持单引号字符串。
  - `status`：`open`、`accepted`、`fixed`、`rejected`、`wontfix` 之一。
  - `fixed_in`：流式列表，元素为 7 到 40 位小写十六进制提交 ID，不重复。空列表写作 `[]`。
  - `labels`：流式列表，元素符合 slug 规则，不重复，保持写入顺序。
  - `remote`：该 issue 在远程平台上的对应条目，值为该条目的完整 URL：`https://github.com/<owner>/<repo>/issues/<number>`，例如 `https://github.com/serialport/node-serialport/issues/3149`。目前只支持 GitHub 这一个 remote，协议必须是 `https`，主机必须是 `github.com`，末尾不带 `/`、查询参数或 `#` 片段。`<owner>` 由 ASCII 字母、数字和连字符组成；`<repo>` 由 ASCII 字母、数字、`.`、`_`、`-` 组成；`<number>` 为不以 0 开头的正整数。同一个 remote 不能出现在两个 issue 文件中，比较 `<owner>` 和 `<repo>` 时不区分大小写。`remote` 只是数据，`issue` 从不访问它。
  - `problem_title`、`proposal_title`、`decision_title`：三段正文的标题文字（`## ` 之后的部分），写法同 `title`，但不能为空。三者必须同时出现或同时省略；省略时分别取缺省值 `Problem`、`Proposal`、`Decision`。三者不能彼此相同，也不能是 `讨论经过`（第 10.5 节）。
- 没有 `updated`、`closed` 之类的时间字段：这些信息由 git 历史提供。

### 3.4 正文

- front matter 之后是一个空行，然后是三段正文，之后可以有**附加段落**。
- 文件中的前三个二级标题（以 `## ` 开头的行）必须依次恰为 `## <problem_title>`、`## <proposal_title>`、`## <decision_title>`，否则报错。比较时取 `## ` 之后、去掉首尾空白的部分，区分大小写，完全相等才算匹配。
- 标题文字由声明字段决定，因此与语种无关：中文项目声明 `problem_title: 问题描述`，正文中就写 `## 问题描述`；未声明时正文写 `## Problem`。
- 所有有用的内容都必须归入三段正文。在三段之前或之间插入其他二级标题（例如 `## 背景`）属于结构错误；这类内容应写成相应段落下的三级标题，例如 Problem 下的 `### 背景`。
- 第一个二级标题之前只允许空行。三段正文的内容中不允许出现一级标题；三级及以下标题可以使用。围栏代码块（` ``` ` 或 `~~~`）内的行不视为标题。
- 三段正文各自的内容 = 该标题之后到下一个二级标题（或文件末尾）之间的行，去掉首尾空行。内容可以为空。
- **附加段落**：从第四个二级标题所在行起，直到文件末尾的全部内容。`issue` 把它当作不透明的文本：不解析其中的标题和结构，不校验其内容，不出现在 JSON 输出中，`modi` 逐字节保留它。第 3.1 节的编码规则仍然适用于整个文件。

### 3.5 示例

```
---
id: ggkpa773
opened: 2026-10-18T00:03:31.121Z
title: Start fails when one server cannot bind
status: accepted        # open | accepted | fixed | rejected | wontfix
fixed_in: []            # commit IDs, backfilled at version commit time
labels: [startup]
---

## Problem

When one of several servers fails to bind, the others keep running.

## Proposal

Stop all started servers and report every failure.

## Decision

Accepted: implement the proposal in 0.4.
```

使用中文标题的文件，front matter 中声明三个标题：

```
---
id: 0vdz2x70
opened: 2026-10-17T23:58:07.000Z
title: 块的 offset 没有要求偶数
status: open
fixed_in: []
problem_title: 问题描述
proposal_title: 解决提案
decision_title: 裁定
---

## 问题描述

## 解决提案

## 裁定
```

## 4. id 与 opened

id 算法、`opened` 的格式、日期参数的解析、冲突处理与 bump 规则，以及全部参考测试向量，都与 `spec-create-issue.md` 第 1、3、5 节完全一致，`issue` 必须通过同一组向量。要点：

- `ms` = 打开时间的 Unix epoch 毫秒；对其 ASCII 十进制文本取 SHA-256，取前 40 位，按 5 位一组映射到 `0123456789abcdefghjkmnpqrstvwxyz`，得到 8 个字符。
- id 必须能由 `opened` 推导，且等于文件名的前 8 个字符。这是 `check` 的核心完整性规则。
- id 冲突以 issues 目录中已有的 id 为准，与 slug 无关。

## 5. 模板

- 新建 issue 时，有 `issues/template.md` 就用它，否则用内置默认模板。默认模板的内容即本仓库的 `default-template.md`（英文），在编译时嵌入 `issue`，运行时不依赖任何外部文件。
- 模板的读取、占位符 `{{id}}` / `{{opened}}` 的替换，以及 `opened` 字段的强制填写，规则同 `spec-create-issue.md` 第 4 节。
- 生成的内容必须通过 `check` 的全部错误检查，否则不写入任何文件、退出码 1，消息中指出模板的问题。
- 项目需要其他语种或不同的标题文字时，自行提供对应的 `issues/template.md`，并在其 front matter 中写出三个标题声明字段，与模板正文的标题一致。默认模板使用缺省值，不写这三个字段。
- 模板可以在三段之后附带附加段落。

## 6. 命令行

### 6.1 通用约定

```
issue [-C <dir>] <command> [args]
```

- 所有命令都只读写 issues 目录，绝不调用 git，绝不访问网络。
- 退出码：`0` 成功；`1` 运行时错误，或 `check` 发现错误；`2` 用法错误（未知命令或选项、参数缺失或不合规）。用法错误时不写入任何内容。
- 错误信息和警告写到 stderr，每条一行，英文。正常输出写到 stdout。
- 参数必须是合法的 UTF-8，否则属于用法错误。
- **issue 引用 `<ref>`**：完整 id、id 的唯一前缀（至少 2 个字符）、issue 文件名，或 issue 文件路径。找不到或前缀不唯一时退出码 1，并在消息中列出所有候选文件名。

### 6.2 `issue new <slug> [date] [--title <text>] [--label <label>]... [--json]`

- `slug`、`date`、id、冲突处理和模板，规则同第 4、5 节及 `spec-create-issue.md`。
- `--title` 写入 `title`；`--label` 可重复，写入 `labels`，没有标签时不写这一行。
- stdout：所创建的文件名；带 `--json` 时输出第 7 节的单个 issue 对象。

### 6.3 `issue list [--status <status>]... [--label <label>]... [--all] [--json]`

- 默认只列活动状态（`open`、`accepted`）的 issue；`--all` 列出全部；`--status` 可重复，按并集过滤，并覆盖默认过滤。
- `--label` 可重复，要求同时具有所有指定标签。
- 按 `opened` 升序排列。
- 文本输出每个 issue 一行：`<id>  <status>  <opened 的日期部分>  <title>`，列之间对齐；`title` 为空时显示 `(untitled)`。
- 无法解析的 issue 文件在 stderr 中逐个报告并跳过，其余照常输出，最后退出码为 1。

### 6.4 `issue show <ref> [--section <name>] [--json]`

- 默认原样输出 issue 文件的全部内容，包括附加段落。
- `--section problem|proposal|decision`：只输出该段落的内容（第 3.4 节的定义），不含标题。
- `--json`：输出第 7 节的单个 issue 对象，包含三段正文。

### 6.5 `issue modi <ref> [选项]...`

> **待定**：`modi` 的规格（对 front matter 各字段、三段正文以及附加段落的修改）将单独讨论。本节内容暂不作为定稿依据。

修改一个 issue。至少需要一个选项，否则属于用法错误。

| 选项 | 作用 |
| :- | :- |
| `--title <text>` | 替换 `title` |
| `--status <status>` | 替换 `status`；不强制状态迁移顺序 |
| `--slug <slug>` | 修改文件名中的 slug，id 不变 |
| `--fixed-in-add <commit>`，`--fixed-in-remove <commit>` | 增删 `fixed_in` 元素，可重复；增加已有元素、删除不存在的元素都不算错误 |
| `--label-add <label>`，`--label-remove <label>` | 增删 `labels` 元素，可重复；列表为空时删除 `labels` 行，首次添加时新增该行（不带注释） |
| `--remote <remote>`，`--remote-clear` | 设置或删除 `remote`；首次设置时新增该行（不带注释） |
| `--problem <source>`，`--proposal <source>`，`--decision <source>` | 用新内容**整体替换**该段落 |

- `<source>`：`-` 表示从 stdin 读取，`@<path>` 表示从文件读取（UTF-8），其他值按字面文本处理。内容中的 CRLF 规范化为 LF，去掉首尾空行。传空字符串即清空该段落。新内容中不得含一级或二级标题，否则属于用法错误。附加段落不受影响。
- `id` 和 `opened` 不可修改。
- 目标文件必须先通过 `check` 的全部错误检查，否则拒绝修改（退出码 1，列出错误），以免在格式损坏的文件上继续写入。
- 只改动需要改动的行；未修改的行和附加段落逐字节保持不变；修改值时保留行尾注释；标题行不变。
- 修改是原子的：所有选项要么全部生效，要么都不生效。先写入 issues 目录中的临时文件，再替换原文件；改 slug 时，新文件名已存在则报错，退出码 1，不做任何修改。
- stdout：修改后的文件名（改 slug 后为新文件名）。

### 6.6 `issue check [<ref>...] [--json]`

校验指定的 issue，不指定时校验 issues 目录中的全部 issue 和 `template.md`。

错误：

- 编码：有 BOM 或 CR。
- 文件名不符合第 3.2 节；不同文件的 id 重复。
- front matter 结构不符合第 3.3 节：缺键、重复的键、未知的键、值不合规；三个标题声明只出现了一部分，或取值为空、彼此相同、为 `讨论经过`。
- id 不能由 `opened` 推导，或与文件名的前 8 个字符不一致。
- `remote` 格式不合规，或同一个 remote 出现在多个文件中。
- 正文结构不符合第 3.4 节，包括前三个二级标题与声明的标题文字不一致、顺序不对，或在三段之前、之间插入了其他二级标题。错误信息中提示改用三级标题。
- `template.md` 在替换占位符后生成的内容不合规。

警告（不影响退出码）：

- `title` 为空。
- 状态为 `accepted` 或关闭状态，但 decision 为空。
- 状态不是 `fixed`，但 `fixed_in` 不为空。
- issues 目录中有 issue 文件和 `template.md` 之外的条目。

输出：每条发现一行，`<file>: error|warning: <message>`。有任何错误时退出码 1，否则为 0。适合放进 pre-commit 钩子或 CI。

## 7. JSON 输出

这是第三方读取数据的稳定接口。字段名采用 snake_case，新增字段不视为破坏性变更，删除或改变字段语义时递增 `schema_version`。

单个 issue 对象：

```json
{
  "id": "ggkpa773",
  "slug": "start-partial-failure",
  "file": "issues/ggkpa773-start-partial-failure.md",
  "opened": "2026-10-18T00:03:31.121Z",
  "title": "Start fails when one server cannot bind",
  "status": "accepted",
  "fixed_in": [],
  "labels": ["startup"],
  "remote": "https://github.com/example/server/issues/42",
  "section_titles": {
    "problem": "Problem",
    "proposal": "Proposal",
    "decision": "Decision"
  },
  "sections": {
    "problem": "When one of several servers fails to bind, the others keep running.",
    "proposal": "Stop all started servers and report every failure.",
    "decision": "Accepted: implement the proposal in 0.4."
  }
}
```

- `file` 是相对项目根目录的路径，使用 `/` 分隔。`labels` 行省略时为 `[]`；`remote` 行省略时为 `null`；未声明标题时，`section_titles` 为缺省的英文值。
- `show --json` / `new --json`：`{"schema_version": 1, "issue": <对象>}`。
- `list --json`：`{"schema_version": 1, "issues": [<对象>...]}`，对象中不含 `sections`。
- `check --json`：`{"schema_version": 1, "findings": [{"file": ..., "level": "error"|"warning", "message": ...}]}`。
- 输出为 UTF-8，不转义非 ASCII 字符。

## 8. 与 git 的关系

- **权威版本**：以默认分支（如 `main`）上的 issue 文件为准。其他分支上对 issue 文件的修改只是提议，合并到默认分支后才生效。第三方读取权威数据时，应基于默认分支。
- `issue` 只处理当前工作目录中的文件，不知道也不判断所在分支；在哪个分支上运行由使用者负责。
- `issue` 从不调用 git，也从不提交。何时提交由人或第三方决定。
- 每一个提交中的 issue 文件，就是该 issue 在那个时间点的阶段性表述。查看一个 issue 的演变：`git log --follow -p -- issues/<id>-<slug>.md`。改 slug 是文件重命名，git 的重命名检测能跟踪；id 是稳定的检索键。
- 修改表述时，建议让 issue 文件的改动独立成提交，或与实现它的代码放在同一个提交中，使历史保持可读。提交信息的格式不在本规格范围内。
- `fixed_in` 的回填由版本提交流程使用 `issue modi --fixed-in-add` 完成。

## 9. 与第三方的边界

- 第三方（GUI、WebUI、讨论系统）通过 `issue ... --json` 读取数据，也可以按第 3 节直接读取文件。
- 第三方修改 issue 时，应调用 `issue new` / `issue modi`；如果直接写文件，写出的文件必须通过 `issue check`。
- 讨论、评论及其存档保存在第三方系统中，以 issue 的 id 关联，不写入三段正文。
- 当讨论形成新的结论时，由第三方或人把结论改写进相应段落，并提交到 git。

## 10. 附加工具：GitHub 导入与讨论同步

### 10.1 定位

- 独立的可执行文件 `issue-github`，与 `issue` 在同一个 Cargo 工作区中。
- `import`：从 GitHub 读取目标仓库的 issue，在当前项目的 issues 目录中生成对应的 issue 文件，并写入 `remote`。
- `sync`：按 `remote` 重新读取 GitHub 上的讨论，更新 `## 讨论经过`。
- 分工：**工具提供讨论经过的同步，三段正文仍由人或 AI 助手改写。**`import` 只在新建文件时写入 front matter；`sync` 从不改动 front matter 和三段正文。
- 只调用 GitHub 的只读 REST API，绝不修改 GitHub 上的任何内容。目前只支持 GitHub。

### 10.2 通用约定

- 认证：从环境变量 `GITHUB_TOKEN` 读取令牌。令牌可以不设置（公开仓库可以匿名读取，但速率限制更低）。令牌绝不通过命令行参数传入，也绝不出现在任何输出或文件中。
- GitHub 的 issues API 同时返回 pull request，全部跳过。
- 每个文件独立地原子写入。网络错误、API 错误或达到速率限制时退出码为 1，并在 stderr 中说明中断位置；已写入的文件保留，重新运行即可继续。
- 退出码同第 6.1 节。`--dry-run`：只输出将要创建或修改的文件名，不写入任何内容。

### 10.3 `issue-github [-C <dir>] import <owner>/<repo> [--state open|closed|all] [--number <n>]... [--dry-run]`

- `--state`：按 GitHub 上的状态过滤，默认 `all`。`--number`：可重复，只导入指定编号的 issue。
- 已有 issue 文件的 `remote` 指向同一个 GitHub issue 时，跳过该 issue，并在 stderr 中说明。
- stdout：每创建一个文件输出一行文件名。

字段映射：

| GitHub | issue 文件 |
| :- | :- |
| `created_at` | `opened`。GitHub 只精确到秒，毫秒为 0 |
| `title` | `title` |
| `state` / `state_reason` | `open` → `open`；`closed` 且原因为 `completed` 或未给出 → `fixed`；`not_planned` → `wontfix`；`duplicate` → `rejected` |
| `labels` | `labels`。名称按下述 slug 转换规则转换；转换后为空的标签丢弃，并在 stderr 中警告 |
| 仓库与编号 | `remote`：API 返回的 issue 页面 URL（`html_url`），形如 `https://github.com/<owner>/<repo>/issues/<number>` |
| issue 正文和全部评论 | 附加段落 `## 讨论经过`（第 10.5 节） |

- `fixed_in` 为 `[]`。
- slug 转换规则：转为小写，ASCII 字母和数字以外的字符替换为连字符，合并连续的连字符，去掉首尾的连字符；超过 60 个字符时在连字符处截断。由 `title` 转换得到的 slug 为空时（例如标题全是中文），使用 `gh-<number>`。
- 三段正文由模板（第 5 节）生成，保持模板原样，**不填写内容**。
- id 由 `opened` 计算。按 GitHub issue 编号升序处理；id 与已有文件冲突时，按 bump 规则加 1 ms 后重试。

### 10.4 `issue-github [-C <dir>] sync [<ref>...] [--dry-run]`

- 不指定 `<ref>` 时，同步所有带 `remote` 的 issue；指定时只同步这些 issue，其中没有 `remote` 的报错。
- 对每个 issue，重新读取 GitHub 上的 issue 正文和全部评论，**整体重新生成** `## 讨论经过`：
  - 文件中没有 `## 讨论经过` 时，追加到文件末尾。
  - 已有时，替换从该标题行起到文件末尾的全部内容。
- 文件的其余部分（front matter、三段正文、`## 讨论经过` 之前的其他附加段落）逐字节保持不变。
- 每次都整体重新生成，不需要记录同步进度；GitHub 上评论的新增、编辑和删除都会反映出来。增量部分由 git diff 体现：重新生成后与上一版相同的内容不会产生差异。
- 生成结果与现有内容完全相同时，不写入文件。
- GitHub 上的标题、状态、标签与本地不一致时，只在 stderr 中提示，不修改本地字段：本地文件才是权威来源。
- 目标文件必须先通过 `issue check` 的全部错误检查，否则跳过并报错。某个 issue 在 GitHub 上已不存在或无权访问时，报错并继续处理其余 issue，最后退出码为 1。
- stdout：每修改一个文件输出一行文件名。

### 10.5 `## 讨论经过` 段落

标题文字固定为 `## 讨论经过`，与模板的语种无关。该段落归 `issue-github` 管理，必须位于文件末尾；作者在其中所做的修改，会在下次 `sync` 时被覆盖。

```
## 讨论经过

### @<login> 2026-10-18T00:03:31Z

<issue 正文>

### @<login> 2026-10-19T08:00:00Z

<评论正文>
```

- 第一条是 issue 本身的正文，其后按时间顺序列出全部评论。正文原样保留，只把 CRLF 规范化为 LF；正文为空时写 `（空）`。
- 不包含标签变更、指派、关闭等事件，也不下载附件；附件和图片仍以指向 GitHub 的链接形式保留在正文中。
- `sync` 定位 `## 讨论经过` 的方法：在三段正文之后，第一条内容恰为 `## 讨论经过` 的行。

### 10.6 使用流程

1. `issue-github import` 导入。生成的文件通过 `issue check` 的全部错误检查；三段正文为空，会产生警告。
2. 人或 AI 助手阅读 `## 讨论经过`，把最终的决定写进三段正文，例如 `issue modi <ref> --problem @problem.md --decision @decision.md`。
3. GitHub 上有新的讨论时，运行 `issue-github sync`，再由人或 AI 助手据此改写三段正文。
4. 每一步的改动都通过 git diff 审阅后再提交；合并到默认分支后才成为权威版本（第 8 节）。
5. 不再需要同步的 issue，可以用 `issue modi --remote-clear` 解除关联；是否保留 `## 讨论经过` 由作者决定。`issue` 从不读取、校验或修改它。

## 11. 实现约束

- Rust stable，生成两个可执行文件 `issue` 和 `issue-github`，支持 Windows 11 和 Linux，运行时不依赖外部程序。文件格式、id、模板等逻辑放在两者共用的库 crate 中。
- 依赖保持最少：命令行解析、SHA-256、JSON 序列化各用一个常见的 crate。`issue-github` 另外允许使用一个 HTTP 客户端和一个 TLS 实现；`issue` 不依赖它们。front matter 按第 3.3 节的子集手工解析，不引入 YAML 库，以保证修改时注释和未改动的行逐字节保留。
- 全程 UTF-8，不经过任何代码页。
- 遵循 `AGENTS.md`：英文标识符和注释，UTF-8 无 BOM，LF 换行。
- 解析、id 计算、校验和修改逻辑放在库模块中，可以脱离进程直接做单元测试；`main` 只负责参数解析、输入输出和退出码。

## 12. 测试

- 单元测试：第 4 节的全部参考向量；front matter 子集的解析与写出（包括 title 的引号规则和行尾注释的保留）；正文切分（包括围栏代码块中的 `## `）；每一条 `check` 规则的正例和反例；`modi` 的每个选项。
- 集成测试放在 `tests/` 目录中，每个测试使用全新的临时项目目录，通过子进程运行编译出的 `issue`，检查 stdout、stderr、退出码和文件字节。至少覆盖：
  - `new` 的全部行为，与 `spec-create-issue.md` 第 7 节的检查项对应。
  - `list` 的过滤、排序，以及遇到损坏文件时的行为。
  - `show` 的三种输出。
  - `modi` 的原子性：任何一个选项失败时，文件逐字节不变；改 slug 遇到冲突时也是如此。
  - `modi` 之后的文件仍然通过 `check`，未修改的行逐字节不变。
  - `check` 对每一类错误和警告的报告，以及退出码。
  - 用 `create-issue.ps1` 创建的文件能通过 `issue check`。
- 标题声明：缺省和声明两种情况都能正确解析；部分声明、取值不合规、标题与声明不一致、调换顺序、插入其他二级标题时，`check` 报错；键的顺序不同但内容相同的文件，解析结果相同。
- 附加段落：`show` 原样输出；`modi` 修改三段正文和 front matter 后，附加段落逐字节不变；附加段落中的任意内容（包括一级、二级标题和 `---` 行）都不影响 `check`。
- `issue-github`：GitHub API 访问抽象为接口，测试使用录制好的 JSON 响应，不访问真实网络。`import` 至少覆盖字段映射、分页、跳过 pull request、slug 和标签的转换（包括转换结果为空的情况）、`remote` 相同时跳过、id 冲突时 bump。`sync` 至少覆盖：追加与替换 `## 讨论经过`；`## 讨论经过` 之外的内容逐字节不变；内容不变时不写文件；评论的新增、编辑、删除；远程字段不一致时只提示；远程 issue 不存在时继续处理其余文件。两者都要覆盖 `--dry-run`、中途失败时已写文件的保留，以及令牌不出现在任何输出中；生成或修改后的文件必须通过 `issue check`。
- 测试不调用 git，不访问网络，不修改测试目录之外的任何文件。

## 13. 交付物

- 项目根目录下的 Cargo 工作区：共用的库 crate，以及 `issue` 和 `issue-github` 两个可执行文件，各自带测试。
- `default-template.md` 保留在项目根目录，由 `issue` 在编译时嵌入。
- `create-issue.ps1` 及其测试 `test/create-issue.tests.ps1` 保持不变。

## 14. 范围外

GUI 和 WebUI；讨论、评论、通知；用户、权限和指派人；优先级、里程碑、issue 之间的依赖；全文搜索；删除命令（用 `git rm`，或把状态改为 `rejected` / `wontfix`）；任何 git 操作；回写到 GitHub；同步 `## 讨论经过` 以外的任何内容（标题、状态、标签）；GitHub 以外的 remote；导入 pull request；命令行消息的本地化。

## 15. 待定问题

定稿前需要确认：

1. 程序名用 `issue` 是否合适。
2. `labels` 是否保留。
3. `list` 默认只显示活动状态，还是显示全部。
4. id 前缀的最小长度（目前为 2）。
5. front matter 中出现未知键时，按错误处理（目前的设计）还是按警告处理以便扩展。
6. 是否需要 `issue edit <ref>`：用 `$EDITOR` 打开文件，保存后自动运行 `check`。
7. 附加工具的名称 `issue-github` 是否合适，还是作为 `issue` 之外的另一个仓库发布。
8. GitHub 上 `closed` 且原因为 `completed` 的 issue 映射为 `fixed` 是否合适：它在 GitHub 上被关闭，但在本仓库中未必有对应的 `fixed_in`。
9. `## 讨论经过` 的标题文字是否固定为中文，还是允许通过选项指定。
10. `sync` 发现 GitHub 上的状态与本地不一致时，是否需要一个选项把它写回本地，还是始终只提示。
