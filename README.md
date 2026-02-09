# xxSanSwtich

VRChat OSC を受信して、AvatarMover 用の入力OSC（`/input/*`）を返す簡易ブリッジです。

このFlutter版は **C#版互換** として、`/input/*` には基本的に **`int 0/1`** を送ります。

## 使い方

1. VRChat 側で OSC を有効化（`Settings > OSC`）
   - `OSC Input`（外部からの入力制御）が無効だと、`/input/*` は受け付けません
2. このアプリを起動して `Start`
   - `Listen Port`: `9001`（VRChat が送信してくる先）
   - `VRChat Host`: `127.0.0.1`
   - `VRChat Port`: `9000`（VRChat の受信ポート）

## 起動（例: Windows）

```bash
flutter run -d windows
```

## 動かないときの確認

- 画面の `RX count` が増える（受信できている）か
- `TX count` が増える（`/input/*` を送れている）か
- Log に `RX unmapped AM address` が出ていないか（アバターパラメータ名が想定と違う）
- VRChat の `OSC Input` が有効か、`VRChat Port` が VRChat 側の `In Port` と一致しているか

## 対応している Avatar パラメータ（受信）

- `/avatar/parameters/sai.AMForward` → `/input/MoveForward`
- `/avatar/parameters/sai.AMBack` → `/input/MoveBackward`
- `/avatar/parameters/sai.AMRight` → `/input/MoveRight`
- `/avatar/parameters/sai.AMLeft` → `/input/MoveLeft`
- `/avatar/parameters/sai.AMJump` → `/input/Jump`（1秒だけ押下）
- `/avatar/parameters/sai.AMLookRight` → `/input/LookRight`
- `/avatar/parameters/sai.AMLookLeft` → `/input/LookLeft`
- `/avatar/parameters/sai.AMMic` → `/input/Voice`（1秒だけ押下）
