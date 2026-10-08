# ime-watch

ibus-mozc で入力モードを切り替えたとき、文字を打っている位置のすぐ横に「あ」「A」を一瞬表示します。同時に現在のモードをファイルへ書き出すので、Claude Code の statusline などから読めます。

GNOME のトップバーの表示は、Mozc のキーマップで割り当てた IMEOn/IMEOff に追従しません。しかも画面の右上にあるので、見落として全角のまま `/` を打ってしまいがちです。ime-watch はこれを防ぐために作りました。

## 動作環境

- ibus と ibus-mozc
- Xorg セッション（Ubuntu 24.04 の GNOME で確認しています）
- Python 3 と PyGObject（`gir1.2-ibus-1.0`、`gir1.2-gtk-3.0`）

Wayland では、ポップアップを入力位置に動かせません。状態ファイルの書き出しは動くはずですが、試していません。

## インストール

```sh
git clone git@github.com:kazuhironx/ime-watch.git ~/dev/github.com/kazuhironx/ime-watch
~/dev/github.com/kazuhironx/ime-watch/install.sh
```

`install.sh` は、`~/.local/bin/ime-watch` と `~/.config/systemd/user/ime-watch.service` にリンクを張り、サービスを有効にします。サービスは `graphical-session.target` に合わせて起動します。外すときは `install.sh --uninstall` を実行します。

## 状態ファイル

`~/.cache/ime-state`（`$XDG_CACHE_HOME` があればその下）に、Mozc が表示しているモードの記号を1行で書きます。

| 値 | モード |
|----|--------|
| `A` | 直接入力（英数） |
| `あ` | ひらがな |
| `ア` / `_ｱ` | 全角カタカナ / 半角カタカナ |
| `Ａ` / `_A` | 全角英数 / 半角英数 |

モードが変わったときだけ、一時ファイルからの rename で置き換えます。読む側が書きかけの内容を見ることはありません。

Claude Code の statusline に出す例は [examples/statusline-segment.sh](examples/statusline-segment.sh) にあります。statusline は Claude Code のイベントごとにしか描き直されないので、`statusLine` の `refreshInterval` を `2` 程度にしておきます。

## 仕組み

ibus-daemon のバスに `eavesdrop=true` の match rule を登録し、次の2つを横から読んでいます。

- エンジンが出す `UpdateProperty` シグナルのうち `InputMode`。ラベル `Input Mode (あ)` の括弧の中を、モードとして使います。
- クライアントが送る `SetCursorLocation`。入力位置の座標です。

ibus-daemon は `org.freedesktop.DBus.Monitoring` を実装していないので、盗聴（eavesdrop）でしか読めません。盗聴した他人宛のメソッド呼び出しはフィルタで捨てます。捨てないと GDBus が `UnknownMethod` エラーを返してしまうからです。

`ibus restart` でバスとの接続が切れると、ime-watch は終了します。再接続は systemd の `Restart=always` に任せています。

## ライセンス

MIT
