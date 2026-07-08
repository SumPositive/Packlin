// 公開パックの整理:
//  1. サンプル24件(sample-*)の user_id を実機 64f18c2e に集約する
//     （UNIQUE(user_id, source_pack_id) 衝突を避けるため source_pack_id に -<locale> を付ける）
//  2. 実機で誤登録した新規1件（64f18c2e の src=Pl8pVG68DtwARUnK7Zh9）を削除
//  3. 旧手動公開6件（sample- でない従来分）を削除して新サンプルに一本化
//
// 実行（本番DB。--commit を付けたときだけ書き込む）:
//   cd /Users/sumpositive/GitLocal/azuki-api
//   node ../Packlin/fastlane/sample_packs/db_reassign_and_cleanup.mjs           # ドライラン
//   node ../Packlin/fastlane/sample_packs/db_reassign_and_cleanup.mjs --commit  # 実行
//
import { readFileSync } from "node:fs";
import { neon } from "@neondatabase/serverless";

const COMMIT = process.argv.includes("--commit");
const DEVICE = "64f18c2e-be24-4535-bd13-c6d6bd1a67a9"; // 実機（管理者が実際に使っている端末）
const OLD_SAMPLE_USERS = [
  "8856f454-4345-41f1-9c11-eba24bd8f6df", // ja サンプル投入先
  "57a0e4a0-ada6-4cc8-a712-1f520f2ecd83", // en サンプル投入先
];
const MISPUBLISHED_SRC = "Pl8pVG68DtwARUnK7Zh9"; // 実機で取得→公開して増えた1件

const url = readFileSync("./.dev.vars", "utf8").split(/\r?\n/)
  .find((l) => l.startsWith("DATABASE_URL=")).slice("DATABASE_URL=".length).trim();
const sql = neon(url);

async function main() {
  // ---- 対象の把握 ----
  // 集約するサンプル（現状 8856../57a0.. に紐付く sample-*）
  const samples = await sql`
    SELECT id, user_id, source_pack_id, name, locale
    FROM published_packs
    WHERE source_pack_id LIKE 'sample-%'
      AND user_id = ANY(${OLD_SAMPLE_USERS})
    ORDER BY locale, source_pack_id`;
  console.log(`reassign samples -> ${DEVICE.slice(0,8)}: ${samples.length}`);

  // 誤登録1件
  const mis = await sql`
    SELECT id, name FROM published_packs
    WHERE user_id = ${DEVICE} AND source_pack_id = ${MISPUBLISHED_SRC}`;
  console.log(`mispublished to delete: ${mis.length}` + (mis[0] ? ` ("${mis[0].name}")` : ""));

  // 旧手動6件（sample- でない全公開）
  const oldManual = await sql`
    SELECT id, user_id, source_pack_id, name, locale FROM published_packs
    WHERE status='public' AND source_pack_id NOT LIKE 'sample-%'`;
  console.log(`old manual to delete: ${oldManual.length}`);
  for (const r of oldManual) console.log(`   - [${r.locale}] "${r.name}" (uid=${r.user_id.slice(0,8)})`);

  if (!COMMIT) {
    console.log("\nDRY-RUN. 実行するには --commit を付ける");
    console.log("集約後の source_pack_id 例: sample-hike_tent -> sample-hike_tent-ja / -en");
    return;
  }

  // ---- 1. サンプルを実機へ集約（source_pack_id に -locale を付けて衝突回避）----
  let reassigned = 0;
  for (const s of samples) {
    const newSrc = `${s.source_pack_id}-${s.locale}`; // 例 sample-hike_tent-ja
    await sql`
      UPDATE published_packs
      SET user_id = ${DEVICE}, source_pack_id = ${newSrc}, updated_at = NOW()
      WHERE id = ${s.id}`;
    reassigned += 1;
  }
  console.log(`reassigned: ${reassigned}`);

  // ---- 2. 誤登録1件を削除 ----
  const delMis = await sql`
    DELETE FROM published_packs
    WHERE user_id = ${DEVICE} AND source_pack_id = ${MISPUBLISHED_SRC}
    RETURNING id`;
  console.log(`deleted mispublished: ${delMis.length}`);

  // ---- 3. 旧手動6件を削除 ----
  const delOld = await sql`
    DELETE FROM published_packs
    WHERE status='public' AND source_pack_id NOT LIKE 'sample-%'
    RETURNING id`;
  console.log(`deleted old manual: ${delOld.length}`);

  console.log("\nCOMMITTED.");
}

main().catch((e) => { console.error(e); process.exit(1); });
