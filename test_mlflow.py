import os
import glob
import json

os.environ.setdefault("MLFLOW_DISABLE_AGENT_HINT", "1")

import mlflow
import numpy as np
from scipy.io import loadmat

# 設定
TRACKING_URI = "http://127.0.0.1:5001"  # 起動中のMLflowポート
SYNC_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "mlflow_sync")  # ローカル完結（クラウド同期対象外）

def log_timeseries_metrics(folder):
    """signals.matの時系列を、共通の0.1秒刻みグリッドにリサンプルしてから
    step付きmetricとして記録する。MLflowのCompare Runs画面で複数run分の
    波形を重ねて比較できるようにするため。

    リサンプルする理由: 元の可変ステップ solver の時刻をそのまま
    round(t*10) で step 化すると、同じ step に複数サンプルが collision
    したり(重複)、信号ごとにサンプル数が変わったりする。MLflowの
    Chart画面でX軸にmetric(SimTime_s)を指定する機能は、おそらく
    「何番目の点か」で対応付けているため、LevelMeas/LevelRef/SimTime_sの
    点数が1点でもズレると後半の対応がズレてジグザグな波形になる
    (実際に発生した不具合)。共通グリッドへの線形補間でこれを解消し、
    SimTime_s・LevelMeas・LevelRefの点数と順序を完全に一致させる。"""
    mat_path = os.path.join(folder, "signals.mat")
    if not os.path.exists(mat_path):
        return

    try:
        data = loadmat(mat_path)
    except Exception as e:
        print(f"  ⚠️ signals.mat 読み込み失敗: {e}")
        return

    series_map = {
        "LevelMeas": ("tMeas", "yMeas"),
        "LevelRef": ("tRef", "yRef"),
    }

    dt = 0.1
    t_max = 0.0
    for t_key, _ in series_map.values():
        if t_key in data:
            t_max = max(t_max, float(data[t_key].flatten()[-1]))
    if t_max <= 0:
        return
    n_steps = int(round(t_max / dt)) + 1
    grid_t = np.arange(n_steps) * dt

    for metric_name, (t_key, y_key) in series_map.items():
        if t_key not in data or y_key not in data:
            continue
        t = data[t_key].flatten()
        y = data[y_key].flatten()
        y_grid = np.interp(grid_t, t, y)
        for step, yi in enumerate(y_grid):
            mlflow.log_metric(metric_name, float(yi), step=step)
        print(f"  📈 時系列metric追加: {metric_name} ({n_steps} 点、0.1秒刻みにリサンプル)")

    for step, ti in enumerate(grid_t):
        mlflow.log_metric("SimTime_s", float(ti), step=step)
    print(f"  🕒 SimTime_s も記録 ({n_steps} 点) — Chart画面のX軸に指定可能")


def sync_runs():
    print(f"MLflow Tracking URI: {TRACKING_URI}")
    mlflow.set_tracking_uri(TRACKING_URI)
    
    if not os.path.exists(SYNC_DIR):
        print(f"エラー: 同期ディレクトリが見つかりません: {SYNC_DIR}")
        return

    # 各 run_ フォルダを走査
    run_folders = sorted(glob.glob(os.path.join(SYNC_DIR, "run_*")))
    if not run_folders:
        print("同期対象の run_* フォルダが見つかりませんでした。")
        return

    print(f"検出されたフォルダ数: {len(run_folders)}")

    for folder in run_folders:
        folder_name = os.path.basename(folder)
        meta_file = os.path.join(folder, "metadata.json")
        synced_marker = os.path.join(folder, ".mlflow_synced")

        # 既にMLflowに登録済みのフォルダはスキップ
        if os.path.exists(synced_marker):
            print(f"⏩ スキップ (登録済み): {folder_name}")
            continue

        print(f"🚀 MLflowに登録中: {folder_name} ...")

        try:
            metadata = {}
            if os.path.exists(meta_file):
                with open(meta_file, "r", encoding="utf-8") as f:
                    metadata = json.load(f)

            exp_name = metadata.get("experiment_name", "My_Simulink_Experiment")
            run_name = metadata.get("run_name", folder_name)

            # 実験の設定
            mlflow.set_experiment(exp_name)

            # Runの開始
            with mlflow.start_run(run_name=run_name) as active_run:
                # Sourceをtest_mlflow.py（同期スクリプト）ではなく、実際にシミュレーションした
                # Simulinkモデルに書き換える（Model名は 1.のparamsループより前に読む必要がある）
                params = metadata.get("params", {})
                model_name = params.get("Model")
                if model_name:
                    mlflow.set_tag("mlflow.source.name", f"{model_name}.slx")
                    mlflow.set_tag("mlflow.source.type", "LOCAL")

                # 1. パラメータの記録
                for k, v in params.items():
                    mlflow.log_param(k, v)

                # 2. メトリクスの記録
                metrics = metadata.get("metrics", {})
                for k, v in metrics.items():
                    mlflow.log_metric(k, v)

                # 3. タグの記録
                tags = metadata.get("tags", {})
                for k, v in tags.items():
                    mlflow.set_tag(k, v)

                # 4. 説明・メモの記録
                description = metadata.get("description")
                if description:
                    mlflow.set_tag("mlflow.note.content", description)

                # 5. 成果物 (Artifacts) の登録（.mat, .mldatx, .png等）
                for item in os.listdir(folder):
                    if item.startswith(".") or item == "metadata.json":
                        continue
                    item_path = os.path.join(folder, item)
                    if os.path.isfile(item_path):
                        mlflow.log_artifact(item_path)
                        print(f"  📎 Artifact追加: {item}")

                # 6. 時系列データをstep付きmetricとして記録（run間の波形比較用）
                log_timeseries_metrics(folder)

            # 登録完了マーカーを作成（次回以降の二重登録防止）
            with open(synced_marker, "w") as f:
                f.write("synced")

            print(f"✅ 登録完了: {folder_name}")

        except Exception as e:
            print(f"❌ エラー発生 ({folder_name}): {e}")

    print("\nすべての同期処理が完了しました！ブラウザ (http://127.0.0.1:5001) を確認してください。")

if __name__ == "__main__":
    sync_runs()
