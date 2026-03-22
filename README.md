# swe-opd

This repository contains a minimal SWE-bench rollout stack built around:

- model serving via SGLang
- agent rollout via mini-swe-agent-plus
- a remote rollout service between server A and server B

At the current stage, this repository focuses on four concrete tasks:

1. Deploy and test SGLang on server A
2. Run mini-swe-agent-plus rollout on server B against server A's SGLang
3. Deploy and test the rollout service on server B
4. Call the rollout service from server A and fetch trajectory results

## Layout

- `plan/`: goals and planning documents
- `config/bootstrap/`: example env files
- `scripts/model_serving/`: server A 上的 SGLang 启动与测试
- `scripts/model_serving/start_remote_tunnel.sh`: server A 把本地模型端口反向暴露到 server B
- `scripts/model_serving/status_remote_tunnel.sh`: server A 查看模型 reverse tunnel 状态
- `scripts/model_serving/stop_remote_tunnel.sh`: server A 停止模型 reverse tunnel
- `scripts/agent_runtime/`: server B 上的 rollout、service 启停与测试
- `scripts/remote_client/`: server A 上调用 server B rollout service 的入口
- `scripts/shared/`: shared shell helpers
- `src/swe_opd/distributed_rollout.py`: small Python CLI helpers used by the shell scripts
- `src/swe_opd/rollout_service.py`: rollout HTTP service and client

## Server A: SGLang

1. Copy `config/bootstrap/model_serving.example.env` to `config/bootstrap/model_serving.local.env`
2. Fill in your model path and serving settings
3. Start:

```bash
bash scripts/model_serving/start_sglang.sh
```

4. Or start in background:

```bash
bash scripts/model_serving/start_sglang_nohup.sh
```

5. Test:

```bash
bash scripts/model_serving/test_sglang.sh
```

6. If server B needs to access server A's model through `ssh -R`, start the reverse tunnel:

```bash
bash scripts/model_serving/start_remote_tunnel.sh
bash scripts/model_serving/status_remote_tunnel.sh
```

## Server B: Direct Rollout Against A

1. Copy `config/bootstrap/agent_rollout.example.env` to `config/bootstrap/agent_rollout.local.env`
2. Fill in your `mini-swe-agent-plus` path and remote SGLang endpoint
3. Test remote model access:

```bash
bash scripts/agent_runtime/test_remote_model.sh
```

4. Run a single SWE-bench instance:

```bash
bash scripts/agent_runtime/run_single.sh sympy__sympy-15599
```

5. Run a small batch:

```bash
bash scripts/agent_runtime/run_batch.sh --slice 0:3 --workers 2
```

## Server B: Rollout Service

1. Copy `config/bootstrap/rollout_service.example.env` to `config/bootstrap/rollout_service.local.env`
2. Fill in the bind address, port, and optional API token
3. Start in foreground:

```bash
bash scripts/agent_runtime/start_service.sh
```

4. Or start in background:

```bash
bash scripts/agent_runtime/start_service_nohup.sh
bash scripts/agent_runtime/status_service.sh
```

5. Stop:

```bash
bash scripts/agent_runtime/stop_service.sh
```

## Server A: Call Server B Rollout Service

1. Copy `config/bootstrap/remote_rollout_client.example.env` to `config/bootstrap/remote_rollout_client.local.env`
2. Fill in the SSH host/user/key for server B
3. Run a single rollout:

```bash
bash scripts/remote_client/run_rollout.sh single sympy__sympy-15599
```

4. Run a batch rollout:

```bash
bash scripts/remote_client/run_rollout.sh batch --slice 0:3 --workers 2
```

5. Reset the common A↔B connections and start over:

```bash
bash scripts/remote_client/reset_connections.sh
```

## Notes

- The rollout wrappers always pass `--model` explicitly to
  `swebench_pool_way.py`, because the local `mini-swe-agent-plus` version in
  this workspace assumes `model` is not `None`.
- The helper scripts do not assume that model serving and agent rollout use the
  same Python environment. Serving-side scripts use `SGLANG_PYTHON_BIN`;
  rollout-side scripts use `MINI_PYTHON_BIN` and optionally `BOOTSTRAP_PYTHON_BIN`.
- The generated config is written under `generated/bootstrap/`.
- Runtime artifacts are written under `outputs/`.
