// 公開パックDBの状況を「読み取りだけ」で確認する調査スクリプト。
// DATABASE_URL は azuki-api/.dev.vars から読む（値は表示しない）。
//   実行: cd /Users/sumpositive/GitLocal/azuki-api
//         node ../Packlin/fastlane/sample_packs/db_inspect.mjs
import { readFileSync } from "node:fs";
import { neon } from "@neondatabase/serverless";

function loadDatabaseUrl() {
  const text = readFileSync(new URL("../../../azuki-api/.dev.vars", import.meta.url), "utf8");
  const line = text.split(/\r?\n/).find((l) => l.startsWith("DATABASE_URL="));
  if (!line) throw new Error("DATABASE_URL not found in .dev.vars");
  return line.slice("DATABASE_URL=".length).trim();
}

const sql = neon(loadDatabaseUrl());

// 1) nickname="sumpo" のユーザー
const users = await sql`SELECT user_id, nickname FROM users WHERE nickname = 'sumpo'`;
console.log("users with nickname=sumpo:", users.length);
for (const u of users) console.log("  user_id:", u.user_id);

// 2) その user_id が公開しているパック
if (users.length) {
  const uid = users[0].user_id;
  const packs = await sql`
    SELECT id, source_pack_id, name, locale, group_count, item_count, total_weight,
           download_count, status, created_at
    FROM published_packs WHERE user_id = ${uid}
    ORDER BY created_at DESC`;
  console.log(`\npublished_packs by sumpo: ${packs.length}`);
  for (const p of packs) {
    console.log(`  [${p.status}] ${p.name}  (${p.locale}) G${p.group_count} I${p.item_count} ${p.total_weight}g dl=${p.download_count} src=${p.source_pack_id}`);
  }
}

// 3) 公開パック総数（全ユーザー）
const total = await sql`SELECT COUNT(*)::int AS n FROM published_packs WHERE status='public'`;
console.log(`\ntotal public packs (all users): ${total[0].n}`);

// 4) published_packs の1件を payload 込みで見て、投入形式の参考にする
const sample = await sql`SELECT payload FROM published_packs LIMIT 1`;
if (sample.length) {
  const p = sample[0].payload;
  console.log("\nsample payload keys:", Object.keys(typeof p === "string" ? JSON.parse(p) : p));
}
