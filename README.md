# MATLAB Simulation Data Stock

WaterTankLevelControlDemo(Simulinkの水位制御デモ)のシミュレーション結果を、
モデル・パラメータ・実行結果とひも付けてMLflowに記録・蓄積するための一式。
データはすべてローカル完結(クラウド送信なし)。

## 構成

- `WaterTankLevelControlDemo.slx` / `WaterTankLevelControlDemo_init.m` — Simulinkモデルと初期化スクリプト
- `WaterTankLevelControlDemo_mlflow_run.m` — 単発シミュレーション実行 → 指標計算 → MLflow同期まで一括実行
- `watertank_export_from_out.m` — Simulinkの「Root Parameter Set」(Run All)によるバッチ結果(`out`変数)から、正しいパラメータでrun manifestを再生成するスクリプト
- `watertank_stopfcn_export.m` — モデルのStopFcnコールバック用(現在は未設定。単発実行の自動記録に使う場合はモデルのStopFcnにこの関数名を設定する)
- `watertank_postsim_export.m` — `simulink.multisim.DesignStudy`のPostSimFcn用(現状未使用)
- `test_mlflow.py` — `mlflow_sync/run_*/metadata.json`を読み取り、MLflowへパラメータ・指標・アーティファクト・時系列metricを登録する同期スクリプト
- `mlflow_sync/` — 各シミュレーション実行のrun manifest(`metadata.json`, `response_plot.png`, `signals.mat`など)

## 使い方

### 単発実行
```matlab
run('WaterTankLevelControlDemo_mlflow_run.m')
```
シミュレーション実行→指標計算→`mlflow_sync/run_*/`への書き出し→MLflowへの同期まで自動で行う。

### パラメータスイープ(Root Parameter Set / Run All)
1. Simulinkの「Root Parameter Set」パネルでKp_Level/Ki_Level/Kd_Levelの範囲を設定し「Run All」を実行(結果は`out`変数にたまる)
2. `watertank_export_from_out.m`内の`Kp_vals`/`Ki_vals`/`Kd_vals`をパネルの設定と一致させてから実行
3. 下記コマンドでMLflowに同期

### MLflowへの同期のみ
```bash
python3 test_mlflow.py
```
MLflowサーバーはローカルで起動しておくこと(例: `mlflow ui --port 5001`)。

## 依存関係

- MATLAB / Simulink / Simscape (Isothermal Liquid)
- Python: `mlflow`, `scipy`
