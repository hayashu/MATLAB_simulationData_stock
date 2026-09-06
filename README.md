# MATLAB Simulation Data Stock

WaterTankLevelControlDemo(Simulinkの水位制御デモ)のシミュレーション結果を、
モデル・パラメータ・実行結果とひも付けてMLflowに記録・蓄積するための一式。
データはすべてローカル完結(クラウド送信なし)。

## 構成

- `.simstock` — このフォルダを管理対象プロジェクトとして識別するマーカー(`~/Documents/MATLAB/manage_simstock.py`が検出する)
- `WaterTankApp.mlapp` — **コード不要でワークフロー全体を操作できるGUI**(実験開始・シミュレーション実行・結果同期・考察記入・履歴閲覧)。詳細は下記
- `WaterTankLevelControlDemo.slx` / `WaterTankLevelControlDemo_init.m` — Simulinkモデルと初期化スクリプト
- `new_experiment_note.m` — 実験セッションを開始する(`notes/`にMarkdownノートを作成し、`session_id`をbaseワークスペースに設定)
- `WaterTankLevelControlDemo_mlflow_run.m` — 単発シミュレーション実行 → 指標計算 → MLflow同期まで一括実行
- `watertank_export_from_out.m` — Simulinkの「Root Parameter Set」(Run All)によるバッチ結果(`out`変数)から、正しいパラメータでrun manifestを再生成する薄いラッパー(実処理は`export_batch_results.m`)
- `run_parameter_sweep.m` — Root Parameter Setパネルに依存せず、`simulink.multisim.DesignStudy`+`parsim`で直接パラメータスイープを実行し、そのままエクスポートする(GUIのスイープタブが使用)
- `export_batch_results.m` — バッチ結果(`out`+パラメータ範囲)からrun manifestを書き出し、MLflowへ同期する共通処理
- `watertank_stopfcn_export.m` — モデルのStopFcnコールバック(現在有効)。シミュレーション終了ごとにローカルへ`metadata.json`を書き出す(MLflowへの自動同期はしない。理由はファイル冒頭のコメント参照)
- `watertank_postsim_export.m` — `simulink.multisim.DesignStudy`のPostSimFcn用(現状未使用)
- `test_mlflow.py` — `mlflow_sync/run_*/metadata.json`を読み取り、MLflowへパラメータ・指標・アーティファクト・時系列metricを登録する同期スクリプト(このプロジェクト単体を同期する場合用。複数プロジェクトを横断するなら`manage_simstock.py`を使う)
- `mlflow_sync/` — 各シミュレーション実行のrun manifest(`metadata.json`, `response_plot.png`, `signals.mat`など)
- `notes/` — 実験セッションごとのMarkdownノート(仮説・結果表・考察)

## 使い方

### GUIアプリ(コード不要)
```matlab
app = WaterTankApp();
```
4つのタブでワークフロー全体を操作できる:
1. **実験開始** — タイトルと仮説を入力して開始(`new_experiment_note`を裏で呼ぶ)
2. **シミュレーション実行** — 「単発」か「スイープ」を選び、Kp/Ki/Kdを入力して実行(スイープは`run_parameter_sweep`経由でRoot Parameter Setパネルを使わない)
3. **結果・考察** — MLflow同期・結果表挿入・考察記入・MLflowへの反映・MLflowを開く、をボタン操作で
4. **実験履歴** — 過去の実験ノート一覧と内容の閲覧

以下は同じ処理をコマンドで行いたい場合の方法(GUIの裏側と同じ関数を直接呼ぶ)。

### 単発実行
```matlab
run('WaterTankLevelControlDemo_mlflow_run.m')
```
シミュレーション実行→指標計算→`mlflow_sync/run_*/`への書き出し→MLflowへの同期まで自動で行う。

### パラメータスイープ(Root Parameter Set / Run All)
1. Simulinkの「Root Parameter Set」パネルでKp_Level/Ki_Level/Kd_Levelの範囲を設定し「Run All」を実行(結果は`out`変数にたまる)
2. `watertank_export_from_out.m`内の`Kp_vals`/`Ki_vals`/`Kd_vals`をパネルの設定と一致させてから実行(書き出し+MLflow同期まで自動)

### MLflowへの同期のみ
```bash
python3 test_mlflow.py
```
MLflowサーバーはローカルで起動しておくこと(例: `mlflow ui --port 5001`)。

### 実験ノート(仮説→実行→結果→考察)
科学的プロセスに沿って、シミュレーションの「なぜ」と「結果を見てどう考えたか」を記録する。

```matlab
new_experiment_note('PIDゲインスイープ検討')   % notes/*.md を作成し session_id を設定
```
1. 作成された `notes/<session_id>_*.md` を開き「目的・仮説」を書く
2. シミュレーション実行(単発 or Root Parameter Set batch)。runは自動的に`session_id`タグ付きで記録される
3. `python3 manage_simstock.py sync` でMLflowへ同期
4. `python3 manage_simstock.py summarize <session_id>` で結果表をノートに自動挿入
5. ノートを開き「考察・結論」を書く
6. `python3 manage_simstock.py sync-notes` でノート全文をMLflowの各runのNotes欄へ反映(考察を書き足すたびに何度でも再実行可)

`manage_simstock.py` は `~/Documents/MATLAB/` 直下にあり、`.simstock` マーカーを持つ全プロジェクトを横断して扱う(詳細は同ファイルのdocstring参照)。

## 依存関係

- MATLAB / Simulink / Simscape (Isothermal Liquid)
- Python: `mlflow`, `scipy`, `pyyaml`(`manage_simstock.py`のノート機能で使用)
