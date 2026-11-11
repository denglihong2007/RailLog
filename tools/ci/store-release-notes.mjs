// 把 PR 正文转成微软商店能用的纯文本，并写进 submission JSON 的 zh-cn 列表。
//
// 用法：node tools/ci/store-release-notes.mjs <notes.md> <submission.json>
//
// 商店的「此版本新增内容」只收纯文本，每个语言上限 1500 字符，所以这里要
// 去掉标题、强调、链接、代码块这些 Markdown 语法，再按句末/换行截断。

import { readFileSync, writeFileSync } from 'node:fs';

const LIMIT = 1500;
const LANGUAGE = 'zh-cn';

function toPlainText(markdown) {
  let text = markdown.replace(/^﻿/, '').replace(/\r\n?/g, '\n');

  // HTML 注释和标签不进入商店文案
  text = text.replace(/<!--[\s\S]*?-->/g, '');
  text = text.replace(/<[^>]+>/g, '');

  // 整块代码直接丢掉：PR 里的验证输出对普通用户没有意义
  text = text.replace(/^[ \t]*```[^\n]*\n[\s\S]*?^[ \t]*```[ \t]*$/gm, '');

  // 图片只要 alt 文字，链接只要链接文字
  text = text.replace(/!\[([^\]]*)\]\([^)]*\)/g, '$1');
  text = text.replace(/\[([^\]]+)\]\([^)]*\)/g, '$1');
  text = text.replace(/\[([^\]]+)\]\[[^\]]*\]/g, '$1');

  // 标题标记、引用标记、分隔线
  text = text.replace(/^[ \t]{0,3}#{1,6}[ \t]*/gm, '');
  text = text.replace(/^[ \t]{0,3}>[ \t]?/gm, '');
  text = text.replace(/^[ \t]{0,3}([-*_])(?:[ \t]*\1){2,}[ \t]*$/gm, '');
  text = text.replace(/^[ \t]*[=-]{3,}[ \t]*$/gm, '');

  // 表格：分隔行丢掉，数据行用「·」连接
  text = text.replace(/^[ \t]*\|?[ \t:|-]+\|[ \t:|-]*$/gm, '');
  text = text.replace(/^[ \t]*\|(.+)\|[ \t]*$/gm, (_, row) =>
    row
      .split('|')
      .map((cell) => cell.trim())
      .filter(Boolean)
      .join(' · '),
  );

  // 列表统一成「•」，任务列表的勾选标记也去掉
  text = text.replace(/^(\s*)[-*+][ \t]+\[[ xX]\][ \t]+/gm, '$1• ');
  text = text.replace(/^(\s*)[-*+][ \t]+/gm, '$1• ');

  // 强调、删除线、行内代码
  text = text.replace(/\*\*\*(.+?)\*\*\*/g, '$1');
  text = text.replace(/\*\*(.+?)\*\*/g, '$1');
  text = text.replace(/___(.+?)___/g, '$1');
  text = text.replace(/__(.+?)__/g, '$1');
  text = text.replace(/\*(?!\s)(.+?)(?<!\s)\*/g, '$1');
  text = text.replace(/(?<![\w])_(?!\s)(.+?)(?<!\s)_(?![\w])/g, '$1');
  text = text.replace(/~~(.+?)~~/g, '$1');
  text = text.replace(/`([^`]+)`/g, '$1');

  // Markdown 的反斜杠转义
  text = text.replace(/\\([\\`*_{}[\]()#+\-.!>])/g, '$1');

  // 收掉多余空白，但保留段落之间的一个空行
  text = text.replace(/[ \t]+$/gm, '');
  text = text.replace(/\n{3,}/g, '\n\n');

  return text.trim();
}

function clamp(text) {
  if (text.length <= LIMIT) return text;

  const cut = text.slice(0, LIMIT - 1);
  // 优先在段落/句子边界断开，避免把半句话截给用户
  const boundary = Math.max(
    cut.lastIndexOf('\n'),
    cut.lastIndexOf('。'),
    cut.lastIndexOf('；'),
    cut.lastIndexOf('！'),
    cut.lastIndexOf('？'),
  );
  const body = boundary >= Math.floor(LIMIT * 0.6) ? cut.slice(0, boundary + 1) : cut;
  return `${body.trimEnd()}…`;
}

function findKey(object, name) {
  if (!object || typeof object !== 'object') return undefined;
  return Object.keys(object).find((key) => key.toLowerCase() === name.toLowerCase());
}

const [, , notesPath, submissionPath] = process.argv;
if (!notesPath || !submissionPath) {
  console.error('Usage: node tools/ci/store-release-notes.mjs <notes.md> <submission.json>');
  process.exit(1);
}

const markdown = readFileSync(notesPath, 'utf8').replace(/^﻿/, '');
if (!markdown.trim()) {
  // 没有 PR 正文时不覆盖商店里已有的说明
  console.log('Release notes are empty; the existing store listing was left unchanged.');
  process.exit(0);
}

const submission = JSON.parse(readFileSync(submissionPath, 'utf8').replace(/^﻿/, ''));

const listingsKey = findKey(submission, 'listings');
if (!listingsKey) throw new Error("submission JSON has no 'listings' object");

const listings = submission[listingsKey];
const languageKey = findKey(listings, LANGUAGE);
if (!languageKey) throw new Error(`submission JSON has no '${LANGUAGE}' listing`);

const listing = listings[languageKey];
const baseListingKey = findKey(listing, 'baseListing');
const baseListing = baseListingKey ? listing[baseListingKey] : listing;

const notesKey = findKey(baseListing, 'releaseNotes');
if (!notesKey) throw new Error(`the '${LANGUAGE}' listing has no 'releaseNotes' field`);

const notes = clamp(toPlainText(markdown));
baseListing[notesKey] = notes;

writeFileSync(submissionPath, JSON.stringify(submission), 'utf8');

console.log(`Updated ${LANGUAGE} release notes (${notes.length}/${LIMIT} characters).`);
console.log('---');
console.log(notes);
