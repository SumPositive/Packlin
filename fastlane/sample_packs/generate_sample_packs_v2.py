#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
公開パック用サンプル .packlin を 8 言語で書き出す（多言語版・検証用）。
対応言語: ja, en, de, es, fr, it, ko, zh-Hant

設計:
- I(names, weight, need): names は {lang: 名称} の辞書。対象言語ぶんの訳を持つ。
- G(names, items): names は {lang: グループ名}。
- パックは langs=[...] で対象言語を限定できる（省略=全言語）。日本固有ジャンルは langs=["ja"] 等。
- 慣習調整（レベル2）: パック内で lang 別に数量・重量・一部アイテムを差し替えたい場合は
  override 辞書を使う（本ファイルは検証用に代表3ジャンルのみ。OKなら全ジャンルへ展開）。

使い方:
    cd /Users/sumpositive/GitLocal/Packlin
    python3 fastlane/sample_packs/generate_sample_packs_v2.py
出力先: fastlane/sample_packs/<lang>/<slug>.packlin
"""

import json, os, time

PRODUCT_NAME = "Packlin"
COPYRIGHT = "2025_sumpo@azukid.com"
VERSION = "3.0"
OUT_DIR = os.path.dirname(os.path.abspath(__file__))

# App Store ロケール名に合わせる（zh-Hant は繁体字）。フォルダ名もこれに一致。
LANGS = ["ja", "en", "de", "es", "fr", "it", "ko", "zh-Hant"]


def I(names, weight, need=1):
    return {"names": names, "weight": weight, "need": need}


def G(names, items):
    return {"names": names, "items": items}


# ---- 共通グループ（全言語）----
# 名称は各言語のネイティブ表記。絵文字は共通。
ESSENTIALS = G(
    {"ja": "💳 貴重品", "en": "💳 Valuables", "de": "💳 Wertsachen", "es": "💳 Objetos de valor",
     "fr": "💳 Objets de valeur", "it": "💳 Oggetti di valore", "ko": "💳 귀중품", "zh-Hant": "💳 貴重物品"},
    [
        I({"ja": "財布・身分証", "en": "Wallet & ID", "de": "Geldbörse & Ausweis", "es": "Cartera y DNI",
           "fr": "Portefeuille et pièce d'identité", "it": "Portafoglio e documento", "ko": "지갑·신분증", "zh-Hant": "錢包・證件"}, 150),
        I({"ja": "スマホ", "en": "Smartphone", "de": "Smartphone", "es": "Móvil",
           "fr": "Smartphone", "it": "Smartphone", "ko": "스마트폰", "zh-Hant": "手機"}, 200),
        I({"ja": "鍵", "en": "Keys", "de": "Schlüssel", "es": "Llaves",
           "fr": "Clés", "it": "Chiavi", "ko": "열쇠", "zh-Hant": "鑰匙"}, 60),
        I({"ja": "現金", "en": "Cash", "de": "Bargeld", "es": "Efectivo",
           "fr": "Espèces", "it": "Contanti", "ko": "현금", "zh-Hant": "現金"}, 20),
    ],
)

CHARGING = G(
    {"ja": "🔌 充電まわり", "en": "🔌 Charging", "de": "🔌 Laden", "es": "🔌 Carga",
     "fr": "🔌 Recharge", "it": "🔌 Ricarica", "ko": "🔌 충전", "zh-Hant": "🔌 充電"},
    [
        I({"ja": "モバイルバッテリー", "en": "Power bank", "de": "Powerbank", "es": "Batería externa",
           "fr": "Batterie externe", "it": "Power bank", "ko": "보조배터리", "zh-Hant": "行動電源"}, 250),
        I({"ja": "充電ケーブル", "en": "Charging cable", "de": "Ladekabel", "es": "Cable de carga",
           "fr": "Câble de charge", "it": "Cavo di ricarica", "ko": "충전 케이블", "zh-Hant": "充電線"}, 40, 2),
        I({"ja": "充電器", "en": "Wall charger", "de": "Ladegerät", "es": "Cargador",
           "fr": "Chargeur secteur", "it": "Caricatore", "ko": "충전기", "zh-Hant": "充電器"}, 90),
        I({"ja": "イヤホン", "en": "Earphones", "de": "Kopfhörer", "es": "Auriculares",
           "fr": "Écouteurs", "it": "Auricolari", "ko": "이어폰", "zh-Hant": "耳機"}, 50),
    ],
)

TOILETRIES = G(
    {"ja": "🧼 洗面・衛生", "en": "🧼 Toiletries", "de": "🧼 Toilettenartikel", "es": "🧼 Aseo",
     "fr": "🧼 Trousse de toilette", "it": "🧼 Igiene", "ko": "🧼 세면·위생", "zh-Hant": "🧼 盥洗・衛生"},
    [
        I({"ja": "歯ブラシ・歯磨き粉", "en": "Toothbrush & paste", "de": "Zahnbürste & -pasta", "es": "Cepillo y pasta de dientes",
           "fr": "Brosse à dents et dentifrice", "it": "Spazzolino e dentifricio", "ko": "칫솔·치약", "zh-Hant": "牙刷・牙膏"}, 60),
        I({"ja": "洗顔・スキンケア", "en": "Face wash & skincare", "de": "Gesichtsreinigung & Pflege", "es": "Limpieza facial y cuidado",
           "fr": "Nettoyant visage et soins", "it": "Detergente viso e cura", "ko": "세안·스킨케어", "zh-Hant": "洗面・保養"}, 200),
        I({"ja": "常備薬", "en": "Medicine", "de": "Medikamente", "es": "Medicamentos",
           "fr": "Médicaments", "it": "Medicinali", "ko": "상비약", "zh-Hant": "常備藥"}, 50),
        I({"ja": "ハンカチ・ティッシュ", "en": "Handkerchief & tissue", "de": "Taschentücher", "es": "Pañuelos",
           "fr": "Mouchoirs", "it": "Fazzoletti", "ko": "손수건·휴지", "zh-Hant": "手帕・面紙"}, 40),
    ],
)


# =========================================================================
# 検証用の3ジャンル（全言語 + 慣習調整の実演）
# =========================================================================
PACKS = [
    # ---- 国内旅行 1泊2日（各国とも「近場1泊」の定番。共通ベースで十分）----
    dict(
        slug="trip_domestic_1n2d",
        names={"ja": "国内旅行 1泊2日", "en": "Overnight Trip", "de": "Kurztrip (1 Nacht)",
               "es": "Escapada de una noche", "fr": "Escapade d'une nuit", "it": "Gita di una notte",
               "ko": "1박 2일 여행", "zh-Hant": "國內旅行 兩天一夜"},
        memos={"ja": "週末のお出かけに。着替え・洗面・充電の定番セット。",
               "en": "For a weekend getaway. Clothes, toiletries, and charging basics.",
               "de": "Für einen Wochenendausflug. Kleidung, Toilettenartikel und Ladegeräte.",
               "es": "Para una escapada de fin de semana. Ropa, aseo y carga.",
               "fr": "Pour un week-end. Vêtements, toilette et recharge.",
               "it": "Per una gita nel weekend. Vestiti, igiene e ricarica.",
               "ko": "주말 나들이에. 옷·세면·충전 기본 세트.",
               "zh-Hant": "適合週末出遊。換洗、盥洗、充電的基本組合。"},
        groups=[
            ESSENTIALS, CHARGING, TOILETRIES,
            G({"ja": "👕 着替え", "en": "👕 Clothes", "de": "👕 Kleidung", "es": "👕 Ropa",
               "fr": "👕 Vêtements", "it": "👕 Vestiti", "ko": "👕 옷", "zh-Hant": "👕 換洗衣物"},
              [
                  I({"ja": "下着", "en": "Underwear", "de": "Unterwäsche", "es": "Ropa interior",
                     "fr": "Sous-vêtements", "it": "Biancheria intima", "ko": "속옷", "zh-Hant": "內衣褲"}, 60, 2),
                  I({"ja": "靴下", "en": "Socks", "de": "Socken", "es": "Calcetines",
                     "fr": "Chaussettes", "it": "Calzini", "ko": "양말", "zh-Hant": "襪子"}, 40, 2),
                  I({"ja": "Tシャツ", "en": "T-shirt", "de": "T-Shirt", "es": "Camiseta",
                     "fr": "T-shirt", "it": "Maglietta", "ko": "티셔츠", "zh-Hant": "T恤"}, 150),
                  I({"ja": "パジャマ", "en": "Pajamas", "de": "Schlafanzug", "es": "Pijama",
                     "fr": "Pyjama", "it": "Pigiama", "ko": "잠옷", "zh-Hant": "睡衣"}, 300),
              ]),
        ],
    ),

    # ---- 日帰り登山（水量は各国の常識に合わせて微調整の余地。ベースは共通）----
    dict(
        slug="hike_day",
        names={"ja": "日帰り登山", "en": "Day Hike", "de": "Tageswanderung",
               "es": "Excursión de un día", "fr": "Randonnée à la journée", "it": "Escursione giornaliera",
               "ko": "당일 등산", "zh-Hant": "一日登山"},
        memos={"ja": "水・行動食・雨具は必携。低山〜日帰り向け。",
               "en": "Carry water, snacks, and rain gear. For day hikes.",
               "de": "Wasser, Snacks und Regenkleidung mitnehmen. Für Tagestouren.",
               "es": "Lleva agua, comida y chubasquero. Para excursiones de un día.",
               "fr": "Emportez eau, en-cas et veste de pluie. Pour la journée.",
               "it": "Porta acqua, snack e giacca antipioggia. Per la giornata.",
               "ko": "물·행동식·우비 필수. 당일 산행용.",
               "zh-Hant": "水、行動糧、雨具必備。適合一日登山。"},
        groups=[
            G({"ja": "💳 必須品", "en": "💳 Essentials", "de": "💳 Grundausstattung", "es": "💳 Imprescindibles",
               "fr": "💳 Indispensables", "it": "💳 Essenziali", "ko": "💳 필수품", "zh-Hant": "💳 必需品"},
              [
                  I({"ja": "財布・身分証", "en": "Wallet & ID", "de": "Geldbörse & Ausweis", "es": "Cartera y DNI",
                     "fr": "Portefeuille et pièce d'identité", "it": "Portafoglio e documento", "ko": "지갑·신분증", "zh-Hant": "錢包・證件"}, 150),
                  I({"ja": "地図", "en": "Map", "de": "Karte", "es": "Mapa",
                     "fr": "Carte", "it": "Cartina", "ko": "지도", "zh-Hant": "地圖"}, 30),
                  I({"ja": "ヘッドランプ", "en": "Headlamp", "de": "Stirnlampe", "es": "Linterna frontal",
                     "fr": "Lampe frontale", "it": "Lampada frontale", "ko": "헤드램프", "zh-Hant": "頭燈"}, 90),
              ]),
            G({"ja": "🥾 登山装備", "en": "🥾 Hiking gear", "de": "🥾 Wanderausrüstung", "es": "🥾 Equipo de senderismo",
               "fr": "🥾 Matériel de rando", "it": "🥾 Attrezzatura", "ko": "🥾 등산 장비", "zh-Hant": "🥾 登山裝備"},
              [
                  I({"ja": "デイパック", "en": "Daypack", "de": "Tagesrucksack", "es": "Mochila de día",
                     "fr": "Sac à dos", "it": "Zaino", "ko": "데이백", "zh-Hant": "登山背包"}, 800),
                  I({"ja": "雨具(上下)", "en": "Rain gear (top & bottom)", "de": "Regenkleidung", "es": "Chubasquero",
                     "fr": "Veste et pantalon de pluie", "it": "Giacca e pantaloni antipioggia", "ko": "우비(상하)", "zh-Hant": "雨衣(上下)"}, 600),
                  I({"ja": "防寒着", "en": "Insulation layer", "de": "Wärmeschicht", "es": "Capa de abrigo",
                     "fr": "Couche chaude", "it": "Strato termico", "ko": "방한복", "zh-Hant": "保暖衣物"}, 400),
              ]),
            G({"ja": "💧 食料・水", "en": "💧 Food & water", "de": "💧 Essen & Wasser", "es": "💧 Comida y agua",
               "fr": "💧 Nourriture et eau", "it": "💧 Cibo e acqua", "ko": "💧 식량·물", "zh-Hant": "💧 飲食・水"},
              [
                  I({"ja": "水", "en": "Water", "de": "Wasser", "es": "Agua",
                     "fr": "Eau", "it": "Acqua", "ko": "물", "zh-Hant": "水"}, 1000, 2),
                  I({"ja": "行動食", "en": "Trail snacks", "de": "Wandersnacks", "es": "Snacks",
                     "fr": "En-cas", "it": "Snack", "ko": "행동식", "zh-Hant": "行動糧"}, 300),
              ]),
        ],
    ),

    # ---- 温泉・スパ（★慣習調整の実演。国ごとに名称・想定が変わる）----
    # 日本=温泉、独=Therme/Sauna、韓=찜질방、他=SPA。names で文化的に自然な語を選ぶ。
    dict(
        slug="onsen_spa",
        names={"ja": "温泉", "en": "Hot Spring & Spa", "de": "Therme & Sauna",
               "es": "Balneario y spa", "fr": "Thermes et spa", "it": "Terme e spa",
               "ko": "온천·찜질방", "zh-Hant": "溫泉・SPA"},
        memos={"ja": "日帰り温泉に。タオルや基礎化粧品を忘れずに。",
               "en": "For a day at the spa. Towels and skincare.",
               "de": "Für einen Tag in der Therme. Handtücher und Pflege.",
               "es": "Para un día de balneario. Toallas y cuidado de la piel.",
               "fr": "Pour une journée aux thermes. Serviettes et soins.",
               "it": "Per una giornata alle terme. Asciugamani e cura della pelle.",
               "ko": "온천·찜질방 나들이에. 수건과 기초화장품을 챙기세요.",
               "zh-Hant": "適合泡湯一日遊。別忘了毛巾與保養品。"},
        groups=[
            ESSENTIALS,
            G({"ja": "🧴 バス用品", "en": "🧴 Bath items", "de": "🧴 Badeutensilien", "es": "🧴 Artículos de baño",
               "fr": "🧴 Articles de bain", "it": "🧴 Articoli da bagno", "ko": "🧴 목욕용품", "zh-Hant": "🧴 沐浴用品"},
              [
                  I({"ja": "フェイスタオル", "en": "Face towel", "de": "Handtuch", "es": "Toalla de cara",
                     "fr": "Serviette", "it": "Asciugamano", "ko": "페이스 타월", "zh-Hant": "毛巾"}, 80, 2),
                  I({"ja": "バスタオル", "en": "Bath towel", "de": "Badetuch", "es": "Toalla de baño",
                     "fr": "Serviette de bain", "it": "Telo da bagno", "ko": "목욕 수건", "zh-Hant": "浴巾"}, 300),
                  I({"ja": "基礎化粧品", "en": "Skincare set", "de": "Hautpflege", "es": "Cuidado de la piel",
                     "fr": "Soins de la peau", "it": "Prodotti per la pelle", "ko": "기초화장품", "zh-Hant": "保養品"}, 200),
                  # 慣習調整の例: 独・仏・伊・西のサウナ/温浴文化ではバスローブ/サンダルが定番
                  I({"ja": "ヘアゴム・ブラシ", "en": "Hair tie & brush", "de": "Bademantel", "es": "Albornoz",
                     "fr": "Peignoir", "it": "Accappatoio", "ko": "샤워 타월", "zh-Hant": "髮圈・梳子"}, 60),
              ]),
            G({"ja": "👕 着替え", "en": "👕 Clothes", "de": "👕 Kleidung", "es": "👕 Ropa",
               "fr": "👕 Vêtements", "it": "👕 Vestiti", "ko": "👕 옷", "zh-Hant": "👕 換洗衣物"},
              [
                  I({"ja": "下着", "en": "Underwear", "de": "Unterwäsche", "es": "Ropa interior",
                     "fr": "Sous-vêtements", "it": "Biancheria intima", "ko": "속옷", "zh-Hant": "內衣褲"}, 60),
                  I({"ja": "着替え一式", "en": "Change of clothes", "de": "Wechselkleidung", "es": "Muda de ropa",
                     "fr": "Rechange", "it": "Cambio d'abiti", "ko": "갈아입을 옷", "zh-Hant": "換洗衣物一套"}, 400),
              ]),
        ],
    ),
]


def build_dto(pack, lang):
    def nm(names):
        # 対象言語の訳が無ければ en にフォールバック（検証時の取りこぼし防止）
        return names.get(lang) or names.get("en") or next(iter(names.values()))
    groups = []
    for g in pack["groups"]:
        items = [{
            "check": False,
            "weight": it["weight"],
            "need": it["need"],
            "name": nm(it["names"]),
            "memo": "",
        } for it in g["items"]]
        groups.append({"name": nm(g["names"]), "memo": "", "items": items})
    return {
        "ProductName": PRODUCT_NAME,
        "copyright": COPYRIGHT,
        "version": VERSION,
        "name": nm(pack["names"]),
        "memo": nm(pack["memos"]),
        "createdAt": time.time(),
        "groups": groups,
    }


def main():
    written = 0
    for lang in LANGS:
        d = os.path.join(OUT_DIR, lang)
        os.makedirs(d, exist_ok=True)
        for pack in PACKS:
            target = pack.get("langs")  # None なら全言語
            if target is not None and lang not in target:
                continue
            dto = build_dto(pack, lang)
            with open(os.path.join(d, f"{pack['slug']}.packlin"), "w", encoding="utf-8") as f:
                json.dump(dto, f, ensure_ascii=False, indent=2)
            written += 1
    print(f"wrote {written} files across {len(LANGS)} langs (検証用 {len(PACKS)} ジャンル)")


if __name__ == "__main__":
    main()
