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

    # ========================= スポーツ =========================
    dict(slug="gym_workout",
         name_ja="ジム・筋トレ", name_en="Gym Workout",
         memo_ja="ウェア・シューズ・タオルの定番。プロテインも忘れずに。",
         memo_en="Wear, shoes, and towel basics. Don't forget protein.",
         groups=[
             G("👟 トレーニング", "👟 Training", [
                 I("トレーニングウェア", "Workout clothes", 300),
                 I("シューズ", "Training shoes", 700),
                 I("グローブ", "Lifting gloves", 80),
                 I("タオル", "Towel", 150, 2),
             ]),
             G("🥤 補給・ケア", "🥤 Fuel & care", [
                 I("プロテイン", "Protein", 300),
                 I("シェイカー", "Shaker bottle", 120),
                 I("水", "Water", 500),
                 I("シャンプー・ボディソープ", "Shampoo & body wash", 200),
             ]),
             ESSENTIALS,
         ]),
    dict(slug="running",
         name_ja="ランニング", name_en="Running",
         memo_ja="ランニング一式。夜間は反射材・ライトも。",
         memo_en="Running essentials. Reflectors and a light for night runs.",
         groups=[
             G("🏃 装備", "🏃 Gear", [
                 I("ランニングシューズ", "Running shoes", 500),
                 I("ウェア(上下)", "Running outfit", 300),
                 I("ランニングソックス", "Running socks", 40),
                 I("キャップ", "Cap", 80),
             ]),
             G("📱 サポート", "📱 Support", [
                 I("ランニングウォッチ", "Running watch", 50),
                 I("イヤホン", "Earphones", 50),
                 I("ジェル・補給食", "Energy gel", 40, 2),
                 I("反射材・ライト", "Reflector & light", 60),
             ]),
         ]),
    dict(slug="golf",
         name_ja="ゴルフ", name_en="Golf",
         memo_ja="ラウンド一式。日焼け・雨対策も忘れずに。",
         memo_en="A full round setup. Sun and rain protection too.",
         groups=[
             G("⛳ プレー用品", "⛳ Play items", [
                 I("ゴルフグローブ", "Golf glove", 40, 2),
                 I("ボール", "Golf balls", 45, 6),
                 I("ティー", "Tees", 3, 10),
                 I("マーカー", "Ball marker", 10),
             ]),
             G("👕 ウェア", "👕 Apparel", [
                 I("ゴルフウェア", "Golf wear", 400),
                 I("ゴルフシューズ", "Golf shoes", 900),
                 I("帽子・サンバイザー", "Cap / visor", 100),
                 I("着替え", "Change of clothes", 400),
             ]),
             G("☀️ 対策・その他", "☀️ Protection & misc", [
                 I("日焼け止め", "Sunscreen", 100),
                 I("レインウェア", "Rain gear", 400),
                 I("タオル", "Towel", 150, 2),
                 I("飲み物", "Drinks", 500),
             ]),
         ]),
    dict(slug="tennis",
         name_ja="テニス", name_en="Tennis",
         memo_ja="ラケット・シューズ・ボール。汗対策も。",
         memo_en="Racket, shoes, balls. Plus sweat management.",
         groups=[
             G("🎾 用具", "🎾 Equipment", [
                 I("ラケット", "Racket", 300),
                 I("テニスボール", "Tennis balls", 60, 3),
                 I("テニスシューズ", "Tennis shoes", 700),
                 I("グリップテープ", "Grip tape", 20),
             ]),
             G("👕 ウェア・ケア", "👕 Wear & care", [
                 I("テニスウェア", "Tennis wear", 300),
                 I("リストバンド", "Wristband", 30, 2),
                 I("タオル", "Towel", 150, 2),
                 I("スポーツドリンク", "Sports drink", 500),
             ]),
         ]),
    dict(slug="ski_snowboard",
         name_ja="スキー・スノボ", name_en="Ski & Snowboard",
         memo_ja="ゲレンデ装備。防寒・防水をしっかり。",
         memo_en="Slope gear. Keep it warm and waterproof.",
         groups=[
             G("🎿 ウェア", "🎿 Outerwear", [
                 I("スキーウェア(上下)", "Ski wear", 1500),
                 I("インナー(上下)", "Base layer", 400),
                 I("グローブ", "Gloves", 200),
                 I("ネックウォーマー", "Neck warmer", 80),
             ]),
             G("🥽 小物", "🥽 Accessories", [
                 I("ゴーグル", "Goggles", 200),
                 I("ニット帽", "Beanie", 100),
                 I("厚手ソックス", "Thick socks", 80, 2),
                 I("カイロ", "Hand warmers", 20, 4),
             ]),
             G("🧴 ケア・その他", "🧴 Care & misc", [
                 I("日焼け止め", "Sunscreen", 100),
                 I("リップクリーム", "Lip balm", 20),
                 I("着替え", "Change of clothes", 500),
                 I("現金・IC", "Cash / IC card", 30),
             ]),
         ]),
    dict(slug="bouldering",
         name_ja="ボルダリング", name_en="Bouldering",
         memo_ja="ジム通い装備。シューズとチョークが基本。",
         memo_en="Gym bag basics. Shoes and chalk are key.",
         groups=[
             G("🧗 クライミング", "🧗 Climbing", [
                 I("クライミングシューズ", "Climbing shoes", 500),
                 I("チョークバッグ", "Chalk bag", 120),
                 I("チョーク", "Chalk", 100),
                 I("テーピング", "Tape", 40),
             ]),
             G("👕 その他", "👕 Misc", [
                 I("動きやすい服", "Athletic clothes", 300),
                 I("タオル", "Towel", 150),
                 I("飲み物", "Drink", 500),
                 I("ブラシ", "Hold brush", 30),
             ]),
         ]),
    dict(slug="soccer_futsal",
         name_ja="サッカー・フットサル", name_en="Soccer / Futsal",
         memo_ja="練習・試合の定番。すね当ても忘れずに。",
         memo_en="Practice and match basics. Don't forget shin guards.",
         groups=[
             G("⚽ 装備", "⚽ Gear", [
                 I("スパイク・シューズ", "Cleats / shoes", 700),
                 I("すね当て", "Shin guards", 150),
                 I("ユニフォーム", "Uniform", 300),
                 I("ソックス", "Socks", 60, 2),
             ]),
             G("🥤 サポート", "🥤 Support", [
                 I("着替え", "Change of clothes", 400),
                 I("タオル", "Towel", 150, 2),
                 I("スポーツドリンク", "Sports drink", 500),
                 I("ボール", "Ball", 420),
             ]),
         ]),
    dict(slug="yoga",
         name_ja="ヨガ", name_en="Yoga",
         memo_ja="スタジオ通いに。マットとタオルが基本。",
         memo_en="For the studio. Mat and towel are the basics.",
         groups=[
             G("🧘 ヨガ用品", "🧘 Yoga items", [
                 I("ヨガマット", "Yoga mat", 1000),
                 I("ヨガウェア", "Yoga wear", 250),
                 I("フェイスタオル", "Face towel", 80),
                 I("ヨガブロック", "Yoga block", 200),
             ]),
             G("🥤 その他", "🥤 Misc", [
                 I("水", "Water", 500),
                 I("着替え", "Change of clothes", 300),
                 I("汗拭きシート", "Body wipes", 100),
             ]),
         ]),

    # ==================== 趣味・アウトドア ====================
    dict(slug="fishing",
         name_ja="釣り", name_en="Fishing",
         memo_ja="堤防・海釣りの定番。ライフジャケットは必ず。",
         memo_en="Pier and sea fishing basics. Always wear a life vest.",
         groups=[
             G("🎣 タックル", "🎣 Tackle", [
                 I("竿・リール", "Rod & reel", 500),
                 I("仕掛け・ルアー", "Rigs & lures", 200),
                 I("クーラーボックス", "Cooler box", 2000),
                 I("バケツ・網", "Bucket & net", 600),
             ]),
             G("🦺 安全・快適", "🦺 Safety & comfort", [
                 I("ライフジャケット", "Life vest", 700),
                 I("帽子・偏光サングラス", "Cap & sunglasses", 150),
                 I("日焼け止め", "Sunscreen", 100),
                 I("タオル・手拭き", "Towel & wipes", 150),
             ]),
             G("🍙 飲食・その他", "🍙 Food & misc", [
                 I("飲み物", "Drinks", 500, 2),
                 I("軽food", "Snacks", 200),
                 I("ゴミ袋", "Trash bags", 20, 3),
                 I("レインウェア", "Rain gear", 400),
             ]),
         ]),
    dict(slug="camp_solo",
         name_ja="ソロキャンプ", name_en="Solo Camping",
         memo_ja="軽量ソロ装備。焚き火とコーヒーで一人時間を。",
         memo_en="Lightweight solo gear. Fire and coffee for me-time.",
         groups=[
             G("⛺ 宿泊", "⛺ Shelter & sleep", [
                 I("ソロテント", "Solo tent", 2000),
                 I("寝袋", "Sleeping bag", 900),
                 I("マット", "Sleeping mat", 400),
                 I("チェア", "Camp chair", 800),
             ]),
             G("🔥 焚き火・調理", "🔥 Fire & cooking", [
                 I("焚き火台", "Fire pit", 1000),
                 I("シングルバーナー", "Single burner", 250),
                 I("クッカー", "Cookware", 250),
                 I("コーヒーセット", "Coffee set", 300),
             ]),
             G("🔦 その他", "🔦 Misc", [
                 I("ランタン", "Lantern", 300),
                 I("ヘッドランプ", "Headlamp", 90),
                 I("ナイフ", "Knife", 120),
                 I("ゴミ袋", "Trash bags", 20, 3),
             ]),
         ]),
    dict(slug="cycling",
         name_ja="サイクリング", name_en="Cycling",
         memo_ja="ロングライドの装備。パンク修理と補給を忘れずに。",
         memo_en="Long-ride kit. Puncture repair and fuel are key.",
         groups=[
             G("🚴 装備", "🚴 Gear", [
                 I("ヘルメット", "Helmet", 300),
                 I("グローブ", "Cycling gloves", 60),
                 I("サングラス", "Sunglasses", 40),
                 I("ボトル", "Water bottle", 600, 2),
             ]),
             G("🔧 メンテ・補給", "🔧 Repair & fuel", [
                 I("予備チューブ", "Spare tube", 120, 2),
                 I("携帯ポンプ", "Mini pump", 150),
                 I("携帯工具", "Multi-tool", 120),
                 I("補給食", "Energy food", 50, 3),
             ]),
             ESSENTIALS,
         ]),
    dict(slug="bbq",
         name_ja="BBQ", name_en="BBQ",
         memo_ja="デイキャンプ・河原のBBQ。炭と着火が要。",
         memo_en="Day BBQ by the river. Charcoal and a lighter are essential.",
         groups=[
             G("🔥 コンロまわり", "🔥 Grill", [
                 I("BBQコンロ", "BBQ grill", 4000),
                 I("炭", "Charcoal", 3000),
                 I("着火剤・トング", "Lighter & tongs", 400),
                 I("軍手", "Work gloves", 50),
             ]),
             G("🍖 食器・食材", "🍖 Tableware & food", [
                 I("紙皿・カップ", "Paper plates & cups", 200),
                 I("クーラーボックス", "Cooler box", 3000),
                 I("調味料", "Seasonings", 300),
                 I("ウェットティッシュ", "Wet wipes", 150),
             ]),
             G("🪑 快適・その他", "🪑 Comfort & misc", [
                 I("レジャーシート", "Ground sheet", 300),
                 I("折りたたみ椅子", "Folding chair", 900, 2),
                 I("ゴミ袋", "Trash bags", 20, 5),
                 I("虫除け", "Bug spray", 100),
             ]),
         ]),
    dict(slug="stargazing",
         name_ja="天体観測", name_en="Stargazing",
         memo_ja="星空を見に。防寒と赤色ライトが快適の鍵。",
         memo_en="For the night sky. Warm layers and a red light help.",
         groups=[
             G("🔭 観測用品", "🔭 Observation", [
                 I("双眼鏡・望遠鏡", "Binoculars / telescope", 1500),
                 I("星座早見盤", "Star chart", 50),
                 I("赤色ライト", "Red light", 80),
                 I("レジャーシート", "Ground sheet", 300),
             ]),
             G("🧥 防寒・快適", "🧥 Warmth & comfort", [
                 I("防寒着", "Warm jacket", 600),
                 I("ブランケット", "Blanket", 500),
                 I("温かい飲み物", "Hot drink", 400),
                 I("折りたたみ椅子", "Folding chair", 900),
             ]),
         ]),
    dict(slug="photography",
         name_ja="写真撮影", name_en="Photography",
         memo_ja="撮影遠征に。予備バッテリーとレンズ拭きを。",
         memo_en="For a photo trip. Spare batteries and lens cloth.",
         groups=[
             G("📷 機材", "📷 Equipment", [
                 I("カメラ本体", "Camera body", 700),
                 I("レンズ", "Lens", 500, 2),
                 I("三脚", "Tripod", 1200),
                 I("予備バッテリー", "Spare battery", 60, 2),
             ]),
             G("💾 サポート", "💾 Support", [
                 I("SDカード", "SD card", 5, 2),
                 I("レンズ拭き", "Lens cloth", 20),
                 I("ブロワー", "Air blower", 80),
                 I("モバイルバッテリー", "Power bank", 250),
             ]),
         ]),

    # =============== 趣味・インドア / 推し活 ===============
    dict(slug="live_concert",
         name_ja="ライブ・コンサート", name_en="Live Concert",
         memo_ja="参戦準備。チケットとペンライトは必須。",
         memo_en="Show-day prep. Ticket and glow stick are must-haves.",
         groups=[
             G("🎫 必需品", "🎫 Essentials", [
                 I("チケット", "Ticket", 10),
                 I("ペンライト", "Glow stick", 100, 2),
                 I("身分証", "ID", 20),
                 I("現金・交通IC", "Cash / IC card", 30),
             ]),
             G("🎒 快適グッズ", "🎒 Comfort", [
                 I("うちわ・応援グッズ", "Fan goods", 100),
                 I("モバイルバッテリー", "Power bank", 250),
                 I("タオル", "Towel", 150),
                 I("飲み物", "Drink", 500),
             ]),
         ]),
    dict(slug="fan_tour",
         name_ja="推し活・遠征", name_en="Fan Tour",
         memo_ja="遠征1泊。グッズ用の空きバッグも用意。",
         memo_en="Overnight fan trip. Bring an empty bag for goods.",
         groups=[
             G("🎫 参戦セット", "🎫 Event set", [
                 I("チケット", "Ticket", 10),
                 I("応援グッズ", "Cheer goods", 200),
                 I("推しカラー衣装", "Themed outfit", 400),
                 I("うちわ", "Paper fan", 100),
             ]),
             G("🛍 遠征装備", "🛍 Travel gear", [
                 I("グッズ用エコバッグ", "Bag for goods", 80),
                 I("モバイルバッテリー", "Power bank", 250),
                 I("着替え", "Change of clothes", 400),
                 I("洗面用具", "Toiletries", 200),
             ]),
             ESSENTIALS,
         ]),
    dict(slug="cinema",
         name_ja="映画館", name_en="Cinema",
         memo_ja="快適に映画を。防寒とのど飴を忍ばせて。",
         memo_en="Comfy movie time. A layer and throat candy help.",
         groups=[
             G("🎬 持ち物", "🎬 Items", [
                 I("チケット・会員証", "Ticket / membership", 10),
                 I("羽織りもの", "Light layer", 300),
                 I("のど飴", "Throat candy", 30),
                 I("ハンカチ", "Handkerchief", 20),
             ]),
         ]),
    dict(slug="boardgame",
         name_ja="ボードゲーム会", name_en="Board Game Night",
         memo_ja="持ち寄り会に。ゲームとおやつを忘れずに。",
         memo_en="A bring-your-own night. Games and snacks!",
         groups=[
             G("🎲 ゲーム", "🎲 Games", [
                 I("ボードゲーム", "Board games", 800, 2),
                 I("カードゲーム", "Card games", 200, 2),
                 I("得点メモ・ペン", "Scorepad & pen", 50),
                 I("タイマー", "Timer", 40),
             ]),
             G("🍿 差し入れ", "🍿 Snacks", [
                 I("お菓子", "Snacks", 300),
                 I("飲み物", "Drinks", 500),
                 I("ウェットティッシュ", "Wet wipes", 100),
             ]),
         ]),
    dict(slug="doujin_event",
         name_ja="同人イベント", name_en="Doujin Event",
         memo_ja="即売会に。現金・クリアファイル・体力ケアを。",
         memo_en="For a fan convention. Cash, folders, and stamina care.",
         groups=[
             G("💴 会場必需品", "💴 Venue essentials", [
                 I("現金(小銭多め)", "Cash (small bills)", 100),
                 I("カタログ・地図", "Catalog / map", 200),
                 I("クリアファイル", "Clear folders", 30, 3),
                 I("紙袋・エコバッグ", "Bags", 80, 2),
             ]),
             G("🔋 体力ケア", "🔋 Stamina", [
                 I("モバイルバッテリー", "Power bank", 250),
                 I("飲み物", "Drinks", 500),
                 I("軽food・補給", "Snacks", 200),
                 I("汗拭きシート", "Body wipes", 100),
             ]),
         ]),

    # =============== 季節・ライフイベント ===============
    dict(slug="beach",
         name_ja="海水浴", name_en="Beach",
         memo_ja="海を満喫。日焼け対策と着替えをしっかり。",
         memo_en="Enjoy the sea. Sun care and a change of clothes.",
         groups=[
             G("🏖 ビーチ用品", "🏖 Beach items", [
                 I("水着", "Swimsuit", 150),
                 I("ビーチタオル", "Beach towel", 400, 2),
                 I("サンダル", "Sandals", 200),
                 I("浮き輪・レジャーシート", "Float & sheet", 600),
             ]),
             G("☀️ 対策・ケア", "☀️ Protection", [
                 I("日焼け止め", "Sunscreen", 150),
                 I("サングラス・帽子", "Sunglasses & hat", 150),
                 I("着替え", "Change of clothes", 400),
                 I("防水ケース", "Waterproof case", 50),
             ]),
             G("🥤 その他", "🥤 Misc", [
                 I("飲み物", "Drinks", 500, 2),
                 I("ゴミ袋", "Trash bags", 20, 3),
                 I("ウェットティッシュ", "Wet wipes", 150),
             ]),
         ]),
    dict(slug="hanami",
         name_ja="花見", name_en="Cherry Blossom Picnic",
         memo_ja="お花見ピクニック。敷物と防寒を忘れずに。",
         memo_en="A hanami picnic. Bring a mat and a warm layer.",
         groups=[
             G("🌸 場所取り・飲食", "🌸 Spot & food", [
                 I("レジャーシート", "Ground sheet", 400),
                 I("お弁当・おつまみ", "Food & snacks", 800),
                 I("飲み物", "Drinks", 1000, 2),
                 I("紙皿・紙コップ", "Paper plates & cups", 150),
             ]),
             G("🧥 快適・その他", "🧥 Comfort & misc", [
                 I("防寒着・ブランケット", "Warm layer & blanket", 600),
                 I("ウェットティッシュ", "Wet wipes", 100),
                 I("ゴミ袋", "Trash bags", 20, 3),
                 I("モバイルバッテリー", "Power bank", 250),
             ]),
         ]),
    dict(slug="fireworks",
         name_ja="花火大会", name_en="Fireworks Festival",
         memo_ja="夏の夜に。浴衣・うちわ・虫除けを。",
         memo_en="A summer night out. Yukata, fan, and bug spray.",
         groups=[
             G("🎆 持ち物", "🎆 Items", [
                 I("レジャーシート", "Ground sheet", 300),
                 I("うちわ・扇子", "Paper fan", 60),
                 I("虫除けスプレー", "Bug spray", 100),
                 I("懐中電灯", "Flashlight", 150),
             ]),
             G("🥤 飲食・ケア", "🥤 Food & care", [
                 I("飲み物", "Drinks", 500, 2),
                 I("軽food", "Snacks", 200),
                 I("タオル・汗拭き", "Towel & wipes", 150),
                 I("ゴミ袋", "Trash bags", 20, 2),
             ]),
         ]),
    dict(slug="hospital_stay",
         name_ja="入院", name_en="Hospital Stay",
         memo_ja="入院準備。着替え・洗面・退屈しのぎを用意。",
         memo_en="Admission prep. Clothes, toiletries, and something to pass time.",
         groups=[
             G("🧾 手続き・必需品", "🧾 Admin & essentials", [
                 I("保険証・診察券", "Insurance & patient card", 30),
                 I("印鑑", "Personal seal", 20),
                 I("現金", "Cash", 30),
                 I("お薬手帳", "Medication record", 30),
             ]),
             G("🧺 身の回り", "🧺 Personal care", [
                 I("パジャマ・下着", "Pajamas & underwear", 500),
                 I("洗面用具", "Toiletries", 300),
                 I("タオル", "Towels", 200, 2),
                 I("スリッパ", "Slippers", 200),
             ]),
             G("📱 快適グッズ", "📱 Comfort", [
                 I("スマホ・充電器", "Phone & charger", 300),
                 I("イヤホン", "Earphones", 50),
                 I("本・雑誌", "Books / magazines", 300),
                 I("ティッシュ・ウェット", "Tissues & wipes", 150),
             ]),
         ]),
    dict(slug="moving",
         name_ja="引っ越し", name_en="Moving Day",
         memo_ja="引っ越し当日。すぐ使う物と工具を手元に。",
         memo_en="Moving day. Keep tools and first-night items handy.",
         groups=[
             G("🔧 作業道具", "🔧 Tools", [
                 I("カッター・はさみ", "Utility knife & scissors", 100),
                 I("ガムテープ", "Packing tape", 200, 2),
                 I("軍手", "Work gloves", 50, 2),
                 I("マジック・ラベル", "Markers & labels", 60),
             ]),
             G("📦 すぐ使う物", "📦 First-night items", [
                 I("トイレットペーパー", "Toilet paper", 200),
                 I("タオル", "Towels", 200, 2),
                 I("着替え", "Change of clothes", 400),
                 I("洗面用具", "Toiletries", 300),
             ]),
             G("🧾 手続き", "🧾 Paperwork", [
                 I("契約書類", "Contract documents", 100),
                 I("印鑑", "Personal seal", 20),
                 I("現金", "Cash", 50),
                 I("スマホ・充電器", "Phone & charger", 300),
             ]),
         ]),
    dict(slug="wedding_guest",
         name_ja="結婚式参列", name_en="Wedding Guest",
         memo_ja="お呼ばれ準備。ご祝儀袋と袱紗を忘れずに。",
         memo_en="Wedding guest prep. Don't forget the gift envelope.",
         groups=[
             G("🎁 マナー品", "🎁 Etiquette items", [
                 I("ご祝儀袋", "Gift money envelope", 30),
                 I("袱紗", "Fukusa cloth", 40),
                 I("招待状", "Invitation", 20),
                 I("新札", "New bills", 20),
             ]),
             G("👗 身だしなみ", "👗 Grooming", [
                 I("フォーマル靴", "Formal shoes", 700),
                 I("ハンカチ", "Handkerchief", 20),
                 I("予備ストッキング", "Spare stockings", 30),
                 I("メイク直し", "Makeup touch-up", 150),
             ]),
             ESSENTIALS,
         ]),
    dict(slug="exam",
         name_ja="資格試験", name_en="Exam Day",
         memo_ja="試験当日。受験票と時計、防寒調整を。",
         memo_en="Exam day. Admission ticket, a watch, and layers.",
         groups=[
             G("📝 受験必需品", "📝 Exam essentials", [
                 I("受験票", "Admission ticket", 10),
                 I("身分証", "ID", 20),
                 I("筆記用具", "Writing tools", 60),
                 I("腕時計", "Watch", 50),
             ]),
             G("🧥 コンディション", "🧥 Condition", [
                 I("羽織りもの", "Layer", 300),
                 I("飲み物", "Drink", 500),
                 I("軽food・チョコ", "Snack / chocolate", 100),
                 I("参考書・要点メモ", "Notes", 300),
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
