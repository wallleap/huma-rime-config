#!/usr/bin/env node
// Rime 配置仓库格式校验
// 依赖: js-yaml (YAML), luaparse (Lua 语法)
// 用法: node bin/lint.mjs [--strict]
import fs from "node:fs";
import path from "node:path";
import { execSync } from "node:child_process";
import yaml from "js-yaml";
import luaparse from "luaparse";

const REPO_ROOT = path.resolve(import.meta.dirname, "..");
const STRICT = process.argv.includes("--strict");

// ---------- 收集待检文件 (Git 跟踪 + 未忽略的本地文件) ----------
function gitFiles(args) {
  try {
    return execSync(`git ls-files ${args}`, {
      cwd: REPO_ROOT,
      encoding: "utf8",
    })
      .split("\n")
      .filter(Boolean);
  } catch {
    return [];
  }
}
const tracked = new Set(gitFiles("")); // 已跟踪
const untracked = gitFiles("--others --exclude-standard"); // 未跟踪且未被 .gitignore 忽略

// 合并: 跟踪 + 未忽略的本地新文件 (尊重 .gitignore, 排除 themes/public 等本地参考目录)
const files = [...tracked, ...untracked].filter(
  (f) =>
    f.endsWith(".yaml") ||
    f.endsWith(".lua") ||
    f.endsWith(".dict.yaml") ||
    f.endsWith("dict.txt"),
);

// ---------- 分类: *.dict.yaml 一律词库, 其余 .yaml 为配置, .lua 为插件 ----------
const yamlFiles = [];
const luaFiles = [];
const dictFiles = [];
const SKIP = ["node_modules/", ".git/", "trash/"]; // 排除目录

for (const f of new Set(files)) {
  if (SKIP.some((s) => f.startsWith(s))) continue;
  const full = path.join(REPO_ROOT, f);
  if (!fs.existsSync(full)) continue;
  if (f.endsWith(".dict.yaml") || f.endsWith("dict.txt")) dictFiles.push(f);
  else if (f.endsWith(".lua")) luaFiles.push(f);
  else yamlFiles.push(f);
}

// ---------- 校验 ----------
let errors = 0;
let warnings = 0;
const fail = (kind, file, msg) => {
  errors++;
  console.error(`[${kind}] ${file}: ${msg}`);
};
const warn = (kind, file, msg) => {
  warnings++;
  console.warn(`[${kind}:警告] ${file}: ${msg}`);
};

for (const f of yamlFiles) {
  const full = path.join(REPO_ROOT, f);
  const content = fs.readFileSync(full, "utf8");
  if (f.startsWith("themes/") && !STRICT) continue; // 主题文件含特殊占位符, 宽松模式跳过
  console.log("current:", f);
  try {
    yaml.load(content); // 只做语法校验, 不关心结果
  } catch (e) {
    fail("yaml", f, e.reason || e.message);
  }
  // 警告: 制表符缩进 (YAML 非法但易被忽略)
  if (/^\t/m.test(content)) warn("yaml", f, "包含 Tab 缩进 (YAML 不允许)");
}

for (const f of luaFiles) {
  const full = path.join(REPO_ROOT, f);
  // 剥离 UTF-8 BOM (Rime 引擎可容忍, 解析器不行)
  const content = fs.readFileSync(full, "utf8").replace(/^\uFEFF/, "");
  console.log("current:", f);
  try {
    luaparse.parse(content, { luaVersion: "5.3" });
  } catch (e) {
    fail("lua", f, e.message);
  }
}

for (const f of dictFiles) {
  const full = path.join(REPO_ROOT, f);
  const lines = fs.readFileSync(full, "utf8").split(/\r?\n/);
  console.log("current:", f);
  let code = 0,
    bad = 0,
    inBody = false; // inBody: 是否已进入词条区 (遇到第一个含 tab 的行)
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const t = line.trim();
    if (!t || t.startsWith("#") || /^---\s*$/.test(t)) continue;
    // 词条区之前的行 (name/version/sort/import_tables 等头部 YAML 元数据) 一律跳过
    if (!inBody && !t.includes("\t")) continue;
    inBody = true;
    const cols = line.split("\t");
    if (cols.length < 2) {
      bad++;
      if (bad <= 3) warn("dict", f, `行 ${i + 1} 列数不足: ${t.slice(0, 30)}`);
      continue;
    }
    code++;
  }
  // 词条区内有格式问题 (bad>0) 但几乎无合法词条 (code 极少) 时, 提示可能是误分类
  if (bad > 0 && code === 0)
    fail("dict", f, `${bad} 行格式异常 (词条区无合法词条)`);
}

console.log("----------------------------------------");

// ---------- 汇总 ----------
if (errors > 0) {
  console.error(`\n✗ Lint 完成: ${errors} 个错误, ${warnings} 个警告`);
  process.exit(1);
} else if (warnings > 0) {
  console.warn(`\n✓ Lint 完成: 无错误, ${warnings} 个警告`);
  process.exit(0);
} else {
  console.log(
    `\n✓ Lint 完成: ${yamlFiles.length + luaFiles.length + dictFiles.length} 个文件全部通过`,
  );
}
