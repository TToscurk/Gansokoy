# blockout —— 烤出來的佈局底稿（不進版控）

這個資料夾放 three.js 版地圖烤成的 `.glb`（每張約 10–110MB，共 300+MB，
所以 gitignore）。拉下 repo 後要自己烤一次：

```
npm install
node tools/export-godot.mjs
```

詳見 `docs/godot-migration.md`。
