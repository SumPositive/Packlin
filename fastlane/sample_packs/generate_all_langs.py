#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
既存 generate_sample_packs.py（ja/en 38ジャンル）の構造をそのまま使い、
ja 名称を terms.py の訳語辞書で6言語(de/es/fr/it/ko/zh-Hant)に引いて 8 言語出力する。

- 訳が terms.py に無い名称は「未訳」として集計・表示する（訳し漏れ検出）。
  未訳がある言語のそのパックは、安全のため出力しない（中途半端な多言語混在を防ぐ）。
- 日本固有ジャンルは JP_ONLY / EU_EXTRA で対象言語を制御する。

使い方:
    cd /Users/sumpositive/GitLocal/Packlin
    python3 fastlane/sample_packs/generate_all_langs.py            # 全言語出力（未訳は集計表示）
    python3 fastlane/sample_packs/generate_all_langs.py --report   # 未訳語の一覧だけ表示（出力しない）
出力先: fastlane/sample_packs/<lang>/<slug>.packlin
"""
import json, os, sys, time, importlib.util

HERE = os.path.dirname(os.path.abspath(__file__))
LANGS_EXTRA = ["de", "es", "fr", "it", "ko", "zh-Hant"]  # ja/en は既存データが持つ
ALL_LANGS = ["ja", "en"] + LANGS_EXTRA

# 日本固有ジャンル: 非日本語では出さない（後で代替を足す）
JP_ONLY_SLUGS = {"hanami", "fireworks", "homecoming", "onsen_spa", "doujin_event", "fan_tour"}

def _load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m

gen = _load("gen", os.path.join(HERE, "generate_sample_packs.py"))
terms = _load("terms", os.path.join(HERE, "terms.py"))
TERMS = terms.TERMS

PRODUCT_NAME = gen.PRODUCT_NAME
COPYRIGHT = gen.COPYRIGHT
VERSION = gen.VERSION

missing = {}  # lang -> set(未訳のja名称)

def tr(ja_name, lang):
    """ja名称を lang に訳す。ja はそのまま。en は既存データ側で持つのでここには来ない想定。"""
    if lang == "ja":
        return ja_name
    entry = TERMS.get(ja_name)
    if entry and entry.get(lang):
        return entry[lang]
    missing.setdefault(lang, set()).add(ja_name)
    return None

def build_dto(pack, lang):
    """pack は gen の dict（name_ja/name_en/memo_ja/memo_en/groups[G{ja,en,items[I{ja,en,weight,need}]}]）"""
    def pack_name():
        if lang == "ja": return pack["name_ja"]
        if lang == "en": return pack["name_en"]
        return tr(pack["name_ja"], lang)
    def pack_memo():
        if lang == "ja": return pack["memo_ja"]
        if lang == "en": return pack["memo_en"]
        # memo は文章なので辞書に無ければ英語でフォールバック（未訳集計はしない）
        return TERMS.get("__memo__" + pack["slug"], {}).get(lang) or pack["memo_en"]

    name = pack_name()
    if name is None:
        return None  # パック名が未訳ならこの言語は出力不可
    groups = []
    for g in pack["groups"]:
        gname = g["ja"] if lang == "ja" else (g["en"] if lang == "en" else tr(g["ja"], lang))
        if gname is None:
            return None
        items = []
        for it in g["items"]:
            iname = it["ja"] if lang == "ja" else (it["en"] if lang == "en" else tr(it["ja"], lang))
            if iname is None:
                return None
            items.append({"check": False, "weight": it["weight"], "need": it["need"], "name": iname, "memo": ""})
        groups.append({"name": gname, "memo": "", "items": items})
    return {
        "ProductName": PRODUCT_NAME, "copyright": COPYRIGHT, "version": VERSION,
        "name": name, "memo": pack_memo(), "createdAt": time.time(), "groups": groups,
    }

def main():
    report_only = "--report" in sys.argv
    written = 0
    skipped = {}  # lang -> [slug]
    for lang in ALL_LANGS:
        for pack in gen.PACKS:
            slug = pack["slug"]
            if lang in LANGS_EXTRA and slug in JP_ONLY_SLUGS:
                continue  # 日本固有は非日本語で出さない
            dto = build_dto(pack, lang)
            if dto is None:
                skipped.setdefault(lang, []).append(slug)
                continue
            if report_only:
                continue
            d = os.path.join(HERE, lang)
            os.makedirs(d, exist_ok=True)
            with open(os.path.join(d, f"{slug}.packlin"), "w", encoding="utf-8") as f:
                json.dump(dto, f, ensure_ascii=False, indent=2)
            written += 1

    # 未訳レポート
    if missing:
        print("=== 未訳の名称（terms.py に追加が必要） ===")
        for lang in LANGS_EXTRA:
            ms = sorted(missing.get(lang, []))
            if ms:
                print(f"[{lang}] {len(ms)}語:")
                for m in ms:
                    print("   ", m)
    else:
        print("未訳なし（全語 terms.py に存在）")
    if skipped and not report_only:
        print("\n=== 未訳のため出力スキップしたパック ===")
        for lang, slugs in skipped.items():
            print(f"[{lang}] {len(slugs)}件: {', '.join(sorted(set(slugs)))}")
    if not report_only:
        print(f"\nwrote {written} files")

if __name__ == "__main__":
    main()
