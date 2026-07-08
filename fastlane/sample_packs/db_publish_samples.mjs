// 公開パックのサンプルを Neon (published_packs) に直接 upsert する。
// nickname=sumpo の実ユーザーに紐付ける（ja / en で user_id を分ける）。
//
// 実行（本番DBに書き込む。--commit を付けたときだけ実際に書く）:
//   cd /Users/sumpositive/GitLocal/azuki-api
//   node ../Packlin/fastlane/sample_packs/db_publish_samples.mjs          # ドライラン（何を入れるか表示のみ）
//   node ../Packlin/fastlane/sample_packs/db_publish_samples.mjs --commit # 実投入
//
// publish ルート(/api/packs/publish)の INSERT を再現する:
//   - payload は PackJsonDTO（createdAt は ISO8601 文字列に変換）
//   - payload_bytes = JSON.stringify(payload) のバイト長
//   - search_text = name + memo + group名/memo + item名/memo をスペース連結
//   - total_weight = Σ(weight × need)
//   - upsert キーは (user_id, source_pack_id)。source_pack_id は slug を使う。
//
import { readFileSync, readdirSync } from "node:fs";
import { neon } from "@neondatabase/serverless";

const COMMIT = process.argv.includes("--commit");

// サンプルは「管理者実機」の user_id に集約する（nickname=sumpo）。
// 実機から公開ギャラリーで削除・上書きできるようにするため、ja/en とも同じ user_id にする。
// （過去は ja=8856../en=57a0.. に分けていたが 2026-07-08 に 64f18c2e へ集約済み）
const DEVICE_USER_ID = "64f18c2e-be24-4535-bd13-c6d6bd1a67a9";

function loadDatabaseUrl() {
  const text = readFileSync("./.dev.vars", "utf8");
  const line = text.split(/\r?\n/).find((l) => l.startsWith("DATABASE_URL="));
  if (!line) throw new Error("DATABASE_URL not found in ./.dev.vars (run from azuki-api dir)");
  return line.slice("DATABASE_URL=".length).trim();
}

// .packlin（createdAt=数値）を publish payload 形式（createdAt=ISO8601）に整える
function toPayload(dto) {
  const iso = new Date((dto.createdAt ?? Date.now() / 1000) * 1000).toISOString();
  return { ...dto, createdAt: iso };
}

function buildSearchText(dto) {
  const parts = [dto.name, dto.memo];
  for (const g of dto.groups) {
    parts.push(g.name, g.memo ?? "");
    for (const it of g.items) parts.push(it.name, it.memo ?? "");
  }
  return parts.filter((s) => s && s.length).join(" ");
}

function totals(dto) {
  let items = 0, weight = 0;
  for (const g of dto.groups) {
    for (const it of g.items) { items += 1; weight += (it.weight ?? 0) * (it.need ?? 1); }
  }
  return { groupCount: dto.groups.length, itemCount: items, totalWeight: weight };
}

const SAMPLE_DIR = "../Packlin/fastlane/sample_packs";

async function main() {
  const sql = neon(loadDatabaseUrl());
  const enc = new TextEncoder();
  let planned = 0, wrote = 0;

  for (const lang of ["ja", "en"]) {
    const dir = `${SAMPLE_DIR}/${lang}`;
    const files = readdirSync(dir).filter((f) => f.endsWith(".packlin")).sort();
    for (const file of files) {
      const slug = file.replace(/\.packlin$/, "");
      const dto = JSON.parse(readFileSync(`${dir}/${file}`, "utf8"));
      const payload = toPayload(dto);
      const payloadText = JSON.stringify(payload);
      const payloadBytes = enc.encode(payloadText).length;
      const { groupCount, itemCount, totalWeight } = totals(dto);
      const searchText = buildSearchText(dto);
      // 実機集約後のキー形式に合わせる: sample-<slug>-<locale>
      // （同じ user_id に ja/en を共存させるため locale サフィックスで UNIQUE 衝突を回避）
      const sourcePackId = `sample-${slug}-${lang}`;
      const userId = DEVICE_USER_ID;

      planned += 1;
      console.log(`[${lang}] "${dto.name}"  G${groupCount} I${itemCount} ${totalWeight}g  src=${sourcePackId} bytes=${payloadBytes}`);

      if (!COMMIT) continue;

      await sql`
        INSERT INTO published_packs
          (id, user_id, source_pack_id, name, memo, locale, group_count, item_count, total_weight, payload, payload_bytes, search_text, status, created_at, updated_at)
        VALUES
          (${crypto.randomUUID()}, ${userId}, ${sourcePackId}, ${dto.name}, ${dto.memo ?? ""}, ${lang}, ${groupCount}, ${itemCount}, ${totalWeight}, ${payloadText}::jsonb, ${payloadBytes}, ${searchText}, 'public', NOW(), NOW())
        ON CONFLICT (user_id, source_pack_id) DO UPDATE SET
          name = EXCLUDED.name,
          memo = EXCLUDED.memo,
          locale = EXCLUDED.locale,
          group_count = EXCLUDED.group_count,
          item_count = EXCLUDED.item_count,
          total_weight = EXCLUDED.total_weight,
          payload = EXCLUDED.payload,
          payload_bytes = EXCLUDED.payload_bytes,
          search_text = EXCLUDED.search_text,
          status = 'public',
          updated_at = NOW()`;
      wrote += 1;
    }
  }

  console.log(`\n${COMMIT ? "COMMITTED" : "DRY-RUN"}: planned=${planned} wrote=${wrote}`);
  if (!COMMIT) console.log("→ 実際に投入するには --commit を付けて再実行");
}

main().catch((e) => { console.error(e); process.exit(1); });
