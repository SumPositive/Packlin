#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
公開パック用のサンプル .packlin を ja / en で書き出す。
- 形式は同梱サンプル（PackList/Resources/*.lproj/Pack_*.packlin）に準拠：
    ProductName / copyright / version / name / memo / createdAt /
    groups[]{ name, memo, items[]{ check, weight, need, name, memo } }
- weight は g（0=未設定扱い）。need は必要数。
- 出力先: fastlane/sample_packs/<lang>/<slug>.packlin
使い方:
    cd /Users/sumpositive/GitLocal/Packlin
    python3 fastlane/sample_packs/generate_sample_packs.py
内容を直したいときはこのファイルの PACKS を編集して再実行する。
"""

import json, os, time

PRODUCT_NAME = "Packlin"
COPYRIGHT = "2025_sumpo@azukid.com"
VERSION = "3.0"
OUT_DIR = os.path.dirname(os.path.abspath(__file__))

# item = (name_ja, name_en, weight_g, need)
# group = (name_ja, name_en, [item, ...])
# pack  = slug, name_ja, name_en, memo_ja, memo_en, [group, ...]

def G(ja, en, items):
    return {"ja": ja, "en": en, "items": items}

def I(ja, en, weight, need=1):
    return {"ja": ja, "en": en, "weight": weight, "need": need}

ESSENTIALS = G("💳 貴重品", "💳 Valuables", [
    I("財布・身分証", "Wallet & ID", 150),
    I("スマホ", "Smartphone", 200),
    I("鍵", "Keys", 60),
    I("現金", "Cash", 20),
])
CHARGING = G("🔌 充電まわり", "🔌 Charging", [
    I("モバイルバッテリー", "Power bank", 250),
    I("充電ケーブル", "Charging cable", 40, 2),
    I("充電器", "Wall charger", 90),
    I("イヤホン", "Earphones", 50),
])
TOILETRIES = G("🧼 洗面・衛生", "🧼 Toiletries", [
    I("歯ブラシ・歯磨き粉", "Toothbrush & paste", 60),
    I("洗顔・スキンケア", "Face wash & skincare", 200),
    I("常備薬", "Medicine", 50),
    I("マスク", "Masks", 5, 3),
    I("ハンカチ・ティッシュ", "Handkerchief & tissue", 40),
])

PACKS = [
    # ---- 国内旅行 1泊2日 ----
    dict(slug="trip_domestic_1n2d",
         name_ja="国内旅行 1泊2日", name_en="Domestic Trip (2 days)",
         memo_ja="週末のお出かけに。着替え・洗面・充電の定番セット。",
         memo_en="For a weekend getaway. Clothes, toiletries, and charging basics.",
         groups=[
             ESSENTIALS, CHARGING, TOILETRIES,
             G("👕 着替え", "👕 Clothes", [
                 I("下着", "Underwear", 60, 2),
                 I("靴下", "Socks", 40, 2),
                 I("Tシャツ", "T-shirt", 150, 1),
                 I("パジャマ", "Pajamas", 300),
             ]),
         ]),
    # ---- 国内旅行 2泊3日 ----
    dict(slug="trip_domestic_2n3d",
         name_ja="国内旅行 2泊3日", name_en="Domestic Trip (3 days)",
         memo_ja="少し長めの旅行に。着替え多めで安心。",
         memo_en="For a slightly longer trip. Extra changes of clothes.",
         groups=[
             ESSENTIALS, CHARGING, TOILETRIES,
             G("👕 着替え", "👕 Clothes", [
                 I("下着", "Underwear", 60, 3),
                 I("靴下", "Socks", 40, 3),
                 I("Tシャツ", "T-shirt", 150, 2),
                 I("羽織りもの", "Light jacket", 400),
                 I("パジャマ", "Pajamas", 300),
             ]),
             G("👜 あると便利", "👜 Nice to have", [
                 I("エコバッグ", "Reusable bag", 60),
                 I("折りたたみ傘", "Folding umbrella", 250),
                 I("常備薬", "Medicine", 50),
             ]),
         ]),
    # ---- 海外旅行 ----
    dict(slug="trip_overseas",
         name_ja="海外旅行", name_en="Overseas Trip",
         memo_ja="パスポート・変換プラグなど海外ならではの必需品。",
         memo_en="Passport, adapters, and other overseas essentials.",
         groups=[
             G("🛂 渡航書類", "🛂 Travel documents", [
                 I("パスポート", "Passport", 40),
                 I("航空券・予約控え", "Tickets & bookings", 20),
                 I("海外旅行保険証", "Travel insurance", 20),
                 I("クレジットカード", "Credit card", 20, 2),
                 I("現地通貨", "Local cash", 30),
             ]),
             G("🔌 電源・通信", "🔌 Power & connectivity", [
                 I("変換プラグ", "Plug adapter", 80),
                 I("モバイルバッテリー", "Power bank", 250),
                 I("SIM・WiFiルーター", "SIM / WiFi router", 120),
                 I("充電ケーブル", "Charging cable", 40, 2),
             ]),
             TOILETRIES,
             G("👕 衣類", "👕 Clothes", [
                 I("下着", "Underwear", 60, 4),
                 I("靴下", "Socks", 40, 4),
                 I("トップス", "Tops", 200, 3),
                 I("上着", "Jacket", 500),
             ]),
         ]),
    # ---- 日帰り登山 ----
    dict(slug="hike_day",
         name_ja="日帰り登山", name_en="Day Hike",
         memo_ja="水2L・行動食・雨具は必携。低山〜日帰り向け。",
         memo_en="Carry 2L water, snacks, and rain gear. For day hikes.",
         groups=[
             G("💳 必須品", "💳 Essentials", [
                 I("財布・身分証", "Wallet & ID", 150),
                 I("地図", "Map", 30),
                 I("コンパス", "Compass", 40),
                 I("ヘッドランプ", "Headlamp", 90),
             ]),
             G("🥾 登山装備", "🥾 Hiking gear", [
                 I("デイパック", "Daypack", 800),
                 I("トレッキングポール", "Trekking poles", 500, 2),
                 I("雨具(上下)", "Rain gear (top & bottom)", 600),
                 I("防寒着", "Insulation layer", 400),
             ]),
             G("💧 食料・水", "💧 Food & water", [
                 I("水", "Water", 1000, 2),
                 I("行動食", "Trail snacks", 300),
                 I("非常食", "Emergency food", 200),
             ]),
         ]),
    # ---- テント泊登山 ----
    dict(slug="hike_tent",
         name_ja="テント泊登山", name_en="Overnight Backpacking",
         memo_ja="テント・寝袋・炊事道具込み。重量管理が重要。",
         memo_en="Tent, sleeping bag, and cooking gear. Weight matters.",
         groups=[
             G("⛺ 宿泊装備", "⛺ Shelter & sleep", [
                 I("テント", "Tent", 1600),
                 I("寝袋", "Sleeping bag", 900),
                 I("スリーピングマット", "Sleeping mat", 400),
             ]),
             G("🍳 炊事", "🍳 Cooking", [
                 I("バーナー", "Stove", 300),
                 I("ガス缶", "Gas canister", 220),
                 I("クッカー", "Cookware", 250),
                 I("食器・カトラリー", "Dishes & cutlery", 150),
             ]),
             G("🥾 登山装備", "🥾 Hiking gear", [
                 I("バックパック", "Backpack", 1800),
                 I("トレッキングポール", "Trekking poles", 500, 2),
                 I("雨具(上下)", "Rain gear (top & bottom)", 600),
                 I("ヘッドランプ", "Headlamp", 90),
             ]),
             G("💧 食料・水", "💧 Food & water", [
                 I("水", "Water", 1000, 2),
                 I("行動食", "Trail snacks", 300),
                 I("食料(1泊分)", "Food (1 night)", 800),
             ]),
         ]),
    # ---- ファミリーキャンプ ----
    dict(slug="camp_family",
         name_ja="ファミリーキャンプ", name_en="Family Camping",
         memo_ja="テント・調理・焚き火まわり一式。オートキャンプ向け。",
         memo_en="Tent, cooking, and campfire gear for car camping.",
         groups=[
             G("⛺ 設営", "⛺ Setup", [
                 I("テント", "Tent", 8000),
                 I("タープ", "Tarp", 3000),
                 I("ペグ・ハンマー", "Pegs & hammer", 1200),
                 I("グランドシート", "Ground sheet", 900),
             ]),
             G("🛏 快眠", "🛏 Sleep", [
                 I("寝袋", "Sleeping bag", 1500, 4),
                 I("マット", "Sleeping pad", 800, 4),
                 I("ランタン", "Lantern", 600, 2),
             ]),
             G("🍳 調理", "🍳 Cooking", [
                 I("ツーバーナー", "Two-burner stove", 4500),
                 I("クーラーボックス", "Cooler box", 3500),
                 I("調理器具一式", "Cookware set", 2000),
                 I("食器類", "Tableware", 1200),
             ]),
             G("🔥 焚き火", "🔥 Campfire", [
                 I("焚き火台", "Fire pit", 2500),
                 I("薪・着火剤", "Firewood & starter", 5000),
                 I("軍手・トング", "Gloves & tongs", 300),
             ]),
         ]),
    # ---- 出張(ビジネス) ----
    dict(slug="business_trip",
         name_ja="出張（ビジネス）", name_en="Business Trip",
         memo_ja="PC・名刺・充電まわり。1泊想定のミニマル構成。",
         memo_en="Laptop, business cards, chargers. Minimal for one night.",
         groups=[
             G("💼 仕事道具", "💼 Work items", [
                 I("ノートPC", "Laptop", 1300),
                 I("充電器(PC)", "Laptop charger", 300),
                 I("名刺", "Business cards", 30),
                 I("資料・ノート", "Documents & notebook", 300),
             ]),
             ESSENTIALS, CHARGING,
             G("👔 身だしなみ", "👔 Grooming", [
                 I("ワイシャツ", "Dress shirt", 200),
                 I("下着・靴下", "Underwear & socks", 100, 1),
                 I("洗面用具", "Toiletries", 200),
                 I("整髪料", "Hair product", 100),
             ]),
         ]),
    # ---- 帰省 ----
    dict(slug="homecoming",
         name_ja="帰省", name_en="Visiting Family",
         memo_ja="手土産・長距離移動の暇つぶしも忘れずに。",
         memo_en="Gifts and something for the long trip home.",
         groups=[
             ESSENTIALS, CHARGING,
             G("🎁 手土産・荷物", "🎁 Gifts & extras", [
                 I("手土産", "Gift", 500),
                 I("エコバッグ", "Reusable bag", 60),
                 I("お薬手帳", "Medication record", 30),
             ]),
             G("👕 着替え", "👕 Clothes", [
                 I("下着", "Underwear", 60, 2),
                 I("部屋着", "Loungewear", 300),
                 I("羽織りもの", "Light jacket", 400),
             ]),
         ]),
    # ---- 赤ちゃん連れ旅行 ----
    dict(slug="trip_with_baby",
         name_ja="赤ちゃん連れ旅行", name_en="Trip with a Baby",
         memo_ja="おむつ・ミルク・着替えは多めに。母子手帳も忘れずに。",
         memo_en="Bring extra diapers, milk, and clothes. Don't forget records.",
         groups=[
             G("🍼 授乳・ミルク", "🍼 Feeding", [
                 I("哺乳瓶", "Baby bottle", 150, 2),
                 I("粉ミルク", "Formula", 400),
                 I("授乳ケープ", "Nursing cover", 120),
                 I("スタイ", "Bib", 30, 3),
             ]),
             G("🧷 おむつまわり", "🧷 Diapering", [
                 I("紙おむつ", "Diapers", 40, 10),
                 I("おしりふき", "Baby wipes", 250),
                 I("おむつ替えシート", "Changing pad", 150),
                 I("防臭袋", "Odor-proof bags", 5, 5),
             ]),
             G("👶 着替え・ケア", "👶 Clothes & care", [
                 I("ベビー服", "Baby clothes", 100, 3),
                 I("ガーゼ", "Gauze cloth", 20, 3),
                 I("母子手帳・保険証", "Health records & card", 60),
                 I("ベビー用保湿", "Baby lotion", 120),
             ]),
         ]),
    # ---- 温泉・スパ ----
    dict(slug="onsen_spa",
         name_ja="温泉・スパ", name_en="Onsen & Spa",
         memo_ja="日帰り温泉に。タオルや基礎化粧品を忘れずに。",
         memo_en="For a day at the hot spring. Towels and skincare.",
         groups=[
             ESSENTIALS,
             G("🧴 バス用品", "🧴 Bath items", [
                 I("フェイスタオル", "Face towel", 80, 2),
                 I("バスタオル", "Bath towel", 300),
                 I("基礎化粧品", "Skincare set", 200),
                 I("ヘアゴム・ブラシ", "Hair tie & brush", 60),
             ]),
             G("👕 着替え", "👕 Clothes", [
                 I("下着", "Underwear", 60),
                 I("着替え一式", "Change of clothes", 400),
             ]),
         ]),
    # ---- フェス・野外イベント ----
    dict(slug="festival",
         name_ja="フェス・野外イベント", name_en="Festival / Outdoor Event",
         memo_ja="日焼け・雨・水分対策。動きやすい装備で。",
         memo_en="Sun, rain, and hydration ready. Pack light and mobile.",
         groups=[
             ESSENTIALS, CHARGING,
             G("☀️ 暑さ・雨対策", "☀️ Sun & rain", [
                 I("レインポンチョ", "Rain poncho", 200),
                 I("帽子", "Hat", 120),
                 I("日焼け止め", "Sunscreen", 100),
                 I("タオル", "Towel", 100, 2),
             ]),
             G("🎒 快適グッズ", "🎒 Comfort", [
                 I("レジャーシート", "Ground sheet", 300),
                 I("折りたたみ椅子", "Folding chair", 900),
                 I("飲み物", "Drinks", 500, 2),
                 I("ウェットティッシュ", "Wet wipes", 150),
             ]),
         ]),
    # ---- 防災リュック ----
    dict(slug="emergency_kit",
         name_ja="防災リュック", name_en="Emergency Kit",
         memo_ja="非常持ち出し用。定期的に中身と期限を見直しましょう。",
         memo_en="Grab-and-go kit. Review contents and expiry dates regularly.",
         groups=[
             G("💧 水・食料", "💧 Water & food", [
                 I("保存水(500ml)", "Bottled water (500ml)", 500, 4),
                 I("非常食", "Emergency food", 200, 3),
                 I("携帯トイレ", "Portable toilet", 100, 3),
             ]),
             G("🔦 明かり・情報", "🔦 Light & info", [
                 I("懐中電灯", "Flashlight", 200),
                 I("携帯ラジオ", "Portable radio", 250),
                 I("モバイルバッテリー", "Power bank", 250),
                 I("乾電池", "Batteries", 25, 4),
             ]),
             G("🩹 衛生・救急", "🩹 Hygiene & first aid", [
                 I("救急セット", "First-aid kit", 300),
                 I("マスク", "Masks", 5, 5),
                 I("ウェットティッシュ", "Wet wipes", 150),
                 I("常備薬", "Medicine", 50),
             ]),
             G("🧤 防寒・その他", "🧤 Warmth & misc", [
                 I("アルミブランケット", "Emergency blanket", 60),
                 I("軍手", "Work gloves", 50),
                 I("現金(小銭含む)", "Cash (incl. coins)", 50),
                 I("身分証コピー", "Copy of ID", 10),
             ]),
         ]),
]


def build_dto(pack, lang):
    def name(obj):
        return obj["ja"] if lang == "ja" else obj["en"]
    groups = []
    for g in pack["groups"]:
        items = [{
            "check": False,
            "weight": it["weight"],
            "need": it["need"],
            "name": name(it),
            "memo": "",
        } for it in g["items"]]
        groups.append({"name": name(g), "memo": "", "items": items})
    return {
        "ProductName": PRODUCT_NAME,
        "copyright": COPYRIGHT,
        "version": VERSION,
        "name": pack["name_ja"] if lang == "ja" else pack["name_en"],
        "memo": pack["memo_ja"] if lang == "ja" else pack["memo_en"],
        "createdAt": time.time(),
        "groups": groups,
    }


def main():
    written = 0
    for lang in ("ja", "en"):
        d = os.path.join(OUT_DIR, lang)
        os.makedirs(d, exist_ok=True)
        for pack in PACKS:
            dto = build_dto(pack, lang)
            path = os.path.join(d, f"{pack['slug']}.packlin")
            with open(path, "w", encoding="utf-8") as f:
                json.dump(dto, f, ensure_ascii=False, indent=2)
            written += 1
    print(f"wrote {written} files ({len(PACKS)} packs x 2 langs) into {OUT_DIR}/ja , /en")


if __name__ == "__main__":
    main()
