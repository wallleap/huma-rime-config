# huma-rime-config — 虎码 + 小鹤双拼 Rime 配置

基于虎码官方秃码方案深度定制的全平台 Rime 输入法配置集合

仓库地址：<https://github.com/wallleap/huma-rime-config>

## Project

- 纯配置仓库（无构建步骤）：YAML 配置 + Lua 插件 + 词库，复制到各平台 Rime 用户目录后“重新部署”即生效。
- 四个核心方案：`tiger`（虎码・单字）、`tigress`（虎码・含词，带自动造词）、`tiger_sentence`（虎码・整句）、`flypy`（小鹤双拼），入口为 `*.schema.yaml`，方案补丁为同名 `.custom.yaml`
- 前端配置：`squirrel`（macOS）、`weasel`（Windows）、`*.trime`（Android）、`hamster`（iOS）、`space`/`themes`（HarmonyOS 超越）

## Commands

- 无 build/test，改配置后在输入法客户端重新部署生效。
- `bash bin/lint.sh` — 校验格式：YAML 配置（js-yaml）、Lua 插件（luaparse）、dict 词库（Tab 列校验），首次运行自动 `npm install` 依赖；`--strict` 时额外检查 `themes/` 下 YAML（俢改完 yaml、lua、dict 之后必需运行）
- `bash bin/sync_dicts.sh` — 从官方仓库同步词典到 `dicts/` 与根目录，有变更时自动 `git commit` + `git push`（勿手动改这些词典文件）；同步后自动调用 `gen_core2022.sh` 生成字集 Lua 数据
- `bash bin/gen_core2022.sh` — 从 `dicts/core2022.dict.yaml` 生成 `lua/data/core2022/data.lua`（hash set，供 `core2022_filter.lua` O(1) 查询）
- `bash bin/download_gram.sh` — 下载万象模型 `wanxiang-lts-zh-hans.gram` 到仓库根目录、虎码整句模型到 models 目录

## Architecture

- `*.schema.yaml` — 输入方案定义（engine、switches、speller、translator 等）
- `*.custom.yaml` — 同名配置补丁，覆盖默认值；`default.custom.yaml` 为全局补丁（方案列表、标点、按键、候选数）
- `*.dict.yaml` + `dicts/` — 词库（虎码系列 + 万象扩展词库）；`custom_phrase.txt` 自定义短语
- `lua/` + `rime.lua` — Lua 插件总入口，在此 `require` 注册 translator/filter/processor
- `key_bindings.yaml`、`symbols.yaml`、`opencc/`、`fonts/`、`themes/`、`backgrounds/`、`icons/` — 辅助配置与资源
- `models/` — 整句 ngram 模型（`sentence-ngram-v2.bin`，虎码整句方案依赖）
- 同文输入法主题：`*.trime.yaml`（如 `pure.trime.yaml`、 `dvorak.trime.yaml` ）是主题主文件，`*.trime.custom.yaml` 是其补丁
- Lua 子目录：
  - `lua/lib/base.lua` — Lua 通用工具库（Rime 目录获取等）
  - `lua/lib/segment.lua` — segment tag 分类工具（`init_special_tags`/`is_reverse_segment`/`is_special_segment`，供 comment_filter 系列使用）
  - `lua/data/aux_code/` — 辅助码码表（如 `flypy_full.txt` 小鹤音形码表）
  - `lua/data/core2022/` — core2022 字集 hash set（由 `bin/gen_core2022.sh` 从 `dicts/core2022.dict.yaml` 自动生成，勿手动改）
  - `lua/data/input_stats/` — 输入统计数据（由 `input_statistics.lua` 自动生成，勿手动改）
- 超越输入法：根目录 `info.yaml`（方案描述）+ `space.custom.yaml`（目录补丁）+ `themes/`（主题目录，含 `dvorak_pure/` 、 `t26_pure/`）

## Conventions

- 新增 Lua 插件：在 `rime.lua` 中 `require`，模块返回 `{ init = ...， func/filter/processor = ... }`；用中文注释，不在这 `require` 的话，需要加 `*`，例 `lua_translator@*helper`
- 功能触发键：`=` 计算器、`/` 符号与日期、`` ` `` 拼音反查/造词分隔/辅助码分隔、`'` 英文、`S` 数字大写、`mode` 切换方案、`help` 帮助、`uuid` 生成 uuid、`tjrt` 等输出统计信息
- 自动造词：单字编码以 `` ` `` 分隔输入；新词写入 `lua/data/user_dicts/tigress_user.dict.yaml`，格式 `词<Tab>权重<Tab>编码`
- 注释过滤器（charset/chaifen/pinyin_comment_filter）共用 `lua/lib/segment.lua`，首次调用时从 `recognizer/patterns` 动态读取所有 tag 名并缓存；新增 recognizer 模式时三个 filter 自动跳过对应候选，无需改 Lua
- 词库文件体积大（如 `easy_english.dict.yaml` 15MB、`wanxiang-lts-zh-hans.gram` 420MB），grep/读取时注意
- commit message 遵循 Conventional Commits（如 `feat/fix/perf/style/refactor/chore/ci`）

## Notes

- 用户词库模板 `lua/data/user_dicts/tigress_user.dict.yaml` 已 `git update-index --skip-worktree`，本地改动不提交；查标记：`git ls-files -v | grep '^S'`。其内容属于模板，更新后不需要再提交。
- `lua/data` 存储 lua 相关的数据，该目录中的文件不允许手动修改（`core2022/data.lua` 由 `gen_core2022.sh` 生成，`input_stats/data.lua` 由 `input_statistics.lua` 生成）
- `models/*.bin` 整句模型文件不纳入 git 跟踪（类似 `.gram` 文件），需通过 `bin/download_gram.sh` 下载

## References

- `default.custom.yaml`、`*.schema.yaml` 及其同名 `*.custom.yaml` 文件
  - Rime 基础配置参考：https://github.com/rime/rime-prelude
  - Rime 配置：https://github.com/rime/home/wiki/Configuration
  - Rime 定製指南：https://github.com/rime/home/wiki/CustomizationGuide
  - Rime 输入方案设计书：https://github.com/rime/home/wiki/RimeWithSchemata
  - Rime schema 规范：https://github.com/LEOYoon-Tsaw/Rime_collections/blob/master/Rime_description.md
  - Rime emoji 使用：https://github.com/rime/rime-emoji
  - OpenCC：https://github.com/rime/OpenCC
  - 卸载 Squirrel、繁体转换：https://github.com/rime/home/wiki/FAQ
  - 输入法引擎 librime：https://github.com/rime/librime — 如果文档没提，要看这个的源码
- `rime.lua`、`lua/*.lua`
  - Wiki：https://github.com/hchunhui/librime-lua/wiki
  - 快速上手：https://github.com/hchunhui/librime-lua/wiki/Scripting
  - 编程接口：https://github.com/hchunhui/librime-lua/wiki/API
  - 对象接口：https://github.com/hchunhui/librime-lua/wiki/Objects
- `squirrel.custom.yaml` 鼠须管配置
  - 官方 Wiki：https://github.com/rime/squirrel/wiki（要查看其页面 `a` 标签中内容）
    - 重点看 鼠须管介面定制指南 https://github.com/rime/squirrel/wiki/squirrel.yaml-%E9%85%8D%E7%BD%AE%E6%8C%87%E5%8D%97
  - 鼠鬚管介面配置指南：https://github.com/LEOYoon-Tsaw/Rime_collections/blob/master/%E9%BC%A0%E9%AC%9A%E7%AE%A1%E4%BB%8B%E9%9D%A2%E9%85%8D%E7%BD%AE%E6%8C%87%E5%8D%97.md
  - 参考配置：https://github.com/LEOYoon-Tsaw/Rime_collections/blob/master/squirrel.custom.yaml
- `weasel.custom.yaml` 小狼毫配置
  - 官方 Wiki：https://github.com/rime/weasel/wiki（要查看其页面 `a` 标签中内容）
    - Weasel 定制化：https://github.com/rime/weasel/wiki/Weasel-%E5%AE%9A%E5%88%B6%E5%8C%96
    - Weasel 速查：https://github.com/rime/weasel/wiki/weasel.yaml-%E9%80%9F%E6%9F%A5
    - 字体设定：https://github.com/rime/weasel/wiki/%E5%AD%97%E9%AB%94%E8%A8%AD%E5%AE%9A
    - 配色：https://github.com/rime/weasel/wiki/%E5%AE%9A%E5%88%B6%E5%B0%8F%E7%8B%BC%E6%AF%AB%E9%85%8D%E8%89%B2
    - 为特定输入方案定制外观：https://github.com/rime/weasel/wiki/%E4%B8%BA%E7%89%B9%E5%AE%9A%E8%BE%93%E5%85%A5%E6%96%B9%E6%A1%88%E5%AE%9A%E5%88%B6%E5%A4%96%E8%A7%82
    - 示例：https://github.com/rime/weasel/wiki/%E7%A4%BA%E4%BE%8B
- `*.trime.yaml`、`*.trime.custom.yaml` 同文输入法配置
  - 配置文件中的一些语法：https://github.com/osfans/trime/wiki/trimer%E5%B0%8F%E7%9F%A5%E8%AF%86(2)---%E9%85%8D%E7%BD%AE%E6%96%87%E4%BB%B6%E4%B8%AD%E7%9A%84%E4%B8%80%E4%BA%9Byaml%E8%AF%AD%E6%B3%95
  - 索引：https://github.com/osfans/trime/wiki/UserGuide
  - trime 旧配置：https://github.com/osfans/trime/wiki/trime.yaml-%E8%A9%B3%E8%A7%A3
  - trime 新配置：https://github.com/osfans/trime/wiki/Theme-Configuration-(New)
- 超越输入法，当前目录会导入到 `space/schemas/huma_rime_config/`，在本目录中的同名目录（如 `themes`、`fonts`）只在这本目录中的输入方案生效
  - space 仓库：https://github.com/Beyond-Input-Method/space
- 虎码上游方案：https://github.com/zhhmn/huma-rime — `bin/sync_dicts.sh` 的源，方案与词库更新来源
- 万象词库：https://github.com/amzxyz/rime_wanxiang — `dicts/` 大部分词库来源
- 本项目仓库：https://github.com/wallleap/huma-rime-config — 上游维护版本（当前仓库为其本地定制副本）
