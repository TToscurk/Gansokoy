#!/usr/bin/env node
// ============================================================
//  幻想鄉 3D —— 一鍵更新並開始遊玩
//
//  做三件事：
//    1. 從 GitHub 拉最新的程式碼（跟哪一條分支由 .branch 決定，預設 main）
//    2. 啟動開發伺服器（dev-server.mjs，每個回應都送 no-store）
//    3. 開瀏覽器
//
//  為什麼一定要用 dev-server 而不是雙擊 index.html：
//    ES module + importmap 會被 file:// 協定擋掉，遊戲根本不會啟動。
//
//  為什麼這支是 Node 而不是批次檔：
//    cmd.exe 用「位元組」偏移量記住批次檔讀到哪，但 chcp 65001 之後
//    改用「字元」數算，中文一多就會飄到某一行的中間開始執行。
//    play.bat 現在只剩純 ASCII 的殼，中文全在這裡。
// ============================================================
import { execFileSync, spawnSync, spawn } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
process.chdir(ROOT);

const PORT = Number(process.argv[2]) || 5603;
const URL = `http://localhost:${PORT}`;

// -c core.quotepath=false：不然中文檔名會被印成 \346\233\264 這種八進位轉義
function git(...args) {
  try {
    return execFileSync('git', ['-c', 'core.quotepath=false', ...args],
      { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
  } catch {
    return null;
  }
}

console.log('\n============================================');
console.log('  幻想鄉 3D');
console.log('============================================\n');

update();

function update() {
  if (git('--version') === null) {
    console.log('[略過更新] 找不到 git，直接用現有的檔案啟動。');
    console.log('           想自動更新的話請安裝 https://git-scm.com/\n');
    return;
  }
  if (!existsSync('.git')) {
    console.log('[略過更新] 這個資料夾不是 git 儲存庫，直接用現有的檔案啟動。\n');
    return;
  }

  // 要跟哪一條分支：更新.bat 選完會把分支名寫進 .branch
  let branch = 'main';
  if (existsSync('.branch')) {
    const saved = readFileSync('.branch', 'utf8').split('\n')[0].trim();
    if (saved) branch = saved;
  }

  // 有沒有改到「已追蹤的檔案」？有的話不要硬蓋掉你的修改。
  // --untracked-files=no 是關鍵：你隨手在資料夾裡放一個筆記或截圖
  // 不該讓自動更新從此停擺，而 --ff-only 本來就不會動到未追蹤的檔案。
  const dirty = (git('status', '--porcelain', '--untracked-files=no') || '').trim();
  if (dirty) {
    console.log('[注意] 你有還沒提交的本機修改，這次不自動更新：\n');
    console.log(dirty.split('\n').map((l) => '  ' + l).join('\n'));
    console.log('\n       要保留修改就先 git stash 或 git commit，再重跑一次。\n');
    return;
  }

  console.log(`[1/3] 從 GitHub 抓取最新版本（分支：${branch}）...`);
  if (git('fetch', 'origin', branch) === null) {
    console.log('      抓取失敗（可能是沒有網路）。用現有的檔案啟動。\n');
    return;
  }

  // 本地還沒有這條分支的話（例如 更新.bat 剛換過）順手建出來
  if (git('checkout', branch) === null) git('checkout', '-B', branch, `origin/${branch}`);

  if (git('merge', '--ff-only', `origin/${branch}`) !== null) {
    console.log('      完成。');
  } else {
    console.log('      無法快進合併，可能本機有分岔的提交。用現有的檔案啟動。');
  }

  console.log('\n      目前版本：');
  console.log(git('log', '-1', '--date=format:%m-%d %H:%M', '--pretty=format:      %h  %ad  %s') || '');
  console.log();
}

console.log(`[2/3] 啟動伺服器（${URL}）...`);
console.log('[3/3] 開啟瀏覽器...\n');
console.log('---------------------------------------------------------');
console.log('  畫面沒更新的話，在瀏覽器按 Ctrl + Shift + R 強制重整。');
console.log('  要關掉遊戲：回到這個視窗按 Ctrl + C，或直接關掉視窗。');
console.log('---------------------------------------------------------\n');

// 伺服器起來之後再開瀏覽器，不然會看到「無法連線」
setTimeout(() => {
  const [cmd, args] = process.platform === 'win32' ? ['cmd', ['/c', 'start', '', URL]]
    : process.platform === 'darwin' ? ['open', [URL]]
    : ['xdg-open', [URL]];
  const p = spawn(cmd, args, { stdio: 'ignore', detached: true });
  p.on('error', () => console.log(`請自行開啟瀏覽器連到 ${URL}`));
  p.unref();
}, 1000);

spawnSync(process.execPath, ['tools/dev-server.mjs', '.', String(PORT)], { stdio: 'inherit' });
