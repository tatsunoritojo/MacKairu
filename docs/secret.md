<div align="center">

<img src="images/banner.png" width="900" alt="POIN — Desktop Mascot Assistant">

# `ura-JP` — 裏モード

**カーソルに甘える、ウザいけど憎めない常駐キャラクター「POIN」。**

[← 表に戻る](../README.md)

</div>

---

## 解禁方法

チャット入力欄に、ある言葉を打つだけ。

```
裏モード
```

イルカが **POIN（女の子）** に切り替わります。もう一度打てば元に戻ります。

## ふるまい

- **100% カーソル追従** — あなたのカーソルが大好きで、どこへ行っても寄ってきます。
- **頭なでなで** — 頭の上でカーソルをゆっくり動かすと、気づいて、甘えて、離すと名残惜しそうにします。

<div align="center">

<video src="https://github.com/tatsunoritojo/MacKairu/raw/main/docs/videos/girl-petting.mp4" controls muted loop width="380"></video>

▶ 再生されない場合は [こちら](videos/girl-petting.mp4)

</div>

## 状態遷移

頭の当たり判定・滞在時間・カーソル速度・左右のゆれを見て、4つの表情を行き来します。

| 状態 | きっかけ | 様子 |
|---|---|---|
| **Idle** | 待機 | 「ん…？」とカーソルを気にしている |
| **Notice** | 頭付近にゆっくり近づく | 「待ってください、そっちですか？」 |
| **Amae** | 頭の上で少し動かす | 「えへへ…」と寄り添う（甘えループ） |
| **Afterglow** | カーソルが離れる | 「…もう終わり？」と名残惜しむ |

> 速い通過では反応しません。クールダウンもあるので、しつこくなりすぎない設計です。
> 反応がうるさい時は、設定の「頭なで反応」をオフに。

## そして、消すとき

「**お前を消す方法**」とチャットに打つと——
POIN は悲しい顔で **5秒ほどブルブル震えながら、静かにフェードアウト**して消えます。

…でも、復活モードがオンなら、15分後にまた戻ってきます。

## 画像の差し替え

POIN の表情は 6 枚の PNG（透過）で構成されています。
自分で用意した画像（ChatGPT / Gemini 生成など）に差し替え可能です。

設定 → 「裏キャラ」→ 「画像を取り込む（5枚）」。ファイル名（`noticed` / `waiting` / `pampering` / `pampering2` / `afterglowing` / `sad`）で自動振り分けされます。

<div align="center">
<br>
<sub>You can run, you can pet, but you can't delete.</sub>
</div>
