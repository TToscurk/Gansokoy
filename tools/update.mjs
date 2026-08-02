#!/usr/bin/env node
// ============================================================
//  幻想鄉 3D —— 分支更新器
//
//  為什麼這支是 Node 而不是批次檔：
//    cmd.exe 執行批次檔時用「位元組」偏移量記住讀到哪一行，但 chcp 65001
//    之後改用「字元」數去算，兩者對不上就會從某一行的中間開始執行。
//    中文註解越多飄得越兇 —— 第一版的 更新.bat 就是這樣炸的
//    （跑出 'use'（usebackq 的碎片）、date（--date= 的碎片）之類的錯誤）。
//    把中文移出批次檔就沒這個問題，更新.bat 現在只剩純 ASCII 的殼。
//
//  做的事：
//    1. git fetch --prune 抓下所有分支
//    2. 依最後更新時間由新到舊列出來
//    3. 選一條 → 切過去，選擇寫進 .branch（play.bat 會讀）
//       選 A   → git worktree 把每條分支各解一份到 branches/
// ============================================================
import { execFileSync, spawnSync } from 'node:child_process';
import { existsSync, writeFileSync, mkdirSync } from 'node:fs';
import { createInterface } from 'node:readline';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
process.chdir(ROOT);

// git 的回傳值：成功時給 stdout 字串，失敗時給 null（呼叫端自己決定要不要當錯誤）
// -c core.quotepath=false：不然中文檔名會被印成 \346\233\264 這種八進位轉義
const GIT = ['-c', 'core.quotepath=false'];
function git(...args) {
  try {
    return execFileSync('git', [...GIT, ...args], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
  } catch {
    return null;
  }
}
// 要讓使用者看到 git 自己的進度輸出時用這個（fetch、checkout）
// stdin 一定要給 ignore，不能 inherit：readline 已經接管 stdin，
// 讓 git 也去搶會兩邊互卡，整支腳本停在 fetch 那一步不動
function gitLoud(...args) {
  return spawnSync('git', [...GIT, ...args], { stdio: ['ignore', 'inherit', 'inherit'] }).status === 0;
}

// 全程共用同一個 readline。每問一次就新建一個的話，前一個 close 掉時會把
// stdin 已經緩衝的後續輸入一起丟掉，第二題之後永遠讀到空字串。
const rl = createInterface({ input: process.stdin, output: process.stdout });
let stdinEnded = false;
rl.on('close', () => { stdinEnded = true; });

// 自己排隊，不用 rl.question：readline 在管線模式下會把整批輸入一口氣
// 發成 line 事件，還沒問到的那幾行就直接掉了（測試時 A 選項永遠讀不到）。
const queued = [];   // 已經收到、還沒有人來拿的行
const waiting = [];  // 已經在問、還沒有行可以給的 resolve
rl.on('line', (l) => {
  const v = l.trim();
  if (waiting.length) waiting.shift()(v);
  else queued.push(v);
});

function ask(question) {
  process.stdout.write(question);
  if (queued.length) {
    const v = queued.shift();
    console.log(v);
    return Promise.resolve(v);
  }
  // stdin 已經結束就直接回空字串，不然 Promise 會永遠掛著
  if (stdinEnded) { console.log(); return Promise.resolve(''); }
  return new Promise((r) => {
    waiting.push(r);
    rl.once('close', () => r(''));
  });
}
// 走到底或中途 exit 都要把 rl 關掉，不然 node 不會結束
function bye(code = 0) { rl.close(); process.exit(code); }

function die(msg) {
  console.log(`\n[錯誤] ${msg}\n`);
  bye(1);
}

console.log('\n============================================');
console.log('  幻想鄉 3D —— 分支更新器');
console.log('============================================\n');

// ---- 前置檢查 ----
if (git('--version') === null) {
  die('找不到 git。\n\n請先到 https://git-scm.com/ 下載安裝（一路按下一步即可），\n安裝完關掉這個視窗，重新執行一次。');
}
if (!existsSync('.git')) {
  die('這個資料夾不是 git 儲存庫。\n\n請先執行「安裝.bat」把專案抓下來，再用這個腳本切分支。');
}

// ---- 有沒有沒提交的本機修改 ----
// --untracked-files=no：你隨手在資料夾裡放筆記或截圖不該擋住更新
let force = false;  // 使用者點頭要丟掉本機修改，切換時就得帶 -f
const dirty = (git('status', '--porcelain', '--untracked-files=no') || '').trim();
if (dirty) {
  console.log('[注意] 你有還沒提交的本機修改：\n');
  console.log(dirty.split('\n').map((l) => '  ' + l).join('\n'));
  console.log('\n切換分支會覆蓋掉這些修改。要保留就關掉這個視窗，');
  console.log('執行 git stash 或 git commit，再重跑一次。\n');
  const go = await ask('確定要繼續並丟掉這些修改嗎？（輸入 y 再按 Enter）：');
  if (go.toLowerCase() !== 'y') {
    console.log('已取消。');
    bye(0);
  }
  // 說了要丟掉就真的要丟掉。少了這個旗標，下面跑的是普通 checkout，
  // git 只會印一堆 "would be overwritten" 然後 Aborting —— 提示騙人。
  force = true;
  console.log();
}

// ---- 抓所有分支 ----
console.log('[1/3] 從 GitHub 抓取所有分支...');
if (!gitLoud('fetch', 'origin', '--prune')) {
  die('抓取失敗。可能的原因：\n  - 沒有網路\n  - 這是私有儲存庫，需要先在 git 設定好 GitHub 帳號');
}
console.log('      完成。\n');

// ---- 列出來 ----
// 用 \t 當分隔符，提交訊息本身有空格，split 成三段最穩
// 用完整的 %(refname) 而不是 :short —— refs/remotes/origin/HEAD 的 short
// 是「origin」，剝不掉也濾不掉，會被當成一條叫 origin 的分支列進選單。
const FMT = '%(refname)\t%(committerdate:short)\t%(subject)';
const rows = (git('for-each-ref', '--sort=-committerdate', `--format=${FMT}`, 'refs/remotes/origin') || '')
  .split('\n')
  .filter(Boolean)
  .map((line) => {
    const [ref, date, ...rest] = line.split('\t');
    return { name: ref.replace(/^refs\/remotes\/origin\//, ''), date, subject: rest.join('\t') };
  })
  .filter((b) => b.name !== 'HEAD');

if (!rows.length) die('一條分支都沒抓到，這不正常。');

const current = (git('rev-parse', '--abbrev-ref', 'HEAD') || '').trim();

console.log('[2/3] GitHub 上的分支（由新到舊）：\n');
rows.forEach((b, i) => {
  const here = b.name === current ? '  ← 你現在在這條' : '';
  console.log(`  [${i + 1}]  ${b.name}${here}`);
  console.log(`       ${b.date}   ${b.subject}\n`);
});
console.log('  [A]  全部分支各解一份到 branches/ 資料夾底下\n');

// ---- 選 ----
const sel = (await ask('請輸入編號（直接按 Enter = 1，最新的那條）：')) || '1';

if (sel.toLowerCase() === 'a') {
  console.log('\n[3/3] 把每一條分支各解一份到 branches/ 底下...\n');
  console.log('  用的是 git worktree：同一份 .git 歷史，多個工作目錄。');
  console.log('  不會重複下載，但每一份的檔案是實體存在的，');
  console.log(`  ${rows.length} 條分支大概會吃掉數百 MB 磁碟空間。\n`);

  if (!existsSync('branches')) mkdirSync('branches');
  let made = 0;
  for (const b of rows) {
    // 資料夾名不能有斜線，claude/xxx 會變成 claude-xxx
    const dir = `branches/${b.name.replace(/\//g, '-')}`;
    if (existsSync(dir)) {
      // 已經解過了就地快進，--detach 出來的 worktree 不能 pull，用 reset
      const ok = spawnSync('git', ['-C', dir, 'reset', '--hard', `origin/${b.name}`],
        { stdio: ['ignore', 'ignore', 'ignore'] }).status === 0;
      console.log(`  [${ok ? '更新' : '略過'}] ${dir}`);
    } else if (git('worktree', 'add', dir, `origin/${b.name}`, '--detach') !== null) {
      console.log(`  [建立] ${dir}`);
      made++;
    } else {
      console.log(`  [失敗] ${dir}`);
      continue;
    }
    // 每一份都寫自己的 .branch，不然裡面的 play.bat 會預設去追 main，
    // 等於你點開哪一份都被換成 main —— 整個 [A] 就白解了
    writeFileSync(`${dir}/.branch`, b.name + '\n', 'utf8');
  }

  console.log(`\n============================================`);
  console.log(`  完成，這次新解出 ${made} 條`);
  console.log(`============================================\n`);
  console.log('  每個資料夾都是一份完整可執行的遊戲。');
  console.log('  要玩哪一條就進去點裡面的 play.bat。\n');
  console.log('  branches/ 底下那幾份不會自動更新，想更新就再跑一次按 A。');
  console.log('  要整批砍掉：關掉遊戲後刪除 branches 資料夾，');
  console.log('  再回到這裡執行 git worktree prune 清乾淨。\n');
  await ask('按 Enter 關閉...');
  bye(0);
}

const idx = Number(sel);
const target = rows[idx - 1];
if (!target) die(`沒有編號 ${sel} 這個選項。`);

console.log(`\n[3/3] 切換到 ${target.name} ...`);
function checkout(f) {
  return gitLoud('checkout', ...(f ? ['-f'] : []), '-B', target.name, `origin/${target.name}`);
}
if (!checkout(force)) {
  // 最常見的失敗：你把新版的檔案直接解壓縮蓋在資料夾上，那些檔案對 git
  // 來說是「未追蹤」的，普通 checkout 不敢覆蓋。-f 連未追蹤的一起蓋掉。
  console.log('\n上面那串 git 訊息的意思是：這些檔案會被覆蓋掉，所以它停手了。');
  console.log('如果那些檔案只是你解壓縮蓋上去的、或改壞想丟掉，就選強制覆蓋。');
  console.log('要保留的話現在關掉視窗，把檔案複製到別的地方再回來。\n');
  const f = await ask('強制覆蓋並繼續嗎？（輸入 y 再按 Enter）：');
  if (f.toLowerCase() !== 'y') {
    console.log('已取消。');
    bye(0);
  }
  console.log();
  if (!checkout(true)) die('強制切換還是失敗了。');
}
git('branch', `--set-upstream-to=origin/${target.name}`);

// 記住選擇，play.bat / play.sh 會讀這個檔
writeFileSync('.branch', target.name + '\n', 'utf8');

console.log('\n============================================');
console.log(`  已更新到 ${target.name}`);
console.log('============================================\n');
console.log(git('log', '-1', '--date=format:%m-%d %H:%M', '--pretty=format:  目前版本：%h  %ad  %s') || '');
console.log('\n  之後直接點 play.bat 就會跟著這條分支更新。');
console.log('  要換回 main 就再跑一次這個腳本。\n');

const play = await ask('現在開始遊玩嗎？（直接按 Enter = 是，輸入 n = 否）：');
if (play.toLowerCase() === 'n') bye(0);
rl.close();

// play.bat 是 Windows 專用；其他系統走 play.sh
const isWin = process.platform === 'win32';
spawnSync(isWin ? 'cmd' : 'bash', isWin ? ['/c', 'play.bat'] : ['play.sh'], { stdio: 'inherit' });
