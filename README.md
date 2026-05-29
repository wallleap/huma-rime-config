# 虎码 + 小鹤双拼 Rime 配置

项目地址：<https://github.com/wallleap/huma-rime-config>

本项目是基于虎码官方秃码方案进行深度定制的 Rime 配置集合，旨在提供高效、智能的输入体验

全平台适用（下载对应平台 Rime 发行版，导入配置文件，重新部署即可使用）

如何学习虎码：直接到官网（<https://www.tiger-code.com/docs/introduction>）按照顺序练习

> 虎码网盘：<http://huma.ysepan.com/> | 原始仓库：<https://github.com/zhhmn/huma-rime>

配置目录及主要文件说明：

- 全局默认配置 `default.yaml`
- 输入方案 `*.schema.yaml`
- 词库 `*.dict.yaml`
- 前端配置文件
  - macOS 鼠须管配置 `squirrel.yaml`
  - Windows 小狼毫配置 `weasel.yaml`
  - 安卓同文输入法配置 `trime.yaml`、`*.trime.yaml`
  - iOS 仓输入法配置 `hamster.yaml`
- 同名方案、配置补丁 `*.custom.yaml`

```bash
.
├── PY_c.custom.yaml			# 拼音++ 补丁，主要添加小鹤双拼拼写运算规则
├── PY_c.dict.yaml				# 拼音++ 词库
├── PY_c.schema.yaml			# 拼音++ 方案
├── README.md					# README 文档
├── aux_code/					# [目录]存放拼音辅助码表文件
│   └── flypy_full.txt			# 小鹤双拼辅助码表
├── backgrounds/				# [目录]存放同文输入法背景图
│   ├── keyboard-dark.png		# 同文输入法 暖黄渐变 配色背景
│   ├── keyboard-light.png		# 同文输入法 深棕暗调 配色背景
│   └── keys/					# [目录]存放按键背景图
├── bin/						# [目录]存放辅助脚本
│   └── sync_dicts.sh			# 同步虎码、万象词库 bash 脚本
├── core2022.dict.yaml			# 字符集过滤辅助方案词库
├── core2022.schema.yaml		# 字符集过滤辅助方案
├── custom_phrase.txt			# 自定义短语文件
├── default.custom.yaml			# 全局默认配置补丁
├── dicts/						# [目录]存放所有扩展词库
│   ├── cuoyin.dict.yaml		# 万象 错音错字
│   ├── diming.dict.yaml		# 万象 地名
│   ├── duoyin.dict.yaml		# 万象 多音字
│   ├── jichu.dict.yaml			# 万象 基础字词
│   ├── lianxiang.dict.yaml		# 万象 联想词
│   ├── renming.dict.yaml		# 万象 人名
│   ├── shici.dict.yaml			# 万象 诗词
│   ├── tiger.dict.yaml			# 虎单
│   ├── tigress.dict.yaml		# 虎词 单字
│   ├── tigress_ci.dict.yaml	# 虎词 词
│   ├── tigress_simp_ci.dict.yaml	# 虎词 简词
│   ├── wuzhong.dict.yaml		# 万象 物种
│   └── zi.dict.yaml			# 万象 单字
├── easy_english.dict.yaml		# 英文字库
├── easy_english.schema.yaml	# 英文方案
├── flypy.custom.yaml			# 小鹤双拼补丁
├── flypy.dict.yaml				# 小鹤双拼词库
├── flypy.schema.yaml			# 小鹤双拼方案
├── flypy.txt					# 自动生成的小鹤双拼用户词典
├── fonts/						# [目录]存放字体文件，可以直接给同文输入法使用
│   └── tumapua/				# [目录]存放鸿蒙超越输入法字体配置（一个字体一个目录）
│       ├── TumanPUA.ttf		# 字体文件
│       └── info.yaml			# 说明配置
├── hamster.custom.yaml			# iOS 仓输入法配置补丁
├── icons/						# [目录]存放 Windows 小狼毫输入法图标
│   ├── en.ico					# 英文状态
│   ├── full.ico				# 全角状态
│   ├── half.ico				# 半角状态
│   ├── mix.ico					# 混输
│   ├── pin.ico					# 全拼
│   ├── shuang.ico				# 双拼
│   ├── tiger.ico				# 虎码
│   ├── wubi.ico				# 五笔
│   └── zh.ico					# 中文状态
├── info.yaml					# 鸿蒙超越输入法方案整体说明
├── key_bindings.custom.yaml	# 按键绑定补丁
├── key_bindings.yaml			# 按键绑定
├── lua/						# [目录]存放 lua 脚本
│   ├── aux_code.lua			# 辅助码拆分
│   ├── calculator_translator.lua	# 计算器
│   ├── chaifen_comment_filter.lua	# 拆分提示/注释
│   ├── charset_comment_filter.lua	# 字符集提示
│   ├── core2022_filter.lua		# 字集过滤
│   ├── date_translator.lua		# 日期时间
│   ├── helper.lua				# 输入 help 获取简要说明
│   ├── in_user_dict.lua		# 在用户词库添加 emoji
│   ├── input_statistics.lua	# 自动生成输入统计
│   ├── input_stats.lua			# 输入统计
│   ├── lib/					# [目录]存放工具库
│   │   └── base.lua
│   ├── maker.lua				# 虎词自动造词
│   ├── number.lua				# 数字转换
│   ├── pinyin_comment_filter.lua	# 拼音注释
│   ├── schema_switcher.lua		# 输入 mode 选择切换方案
│   ├── unicode_display.lua		# Unicode 显示
│   └── uuid_translator.lua		# 输入 uuid 生成
├── opencc/						# [目录]存放滤镜文件（拼音、拆分、繁简转换、emoji）
├── punctuation.yaml			# 标点符号配置
├── pure.trime.custom.yaml		# 安卓同文输入法补丁
├── pure.trime.yaml				# 安卓同文输入法朴素主题
├── rime.lua					# lua 总入口
├── space.custom.yaml			# 鸿蒙超越输入法目录配置
├── squirrel.custom.yaml		# macOS 鼠须管配置补丁
├── stroke.dict.yaml			# 笔画输入方案词库
├── symbols.yaml				# 符号
├── themes/						# [目录]存放鸿蒙输入法主题
│   └── t26_pure/				# [目录]26键朴素主题
│       ├── info.yaml			# 主题信息
│       ├── preset_keyboards.yaml	# 按键配置
│       ├── preset_keys.yaml	# 按键配置
│       ├── res/				# [目录]存放主题使用到的图标
│       └── theme.yaml			# 主题具体配置
├── tiger.custom.yaml			# 虎单方案补丁
├── tiger.extended.dict.yaml	# 虎单方案词库
├── tiger.schema.yaml			# 虎单方案
├── tiger_flypy_mix.custom.yaml	# 虎单小鹤双拼混输方案补丁
├── tiger_flypy_mix.schema.yaml	# 虎单小鹤双拼混输方案
├── tigress.custom.yaml			# 虎词方案补丁
├── tigress.extended.dict.yaml	# 虎词方案词库
├── tigress.schema.yaml			# 虎词方案
├── tigress_phrase.txt			# 自动生成的虎词造词词库
├── trash/						# [目录]回收站
│   └── stroke.schema.yaml		# 笔画输入方案，前端自带会自动删除，做个备份
├── wanxiang-lts-zh-hans.gram	# 万象模型
└── weasel.custom.yaml			# Windows 小狼毫配置补丁
```

如何列出文件：WSL、mac、Linux 下执行 `tree -I '.git|build|sync|*.userdb'`

## 1. 方案介绍

本项目包含四个核心方案，分别针对不同的使用场景：

### 🐯 虎码单字版 (Tiger) - `tiger.schema.yaml`

- **定位**：专为追求极致单字效率的用户设计（候选词四码唯一自动上屏）。
- **特色**：纯净无词组干扰，专注于单字击打。
- **辅助**：支持开启**拆分滤镜**（Switch: `chaifen`），显示字根拆分辅助记忆。

### 🐯🦩 虎码小鹤双拼混输 (Tiger Flypy Mix) - `tiger_flypy_mix.schema.yaml`

- **定位**：适合小鹤双拼转虎码的用户，支持打虎单以及使用小鹤双拼打词或句子。
- **特色**：整合了虎码单字版和小鹤双拼的输入规则，匹配到虎码单字将位于第一候选。

### 🐯 虎码词库版 (Tigress) - `tigress.schema.yaml`

- **定位**：适合日常整句、词组输入（仍是四码）。
- **核心特色**：集成了强大的**自动造词系统**，支持在使用过程中动态扩充词库。
- **功能**：支持简/繁切换、Emoji、拼音反查、日期计算等丰富功能。

### 🦩 小鹤双拼 - `flypy.schema.yaml`

- **定位**：临时需要简易输入双拼的场景
- **特色**：在万象词库基础上，整合了小鹤双拼的输入规则

小鹤双拼辅助码：输入双拼后加 `;`（个人习惯两个键输入双拼，辅助码仅用于难以选词时使用）

双拼和混熟自定义短语文件：`custom_phrase.txt`

> PY\_c.schema.yaml 是基于拼音 ++ 改造的小鹤双拼方案，整合了小鹤双拼的输入规则，暂时不直接用于输入方案，而是作为虎码反查使用

## 2. 如何使用

1. 安装 Rime 输入法发行版/前端（如「[鼠须管](https://github.com/rime/squirrel/releases)」、「[中州韵](https://github.com/rime/home/wiki/RimeWithIBus)」、「[小狼豪](https://github.com/rime/weasel/releases)」、「[同文输入法](https://github.com/osfans/trime/releases)」、「[仓输入法](https://apps.apple.com/hk/app/%E4%BB%93%E8%BE%93%E5%85%A5%E6%B3%95/id6446617683)」/「[元书输入法](https://apps.apple.com/us/app/%E5%85%83%E4%B9%A6%E8%BE%93%E5%85%A5%E6%B3%95/id6744464701)」、「[超越输入法](https://appgallery.huawei.com/app/detail?id=app.flytype.hmos.bim\&channelId=SHARE\&source=appshare)」等）
2. 到 [Release](https://github.com/wallleap/huma-rime-config/releases) 中下载压缩包，并解压到本地
3. 安装字体包
   - macOS 全选 `fonts` 目录下的所有字体文件，右击，点击安装/打开
   - Windows 全选 `fonts` 目录下的所有字体文件，右击，选择为【所有用户安装】（如果没有看到，可能在更多里面）
   - iOS 端使用仓输入法，可以选择【输入方案上传】，然后在电脑浏览器输入显示的 IP 地址（同一局域网），在根目录新建 `Fonts` 文件夹，把 `fonts` 目录下的所有字体文件上传到 `Fonts` 文件夹中
   - 安卓端同文输入法无需操作
   - 鸿蒙端超越输入法需要导入方案之后在菜单栏中找到字体，选择 「虎码秃码字体」，切换其他输入法然后切换回超越输入法
4. 把本仓库所有文件复制到 Rime 配置目录下（如 `~/Library/Rime`、`%APPDATA%\Rime` 等），手机上可以通过**压缩包导入**或局域网上传等方式导入到对应的目录下
5. 点击重新部署

> 词库文件和万象模型都挺大的，需要等待一段时间才能下载完成，可以复制下载链接，在前面添加 `https://ghfast.top/` 加速下载；部署时，需要等待一段时间才能部署完成；小内存设备输入时，可能会有延迟，建议在输入时保持等待（或者选择其他适合自己的方案）。

通用功能：

- `help` 查看帮助文档（部分快捷键可查看方案文件）
- `mode` 切换方案（手机上仅支持空格切换，直接点击会直接上屏且不会切换）
- `/` 引导的符号日期等
- `'` 引导的英文输入

## 3. 自动造词功能 (Tigress Maker)

这是 `Tigress` 方案最核心的增强功能，允许用户在输入过程中“即造即用”，无需手动编辑文件或重新部署（实际还是需要点击重新部署才能读取到写入词库文件中的新词）。

### 3.1 如何造词

目前只支持单字组合，即一个字加分隔符加字加分隔符加字的形式。

想要输入一个新词（例如“虎码”），只需用单引号 `'` 将各字编码隔开：

1. 输入“虎”的编码：`zhh`
2. 输入分隔符：`'`
3. 输入“码”的编码：`mn`
   - 此时编码显示：`zhh'mn`
4. 候选栏会出现带有 **☯** 标记的造词选项：`虎码 ☯ 造词: zhmn`
5. 按 **空格** 上屏，该词即刻存入词库，并且能够在不部署的情况下直接使用（目前输入新造词不是读取的词库中的新词，而是直接从内存中读取的）。
6. \[可忽略] 重新部署之后，再输入造的词是从词库中读取的，如果开了 `is_in_user_dict` lua 插件，会在后面显示 `*` 号

![](https://cdn.wallleap.cn/img/pic/illustration/20260201204718853.png?imageSlim)

注：已经在用户词库（目前设置的是 `tigress_phrase.txt`）文件中的会显示已在词库，不会重复添加到词库文件中

### 3.2 智能规则与限制

- **4 码自动清理**：为保持输入节奏，若未输入分隔符 `'`，输入超过 4 码时会自动清空前序编码（排除前缀如 `` ` `` 除外）。
- **去重机制**：
  - **系统词库显示时退让**：如果虎码原生词库中已有该词，仍可以进行造词，保存到用户词库，如果开启了 `is_in_user_dict` 重新部署后就能够在这些词后看到 `*` 号，并且显示的时候只显示用户词库中的词。
  - **用户词库去重**：如果已造过该词，选项会显示 `⚡ 已在词库`，重复选择不会重复写入文件。

### 3.3 数据存储

- 新造词语默认保存在 `tigress.txt` 文件中，可以通过配置修改，目前配置为 `tigress_phrase.txt`。
- 格式为：`词语 <Tab> 编码 <Tab> 权重`。

## 4. 通用辅助功能

以下功能在两个虎码方案中均可使用（视具体开关状态而定）：

### 4.1 双拼反查

- **触发键**：`` ` `` (Tab 键上方)。
- **方案**：采用**小鹤双拼**方案进行反查。
- **用途**：遇到不会打的字，可以通过拼音反查出虎码编码。

### 4.2 快捷工具 (Lua 脚本)

- **日期时间**：
  - 输入 `/date` -> 得到当前日期（如 `2023年10月27日`）。
  - 输入 `/time` -> 得到当前时间。
  - 输入 `/week` -> 得到星期几。
  - 其他的可以到 `lua/date_translator.lua` 中查看
- **简易计算器**：
  - 直接输入 `=` + 算式，如 `=1+1`，候选框会显示结果 `1+1=2`。
- **数字大写**：
  - 输入 `S` 开头接数字，可转换为大写金额（如 `S123` -> `壹佰贰拾叁`）。
- **Unicode 显示**：
  - 候选词后方会提示该字符的 Unicode 编码及分区信息（需开启 `charset_comment_filter`）。

## 5. 快捷开关 (Switches)

可以通过快捷键（通常是 `F4` 或 `Ctrl+`）呼出方案选单，调整以下设置：

- **中文 / 西文**：切换中英文输入。
- **全集 / 常用**：过滤非常用生僻字。
- **简中 / 繁中**：快速进行简繁转换。
- **拆隐 / 拆显** (仅 Tiger)：是否显示字根拆分提示。
- **Emoji**：是否显示 Emoji 表情。

## 6. 主题

目前支持以下平台：

- 鸿蒙 超越输入法
- 安卓 同文输入法
- macOS 鼠须管
- Windows 小狼豪

![](https://cdn.wallleap.cn/img/pic/illustration/20260417194633749.png?imageSlim)

![](https://cdn.wallleap.cn/img/pic/illustration/20260125143422338.png?imageSlim)

![](https://cdn.wallleap.cn/img/pic/illustration/20260201203655267.png?imageSlim)

## 7. 脚本

`bin` 目录下放置了一些辅助脚本

### 7.1 sync\_dicts.sh 同步字典文件

该脚本用于同步官方字典文件到本地仓库

如果有其他字典文件需要同步，可以在 `SYNC_LIST` 中添加

```sh
# ===================== 同步列表 =====================
SYNC_LIST=(
  "https://github.com/zhhmn/huma-rime/raw/refs/heads/master/PY_c.dict.yaml|${REPO_ROOT}"
  "https://github.com/zhhmn/huma-rime/raw/refs/heads/master/core2022.dict.yaml|${REPO_ROOT}"
  "https://github.com/zhhmn/huma-rime/raw/refs/heads/master/easy_english.dict.yaml|${REPO_ROOT}"
  "https://github.com/zhhmn/huma-rime/raw/master/tiger.dict.yaml|${REPO_ROOT}/dicts"
  "https://github.com/zhhmn/huma-rime/raw/master/tigress_ci.dict.yaml|${REPO_ROOT}/dicts"
  "https://github.com/zhhmn/huma-rime/raw/master/tigress_simp_ci.dict.yaml|${REPO_ROOT}/dicts"
  "https://github.com/zhhmn/huma-rime/raw/master/tigress.dict.yaml|${REPO_ROOT}/dicts"
  "https://github.com/amzxyz/rime_wanxiang/raw/refs/heads/wanxiang/dicts/cuoyin.dict.yaml|${REPO_ROOT}/dicts"
  "https://github.com/amzxyz/rime_wanxiang/raw/refs/heads/wanxiang/dicts/diming.dict.yaml|${REPO_ROOT}/dicts"
  "https://github.com/amzxyz/rime_wanxiang/raw/refs/heads/wanxiang/dicts/duoyin.dict.yaml|${REPO_ROOT}/dicts"
  "https://github.com/amzxyz/rime_wanxiang/raw/refs/heads/wanxiang/dicts/jichu.dict.yaml|${REPO_ROOT}/dicts"
  "https://github.com/amzxyz/rime_wanxiang/raw/refs/heads/wanxiang/dicts/lianxiang.dict.yaml|${REPO_ROOT}/dicts"
  "https://github.com/amzxyz/rime_wanxiang/raw/refs/heads/wanxiang/dicts/renming.dict.yaml|${REPO_ROOT}/dicts"
  "https://github.com/amzxyz/rime_wanxiang/raw/refs/heads/wanxiang/dicts/shici.dict.yaml|${REPO_ROOT}/dicts"
  "https://github.com/amzxyz/rime_wanxiang/raw/refs/heads/wanxiang/dicts/wuzhong.dict.yaml|${REPO_ROOT}/dicts"
  "https://github.com/amzxyz/rime_wanxiang/raw/refs/heads/wanxiang/dicts/zi.dict.yaml|${REPO_ROOT}/dicts"
)
```

格式为：`文件链接|本地保存路径`

给脚本添加执行权限，然后运行

```sh
chmod +x ./bin/sync_dicts.sh
./bin/sync_dicts.sh
```

## 8. 同步用户数据

主要用于小鹤双拼词库同步合并，需要在每台设备 `installation.yaml` 设置 `sync_dir`

并且借助云盘 + Folder Sync 进行同步

- mac 上：`sync_dir: '/Users/luwang/Library/Mobile Documents/iCloud~~dev~~fuxiao~~app~~hamsterapp/Documents/sync'` 指定 iCloud 下的 仓输入法目录，下载 [FolderSync](https://foldersync.io/desktop/#download)，在账户中登陆 OneDrive，双向同步这个目录和 OneDrive 下的 `sync` 目录
- win 上：`sync_dir: 'C:/Users/luwang/OneDrive/sync'` 指定 OneDrive 下的目录
- 安卓上：保持默认，将会同步到 `rime/sync`，下载 [FolderSync](https://foldersync.io/android)，在账户中登陆 OneDrive，双向同步这个目录和 OneDrive 下的 `sync` 目录
- iOS 上：`sync_dir: '/private/var/mobile/Library/Mobile Documents/iCloud~dev~fuxiao~app~hamsterapp/Documents/sync'` 指定 iCloud 下的 仓输入法目录（最好手动选择）

之后有空的时候点击 Rime 的 `同步` 按钮，即可同步用户数据
