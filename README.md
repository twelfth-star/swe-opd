# swe-opd

This repository contains the glue code for the SWE-bench agent rollout stack we
want to build around:

- model serving via SGLang
- agent rollout via mini-swe-agent-plus
- later integration into Slime for training / OPD

At the current stage, this repository only implements the bootstrap stack:

- no training
- no teacher
- no OPD
- no reward pipeline
- just bring up SGLang serving + mini-swe-agent-plus rollout end to end

## Layout

- `plan/`: goals and planning documents
- `config/bootstrap/`: example env files for model serving and agent rollout
- `scripts/model_serving/`: serving-side launch and validation scripts
- `scripts/agent_rollout/`: rollout-side config rendering, smoke tests, and SWE-bench scripts
- `src/swe_opd/distributed_rollout.py`: small Python CLI helpers used by the shell scripts

## Bootstrap Quick Start

### Model Serving

1. Copy `config/bootstrap/model_serving.example.env` to `config/bootstrap/model_serving.env`
2. Fill in your model path and serving settings
3. Run:

```bash
bash scripts/model_serving/start_sglang.sh
```

You can switch between two serving modes with `SGLANG_LAUNCH_MODE`:

- `single`: one SGLang server process, optionally using `SGLANG_TP` for tensor parallel
- `router`: co-launch SGLang router + workers, using `SGLANG_TP` and `SGLANG_DP_SIZE`

When using `router`, `/v1/models` may briefly return `No models available` during startup before workers finish registering.

4. In another shell, validate:

```bash
bash scripts/model_serving/check_http.sh
bash scripts/model_serving/check_openai_chat.sh
```

### Agent Rollout

1. Copy `config/bootstrap/agent_rollout.example.env` to `config/bootstrap/agent_rollout.env`
2. Fill in your `mini-swe-agent-plus` path and remote SGLang endpoint
3. Run smoke tests:

```bash
bash scripts/agent_rollout/openai_smoke.sh
bash scripts/agent_rollout/litellm_smoke.sh
```

4. Render the mini-swe-agent-plus config:

```bash
bash scripts/agent_rollout/render_remote_config.sh
```

5. Run a single SWE-bench instance:

```bash
bash scripts/agent_rollout/run_swebench_single.sh sympy__sympy-15599
```

6. Run a small batch:

```bash
bash scripts/agent_rollout/run_swebench_batch.sh --slice 0:3 --workers 2
```

## Notes

- The rollout-side wrappers always pass `--model` explicitly to
  `swebench_pool_way.py`, because the local `mini-swe-agent-plus` version in
  this workspace assumes `model` is not `None`.
- The helper scripts do not assume that model serving and agent rollout use the
  same Python environment. Serving-side scripts use `SGLANG_PYTHON_BIN`;
  rollout-side scripts use `MINI_PYTHON_BIN` and optionally `BOOTSTRAP_PYTHON_BIN`.
- The generated config is written under `generated/bootstrap/`.
- Runtime artifacts are written under `outputs/`.
