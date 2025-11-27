# azuki-api修正用プロンプト

以下の内容をサーバー側のazuki-apiに適用できるよう、LLMや開発メンバーへ伝える指示として利用してください。クライアントはiOSアプリの最新実装に合わせており、特に広告特典（AdMob SSV）との連携とアクセストークン配布まわりの仕様を前提とします。

## 目的
- AdMobリワード広告のSSVで `customData` として受け取る `userAdId` をサーバー側で解釈し、購入実績があれば `userId` と関連付ける。
- `/api/credit/check` で広告特典フラグと新規アクセストークン配布に対応する。
- AI生成API `/api/openai` では取得済みアクセストークンを前提に認可処理を行う。

## 要求仕様
1. `userAdId` 取り扱い
    - AdMobのSSV webhookで受信した `customData` を `userAdId` として扱う。
    - すでに課金購入済みの `userId` が存在する場合、同一ユーザーの端末からの広告視聴かどうかを判定し、問題なければ `userAdId` を `userId` にひも付けて永続化する（例: RDBのユーザーテーブルに `user_ad_id` カラムを追加）。
    - `/api/credit/check` のクエリに `userAdId` が含まれていれば、認証済みの `userId` を逆引きできるようにする。

2. `/api/credit/check` の入力と出力
    - 入力: `userId` は必須。`userAdId` は任意だが、あれば記録・紐付け対象とする。
    - 出力: 以下のフィールドをJSONで返す。
        - `balance`: 現在の有料クレジット残高（整数）。
        - `adRewardAvailable`: AdMob視聴による広告特典が利用可能かどうかの真偽値。未判定の場合は `false` を返す。
        - `accessToken`, `accessTokenExpiresAt`, `refreshToken`, `refreshTokenExpiresAt`: ユーザーが未購入でアクセストークンをまだ配布していない場合、新規発行して返す。すでに発行済みなら空欄でよい。
    - 認証: アクセストークン無しでも呼び出せる。ただし、内部では `userId` と `userAdId` の整合性チェックやBAN判定など、必要な検証を挟む。

3. 広告特典付与ロジック
    - AdMob SSVの検証に成功したらサーバー側で広告特典を「1回分付与済み」の状態に更新する。複数回付与したい場合は回数をカウントするフィールドを用意する。
    - `/api/credit/check` では広告特典が残っていれば `adRewardAvailable` を `true` にし、クライアントが消費したタイミングで `false` へ更新できるように状態遷移を設計する。

4. アクセストークン配布と更新
    - `/api/credit/check` から返却するアクセストークン類は、azuki-api内で生成するJWTやAPIキーなど既存の方式に合わせる。期限（expなど）は `accessTokenExpiresAt` / `refreshTokenExpiresAt` にUNIX秒で入れる。
    - クライアントは `adRewardAvailable == true` のとき優先的に広告特典を使い、それが無いときは有料クレジットを減算する。サーバー側でも同じ優先順位となるように実装する。

5. `/api/openai` 側での認可
    - ヘッダーのアクセストークン検証に加え、ユーザーの広告特典や残高が不足していればHTTP 402など適切なエラーを返す。
    - 広告特典が残っていればそちらを優先的に消費し、無い場合のみ有料クレジットを減算する。

## 実装ヒント
- SSVの署名検証や重複リプレイ防止（nonce再利用チェック等）は必須。
- `userAdId` は端末ローカル生成の識別子想定なので、乗っ取り防止のため `userId` が紐づくまでの間は用途を限定し、異なる `userId` に同一 `userAdId` が送られてきた場合は警告ログを残す。
- `adRewardAvailable` をカウンタで管理する場合、減算は `/api/openai` での推論実行成功時に確定させる。ロールバック要件があるならトランザクション管理を検討する。

以上を踏まえ、既存のazuki-apiコードベースに対して差分を生成するよう促してください。
