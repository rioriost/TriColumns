const params = new URLSearchParams(window.location.search);
const language = params.get("lang") === "ja" ? "ja" : "en";
const scenario = params.get("scenario") === "research" ? "research" : "workspace";
const column = Math.min(3, Math.max(1, Number(params.get("column")) || 1));

const content = {
  en: {
    demo: "Demo Content",
    workspace: [
      {
        section: "Morning workspace",
        title: "Signal Briefing",
        metrics: [["12", "new signals"], ["4", "saved"], ["3", "topics"]],
        items: [
          ["NW", "Northwind Desk", "8 min ago", "Urban mobility", "A quieter transit corridor opens downtown", "The new route pairs electric service with a planted pedestrian spine and safer crossings.", "city-transit.png", "City systems", "6 sources", "blue"],
          ["FG", "Field Grid", "24 min ago", "Clean energy", "Coastal generation reaches a seasonal high", "Solar and wind output rose together after several clear, breezy days along the coast.", "coastal-energy.png", "Energy", "Updated today", "gold"],
          ["CL", "Civic Lab", "41 min ago", "Public space", "Three small changes that improved the plaza", "More shade, movable seating, and clearer walking routes helped extend average visits.", null, "Places", "4 notes", "coral"]
        ]
      },
      {
        section: "Team workspace",
        title: "Activity",
        metrics: [["7", "unread"], ["5", "mentions"], ["2", "reviews"]],
        items: [
          ["AK", "Aki Kondo", "2 min ago", "Mention", "Added context to the mobility brief", "Aki linked the latest ridership table and marked two figures for review.", null, "Review", "Open", "coral", "focus"],
          ["MS", "Mina Sato", "11 min ago", "Saved", "Filed the energy outlook", "The coastal generation note is now in the July research collection.", null, "Research", "Filed", "gold", "done"],
          ["JT", "Jun Takeda", "18 min ago", "Comment", "Replied to the public-space note", "The accessibility audit is complete; one entrance still needs updated signage.", null, "Planning", "2 replies", "blue"],
          ["RM", "Rin Mori", "36 min ago", "Assignment", "Requested a short design summary", "Prepare three observations from the prototype review before tomorrow morning.", null, "Design", "Due tomorrow", "coral", "focus"]
        ]
      },
      {
        section: "Live collection",
        title: "Today",
        metrics: [["18", "updates"], ["9", "authors"], ["6", "notes"]],
        items: [
          ["ST", "Studio Thread", "5 min ago", "Product design", "A modular control study enters testing", "The team reduced visual weight while keeping every frequently used action within reach.", "design-workbench.png", "Design", "Prototype 04", "coral"],
          ["ER", "Evening Review", "19 min ago", "Research", "What readers saved this afternoon", "Compact explainers and primary sources led the reading list across all three collections.", null, "Reading", "8 saves", "blue"],
          ["MC", "Metro Commons", "33 min ago", "Community", "Neighborhood workshop notes are ready", "Participants prioritized safer crossings, shade, and more flexible gathering areas.", null, "Community", "12 notes", "gold"]
        ]
      }
    ],
    research: [
      {
        section: "Research workspace",
        title: "Sources",
        metrics: [["24", "sources"], ["8", "primary"], ["5", "new"]],
        items: [
          ["UA", "Urban Archive", "Today", "Dataset", "Transit access indicators: 2026 edition", "A neighborhood-level dataset covering service frequency, walking distance, and transfer time.", "city-transit.png", "Primary source", "CSV + notes", "blue", "done"],
          ["CE", "Coastal Energy Lab", "Yesterday", "Field report", "Complementary output across mixed renewables", "A six-month observation of coastal solar and wind production under changing conditions.", "coastal-energy.png", "Field study", "18 pages", "gold"],
          ["DM", "Design Methods", "Jul 12", "Reference", "A practical guide to modular interface studies", "Methods for comparing control density, hierarchy, and repeated workflows.", null, "Reference", "Saved", "coral"]
        ]
      },
      {
        section: "Research workspace",
        title: "Reading Queue",
        metrics: [["9", "queued"], ["3", "reading"], ["14", "finished"]],
        items: [
          ["01", "Priority reading", "22 min left", "In progress", "Designing information views for narrow spaces", "How stable hierarchy and restrained controls improve scanning in dense operational layouts.", null, "Interface", "68% read", "blue", "focus", 68],
          ["02", "Next in queue", "12 min", "Queued", "Measuring the value of mixed transit networks", "A concise model for comparing frequency, coverage, reliability, and transfer cost.", null, "Mobility", "Start next", "gold", "", 0],
          ["03", "Completed", "Read yesterday", "Finished", "Field notes from a coastal microgrid", "Observations on balancing variable generation with local storage and flexible demand.", null, "Energy", "6 highlights", "coral", "done", 100],
          ["04", "Saved for later", "18 min", "Queued", "Making project reviews more decisive", "A lightweight framework for turning prototype observations into concrete next steps.", null, "Practice", "Saved", "blue"]
        ]
      },
      {
        section: "Research workspace",
        title: "Notes",
        metrics: [["16", "notes"], ["7", "linked"], ["3", "drafts"]],
        items: [
          ["A1", "Working synthesis", "Updated 4 min ago", "Key finding", "Narrow views reward deliberate information hierarchy", "The strongest examples keep identity, status, and the next action visible without flattening the content.", "design-workbench.png", "Synthesis", "3 linked sources", "coral", "focus"],
          ["B2", "Observation", "Updated 17 min ago", "Pattern", "Parallel sources make comparison faster", "Keeping related pages visible at once reduces navigation overhead during active research.", null, "Workflow", "2 references", "blue", "done"],
          ["C3", "Open question", "Updated 31 min ago", "To verify", "Which updates need immediate attention?", "Separate ambient changes from direct mentions and time-sensitive assignments.", null, "Next step", "Review Friday", "gold"]
        ]
      }
    ]
  },
  ja: {
    demo: "サンプルコンテンツ",
    workspace: [
      {
        section: "朝のワークスペース",
        title: "注目トピック",
        metrics: [["12", "新着"], ["4", "保存済み"], ["3", "トピック"]],
        items: [
          ["NW", "ノースウインド編集部", "8分前", "都市交通", "緑豊かな都心に静かな交通軸が開通", "電動車両の新路線に、歩行空間と安全な交差点を組み合わせた計画です。", "city-transit.png", "都市システム", "6件の資料", "blue"],
          ["FG", "フィールドグリッド", "24分前", "クリーンエネルギー", "沿岸部の発電量が今季最高を記録", "晴天と適度な風が続き、太陽光と風力の出力が同時に上昇しました。", "coastal-energy.png", "エネルギー", "本日更新", "gold"],
          ["CL", "シビックラボ", "41分前", "公共空間", "広場の滞在時間を伸ばした3つの改善", "日陰、移動できる椅子、わかりやすい動線が利用者の行動を変えました。", null, "まちづくり", "4件のメモ", "coral"]
        ]
      },
      {
        section: "チームワークスペース",
        title: "アクティビティ",
        metrics: [["7", "未読"], ["5", "メンション"], ["2", "レビュー"]],
        items: [
          ["AK", "近藤アキ", "2分前", "メンション", "交通レポートに資料を追加", "最新の利用者数データをリンクし、確認が必要な数値を2点マークしました。", null, "レビュー", "確認する", "coral", "focus"],
          ["MS", "佐藤ミナ", "11分前", "保存", "エネルギー見通しを整理", "沿岸発電のメモを7月のリサーチコレクションに保存しました。", null, "リサーチ", "保存済み", "gold", "done"],
          ["JT", "武田ジュン", "18分前", "コメント", "公共空間メモに返信", "アクセシビリティ調査が完了し、入口1か所の案内更新が残っています。", null, "計画", "2件の返信", "blue"],
          ["RM", "森リン", "36分前", "依頼", "デザイン要約を依頼", "明日の朝までに、試作レビューから3つの観察点をまとめます。", null, "デザイン", "明日まで", "coral", "focus"]
        ]
      },
      {
        section: "ライブコレクション",
        title: "今日のフィード",
        metrics: [["18", "更新"], ["9", "投稿者"], ["6", "メモ"]],
        items: [
          ["ST", "スタジオスレッド", "5分前", "プロダクトデザイン", "モジュール式コントロールの検証を開始", "よく使う操作を手の届く範囲に保ちながら、画面の情報量を整理しました。", "design-workbench.png", "デザイン", "試作04", "coral"],
          ["ER", "イブニングレビュー", "19分前", "リサーチ", "午後に多く保存された記事", "簡潔な解説と一次資料が、3つのコレクションで上位になりました。", null, "リーディング", "8件の保存", "blue"],
          ["MC", "メトロコモンズ", "33分前", "コミュニティ", "地域ワークショップの記録を公開", "参加者は安全な交差点、日陰、柔軟に使える交流空間を優先しました。", null, "コミュニティ", "12件のメモ", "gold"]
        ]
      }
    ],
    research: [
      {
        section: "リサーチワークスペース",
        title: "情報源",
        metrics: [["24", "資料"], ["8", "一次資料"], ["5", "新着"]],
        items: [
          ["UA", "都市アーカイブ", "今日", "データセット", "交通アクセス指標 2026年版", "運行頻度、徒歩距離、乗換時間を地域別にまとめたデータセットです。", "city-transit.png", "一次資料", "CSV・注記", "blue", "done"],
          ["CE", "沿岸エネルギー研究所", "昨日", "調査報告", "複合型再生可能エネルギーの出力", "沿岸部の太陽光と風力を6か月間観測し、天候による変化を分析しました。", "coastal-energy.png", "現地調査", "18ページ", "gold"],
          ["DM", "デザインメソッド", "7月12日", "参考資料", "モジュール式UI検証の実践ガイド", "操作密度、情報の階層、繰り返し作業を比較するための手法です。", null, "参考資料", "保存済み", "coral"]
        ]
      },
      {
        section: "リサーチワークスペース",
        title: "リーディングリスト",
        metrics: [["9", "未読"], ["3", "読書中"], ["14", "完了"]],
        items: [
          ["01", "優先して読む", "残り22分", "読書中", "狭い画面に適した情報設計", "安定した階層と控えめな操作部品が、高密度な画面の一覧性を改善します。", null, "インターフェース", "68%読了", "blue", "focus", 68],
          ["02", "次に読む", "12分", "未読", "複合交通網の価値を測る", "運行頻度、範囲、信頼性、乗換コストを比較するための簡潔なモデルです。", null, "都市交通", "次に開始", "gold", "", 0],
          ["03", "読了", "昨日", "完了", "沿岸マイクログリッドの現地記録", "変動する発電量を蓄電と柔軟な需要で調整した事例を紹介します。", null, "エネルギー", "6件のハイライト", "coral", "done", 100],
          ["04", "あとで読む", "18分", "未読", "プロジェクトレビューを明確にする", "試作の観察結果を具体的な次の作業に変える軽量なフレームワークです。", null, "実務", "保存済み", "blue"]
        ]
      },
      {
        section: "リサーチワークスペース",
        title: "ノート",
        metrics: [["16", "メモ"], ["7", "リンク済み"], ["3", "下書き"]],
        items: [
          ["A1", "作業中のまとめ", "4分前に更新", "重要な発見", "狭い画面では情報の階層が重要", "優れた例では、発信元、状態、次の操作が見えたまま、内容の強弱が保たれています。", "design-workbench.png", "まとめ", "3件の関連資料", "coral", "focus"],
          ["B2", "観察", "17分前に更新", "パターン", "並列表示は比較を速くする", "関連ページを同時に表示すると、調査中の画面切り替えを減らせます。", null, "ワークフロー", "2件の参照", "blue", "done"],
          ["C3", "確認事項", "31分前に更新", "要検証", "すぐに確認すべき更新は何か", "通常の更新と、直接のメンションや期限のある依頼を分けて考えます。", null, "次の作業", "金曜に確認", "gold"]
        ]
      }
    ]
  }
};

const page = content[language][scenario][column - 1];
document.documentElement.lang = language;
document.querySelector("#section-label").textContent = page.section;
document.querySelector("#page-title").textContent = page.title;
document.querySelector("#demo-badge").textContent = content[language].demo;

const feed = document.querySelector("#feed");
const summary = document.createElement("section");
summary.className = "summary-strip";
summary.setAttribute("aria-label", language === "ja" ? "概要" : "Summary");
summary.innerHTML = page.metrics.map(([value, label]) => `
  <div class="metric">
    <span class="metric-value">${value}</span>
    <span class="metric-label">${label}</span>
  </div>`).join("");
feed.append(summary);

page.items.forEach((item) => {
  const [initials, author, time, kind, title, copy, image, tag, detail, avatarClass, statusClass = "", progress] = item;
  const article = document.createElement("article");
  article.className = "feed-item";
  article.innerHTML = `
    <div class="item-body">
      <div class="item-meta">
        <span class="avatar ${avatarClass}">${initials}</span>
        <span class="meta-copy">
          <span class="author">${author}</span>
          <span class="time">${time}</span>
        </span>
        <span class="status ${statusClass}">${kind}</span>
      </div>
      <h2 class="item-title">${title}</h2>
      <p class="item-copy">${copy}</p>
      ${typeof progress === "number" ? `<div class="progress" aria-label="${progress}%"><span style="width:${progress}%"></span></div>` : ""}
      <div class="tag-row"><span class="tag">${tag}</span><span class="tag">${detail}</span></div>
    </div>
    ${image ? `<img class="item-image" src="assets/${image}" alt="">` : ""}
    <footer class="item-footer">
      <span>${language === "ja" ? "架空のデモデータ" : "Fictional demo data"}</span>
      <span>${String(column).padStart(2, "0")}</span>
    </footer>`;
  feed.append(article);
});
