// 任務資料 —— 手寫分支任務樹。
//
// 每個任務是一組「節點」（stage），節點之間用 next 條件連接。
// 引擎（manager.js）不理解任何任務的具體內容，只認得三種觸發：
//   onTalkTo:  跟指定 NPC 對話時推進
//   onEnter:   走進指定地區時推進
//   branch:    依條件（目前支援 isNight）選擇下一個節點——這是「分支」的部分，
//              同一個節點可以依當下狀態走向不同分支，不是單純的線性清單。
//
// giver 決定「誰會在對話裡提到這個任務」；stage.npcHint 若有值，
// 玩家跟該 NPC 對話時會在原本的閒聊之前插一句任務提示。
//
// 主線追加欄位：
//   main: true        主線旗標（日誌/toast 標示）
//   stage.scene       { npcId: [lines...] } 整場對話取代閒聊，播過不重播。
//                     注意要放在「對話發生時的作用中節點」上——也就是
//                     next.onTalkTo 指向該 NPC 的那個節點，這樣劇情播完
//                     的同一通對話就會順便推進，玩家不用多講一次。
//   start.after       前置任務 id，對方完成的瞬間自動開啟（章節接龍）

export const QUESTS = [
  // =========================================================================
  // 主線第一章：無名之劍
  // 以繼國緣一開場。調性依故事聖經：靜謐、成熟、不喧鬧；
  // 伏筆：「走進來的東西」＝藍染（鏡花水月）、紅魔館窗外＝芙蘭奪還事件的前兆、
  // 緣一結尾按上刀柄＝天照加護線的起手。本章只到「察覺」，不開打。
  // =========================================================================
  {
    id: 'main_ch1_nameless_blade',
    title: '主線一章：無名之劍',
    main: true,
    giver: 'yoriichi',
    start: { npc: 'yoriichi' },
    stages: {
      start: {
        objective: '緣一察覺空氣中有一絲不屬於這裡的味道。替他走一趟博麗神社，問問靈夢。',
        scene: {
          yoriichi: [
            '（黃昏的里緣。他獨自坐在草上，刀橫放在膝前，像一道安靜的界線。）',
            '……你來了。坐吧，不忙的話。',
            '這裡的黃昏很好。孩子回家，炊煙升起來，沒有人需要回頭看身後。',
            '我原本以為，在這樣的地方，刀可以一直放在膝上不用拿起來。',
            '……可是今晚，空氣裡有一絲不屬於這裡的味道。',
            '很淡。像很遠很遠的地方，有人把刀拔出了一寸——又收回去了。',
            '博麗的巫女對這種事最敏感。替我走一趟吧。',
            '我還想……再坐一下。趁這裡還安靜的時候。',
          ],
          reimu: [
            '……你身上有那個男人的味道。算了，坐。說吧，什麼事。',
            '結界晃了一下？哼，你們一個兩個，鼻子都比狗還靈。',
            '……是真的。三天前的夜裡，結界「晃」了一次。不是破，是晃。',
            '像水面被指尖點了一下。什麼都沒有進來的樣子，可是波紋散得很遠。',
            '那種感覺不屬於外面，也不屬於這裡。我退治不了「不屬於任何地方」的東西。',
            '去找那個境界的妖怪吧，她應該還窩在神社的陰涼處睡午覺。',
            '這種帳，只有她查得到。',
          ],
        },
        next: { onTalkTo: 'reimu', goto: 'asked_reimu' },
      },
      asked_reimu: {
        objective: '靈夢也感覺到了——結界「晃」了一下。去神社境內找八雲紫問清楚。',
        scene: {
          yukari: [
            '哎呀。是被巫女趕來的，還是被那位劍士拜託來的？',
            '……不用回答。你身上「事情的經過」，我一眼就看完了。',
            '是有東西穿過了境界。不是掉進來的——掉進來的東西，我這裡什麼都收。',
            '是「走進來」的。帶著意志，帶著目的地，還帶著禮貌。',
            '穿過去的那一瞬間，我只抓到一個殘響。',
            '像碎掉的水面，倒映著一朵不存在的花。',
            '——鏡花水月。如果你聽得懂這四個字，最好裝作不懂。',
            '它往紅色的洋館去了。替我看好那位劍士……他又要開始不睡了。',
          ],
        },
        next: { onTalkTo: 'yukari', goto: 'asked_yukari' },
      },
      asked_yukari: {
        objective: '紫證實有東西「走進」了幻想鄉，方向是紅魔館。親自去館裡看看。',
        next: { onEnter: 'sdm', goto: 'arrived_sdm' },
      },
      arrived_sdm: {
        objective: '紅魔館安靜得不對勁。找女僕長咲夜問問三天前夜裡的情形。',
        scene: {
          sakuya: [
            '歡迎光臨紅魔館。……不過，您挑了一個微妙的時期來訪。',
            '三天前的夜裡，館裡的鐘停了七秒。只有我注意到——時間畢竟是我的領域。',
            '那七秒之間，地下室走廊的門，開了一次，又關上了。',
            '沒有腳步聲。沒有氣息。監看的使魔什麼也沒拍到。',
            '芙蘭妹妹大人沒事。但是隔天，她若無其事地對我說——',
            '「昨晚有個拿刀的大哥哥，在窗外對我笑。他笑得很好看喔，像水裡的月亮。」',
            '……這座館的窗戶，離地三十公尺。',
            '請把這些話，一字不漏地帶給那位劍士先生。他聽得懂。',
          ],
        },
        next: { onTalkTo: 'sakuya', goto: 'asked_sakuya' },
      },
      asked_sakuya: {
        objective: '鐘停了七秒，地下室的門開過一次。把這些話原封不動帶回給緣一。',
        scene: {
          yoriichi: [
            '（他站在河邊。聽完你的話，很久、很久沒有出聲。）',
            '鏡花水月……讓人看見「想看到的東西」的刀。',
            '握著那把刀的人，把謊言當呼吸。他笑著的時候，已經想好要拿走什麼了。',
            '他的目標不是這座館。是館裡的「什麼」……或者，「誰」。',
            '（他的手，輕輕按上了刀柄。這是你第一次看見他碰刀。）',
            '我曾經晚回家過一次。只是一次。然後，就什麼都沒有了。',
            '……這次不會。',
            '回去休息吧。今晚的幻想鄉，有我守著。',
          ],
        },
        next: { onTalkTo: 'yoriichi', goto: 'done' },
      },
      done: {
        objective: '主線第一章完成。',
        npcHint: { yoriichi: '（他對你點了點頭。刀已經不在膝上——佩回腰間了。）' },
        complete: true,
      },
    },
  },

  {
    id: 'erased_records',
    title: '被抹去的記錄',
    giver: 'keine',
    start: { npc: 'keine' },
    stages: {
      start: {
        objective: '慧音提到一位查不到任何記錄的劍士。去人間之里找他談談。',
        npcHint: { keine: '你要找的人就住在里的另一頭。小心一點——不是他危險，是他的過去太安靜了。' },
        next: { onTalkTo: 'yoriichi', goto: 'branch_time' },
      },
      branch_time: {
        objective: '（決定接下來要找誰打聽）',
        next: {
          branch: 'isNight',
          ifTrue: 'talked_yoriichi_night',
          ifFalse: 'talked_yoriichi_day',
        },
      },
      talked_yoriichi_day: {
        objective: '白天：文到處打聽新聞。去問問射命丸文，她說不定查過什麼。',
        npcHint: { yoriichi: '（他只是靜靜聽著，沒有多說什麼。）' },
        next: { onTalkTo: 'aya', goto: 'talked_reporter' },
      },
      talked_yoriichi_night: {
        objective: '夜裡：不如先回神社，靈夢對「來歷不明的東西」總有些直覺。',
        npcHint: { yoriichi: '（夜色中他的輪廓很安靜，像是隨時會融進黑暗裡。）' },
        next: { onTalkTo: 'reimu', goto: 'talked_reporter' },
      },
      talked_reporter: {
        objective: '該知道的都問過了。回去告訴慧音妳查到的事。',
        npcHint: {
          aya: '這條新聞我封存很久了——妳既然也在查，代表這件事早晚會有答案的。',
          reimu: '……那種味道我聞得出來。不是妖怪，也不是神明。是「被留下來的人」的味道。',
        },
        next: { onTalkTo: 'keine', goto: 'done' },
      },
      done: {
        objective: '任務完成。',
        npcHint: { keine: '謝謝妳願意幫我確認。至少現在，這座里裡有人真的記得他存在過。' },
        complete: true,
      },
    },
  },

  {
    id: 'shrine_pilgrimage',
    title: '香油錢的巡禮',
    giver: 'reimu',
    start: { npc: 'reimu' },
    stages: {
      start: {
        objective: '靈夢在抱怨神社的香油錢不夠。順路去博麗神社、守矢神社、命蓮寺各留一點心意吧。',
        npcHint: { reimu: '不用捐大錢，意思到了就好……但意思最好大一點。' },
        next: { onEnter: 'shrine', goto: 'visit_1' },
      },
      visit_1: {
        objective: '博麗神社去過了。接著是守矢神社或命蓮寺，順序不拘。',
        next: { onEnter: 'moriya', goto: 'visit_2' },
      },
      visit_2: {
        objective: '兩間都去過了。最後一間：命蓮寺。',
        next: { onEnter: 'myouren', goto: 'visit_3' },
      },
      visit_3: {
        objective: '三間都巡過了。回博麗神社跟靈夢報告一聲。',
        next: { onTalkTo: 'reimu', goto: 'done' },
      },
      done: {
        objective: '任務完成。',
        npcHint: { reimu: '看吧，其實沒有很麻煩。……下個月還要麻煩妳一次。' },
        complete: true,
      },
    },
  },

  {
    id: 'missing_curio',
    title: '不翼而飛的貨物',
    giver: 'rinnosuke',
    start: { npc: 'rinnosuke' },
    stages: {
      start: {
        objective: '霖之助店裡少了一件外來的道具。他懷疑是魔理沙「借」走的。去魔法之森問問。',
        npcHint: { rinnosuke: '不是要妳興師問罪，就……幫我問一聲『到底是不是妳』。' },
        next: { onTalkTo: 'marisa', goto: 'confronted' },
      },
      confronted: {
        objective: '問完魔理沙了。回香霖堂跟霖之助說結果。',
        npcHint: { marisa: '……好啦好啦，是我借的！我又不是不還！' },
        next: { onTalkTo: 'rinnosuke', goto: 'done' },
      },
      done: {
        objective: '任務完成。',
        npcHint: { rinnosuke: '果然是她。謝了——這種事我自己去問，一定又要吵一架。' },
        complete: true,
      },
    },
  },
];

export const QUEST_BY_ID = Object.fromEntries(QUESTS.map(q => [q.id, q]));
