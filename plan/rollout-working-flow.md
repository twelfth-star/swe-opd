# Rollout 可工作流程

更新时间：2026-03-21

本文档只记录已经验证可工作的流程，不记录排障过程。

## 目标

在不接训练、不接 teacher、不接 OPD 的前提下，跑通下面这条链路：

1. 服务器 A 启动 SGLang，提供 OpenAI-compatible 接口
2. 服务器 A 主动 SSH 到服务器 B，建立 reverse tunnel
3. 服务器 B 通过本地 tunnel 调用服务器 A 上的模型
4. 服务器 B 使用 `mini-swe-agent-plus` 在 Docker 中跑 SWE-bench rollout

## 当前可工作的拓扑

- 服务器 A：GPU 机器，运行 SGLang
- 服务器 B：支持 Docker，运行 `mini-swe-agent-plus`
- Server B 实际访问的模型地址是本地 tunnel，例如：
  - `http://127.0.0.1:32000/v1`

## 服务器 A：模型服务

### 1. 配置

在 [model_serving.example.env](/u/zhe3/re-swe/swe-opd/config/bootstrap/model_serving.example.env) 基础上准备本地配置，例如：

```env
SGLANG_PYTHON_BIN=/projects/bdse/zhe3/uv_env/sglang/bin/python
SGLANG_MODEL_PATH=Kwai-Klear/Klear-AgentForge-8B
SGLANG_HOST=0.0.0.0
SGLANG_PORT=30000
SGLANG_LAUNCH_MODE=router
SGLANG_TP=1
SGLANG_DP_SIZE=2
SGLANG_MEM_FRACTION_STATIC=0.80
SGLANG_EXTRA_ARGS=--trust-remote-code
SGLANG_API_KEY=EMPTY
SGLANG_MODEL_NAME=Kwai-Klear/Klear-AgentForge-8B
SGLANG_SMOKE_PROMPT=Reply with exactly: bootstrap-ok
```

如果只用单卡，可以把：

```env
SGLANG_LAUNCH_MODE=single
SGLANG_TP=1
SGLANG_DP_SIZE=1
```

## 2. 启动

```bash
cd /u/zhe3/re-swe/swe-opd
bash scripts/model_serving/start_sglang.sh
```

## 3. 验证

```bash
curl -s http://127.0.0.1:30000/v1/models
curl -s http://127.0.0.1:30000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer EMPTY' \
  -d '{
    "model": "Kwai-Klear/Klear-AgentForge-8B",
    "messages": [{"role": "user", "content": "Reply with exactly: bootstrap-ok"}],
    "temperature": 0.0,
    "max_tokens": 32
  }'
```

## 4. 建立 reverse tunnel

从真正运行 SGLang 的服务器 A 节点执行：

```bash
ssh -i /u/zhe3/.ssh/taurus_ssh_key \
  -o StrictHostKeyChecking=accept-new \
  -o ExitOnForwardFailure=yes \
  -o ServerAliveInterval=30 \
  -o ServerAliveCountMax=3 \
  -N \
  -R 127.0.0.1:32000:127.0.0.1:30000 \
  zhongmouhe@taurus.cs.ucsb.edu
```

## 服务器 B：agent rollout

### 1. 运行时要求

服务器 B 上需要：

- `swe-opd` 仓库
- `mini-swe-agent-plus` 仓库
- 可用的 Python 环境
- 可用的 Docker

如果需要使用 `add_edit_tool`，运行时必须确保导入的是 `mini-swe-agent-plus` 仓库里的 `src/minisweagent`，而不是旧的 site-packages 包。可工作方式是：

```bash
export PYTHONPATH=/path/to/mini-swe-agent-plus/src:$PYTHONPATH
```

### 2. 配置

在 [agent_rollout.example.env](/u/zhe3/re-swe/swe-opd/config/bootstrap/agent_rollout.example.env) 基础上准备本地配置，例如：

```env
BOOTSTRAP_PYTHON_BIN=/mnt/data2/zhongmouhe/conda_envs/sweagent/bin/python
MINI_PYTHON_BIN=/mnt/data2/zhongmouhe/conda_envs/sweagent/bin/python
MINI_SWE_AGENT_PLUS_ROOT=/home/zhongmouhe/swe-re/mini-swe-agent-plus

REMOTE_API_BASE=http://127.0.0.1:32000
REMOTE_API_KEY=EMPTY
REMOTE_MODEL_NAME=Kwai-Klear/Klear-AgentForge-8B
REMOTE_PROVIDER=openai
REMOTE_TEMPERATURE=0.0
REMOTE_DROP_PARAMS=true
REMOTE_SMOKE_PROMPT=Reply with exactly: bootstrap-ok

MSWEA_COST_TRACKING=ignore_errors

SWEBENCH_SUBSET=verified
SWEBENCH_SPLIT=test
SWEBENCH_WORKERS=2
SWEBENCH_DOCKER_START_CONCURRENCY=1
```

### 3. 标准 SWE-bench 配置

如果只需要标准 SWE-bench rollout：

```env
MINI_BASE_CONFIG=/home/zhongmouhe/swe-re/mini-swe-agent-plus/src/minisweagent/config/extra/swebench.yaml
```

### 4. 带 add_edit_tool 的配置

如果需要启用 `add_edit_tool`，使用 `swe-opd` 里的兼容版配置：

```env
MINI_BASE_CONFIG=/home/zhongmouhe/swe-re/swe-opd/config/mini_swe_agent_plus/swebench_add_edit_tool_compat.yaml
```

这份兼容版配置已经过端到端验证，agent 可以成功使用 `edit_via_str_replace`。

### 5. smoke test

```bash
cd /home/zhongmouhe/swe-re/swe-opd
bash scripts/agent_rollout/doctor.sh
```

## 单实例 rollout

### 标准配置

```bash
cd /home/zhongmouhe/swe-re/swe-opd
bash scripts/agent_rollout/run_swebench_single.sh sympy__sympy-15599
```

### add_edit_tool 配置

```bash
cd /home/zhongmouhe/swe-re/swe-opd
PYTHONPATH=/home/zhongmouhe/swe-re/mini-swe-agent-plus/src:$PYTHONPATH \
MINI_BASE_CONFIG=/home/zhongmouhe/swe-re/swe-opd/config/mini_swe_agent_plus/swebench_add_edit_tool_compat.yaml \
bash scripts/agent_rollout/run_swebench_single.sh sympy__sympy-15599
```

## 小 batch rollout

### 标准配置

```bash
cd /home/zhongmouhe/swe-re/swe-opd
bash scripts/agent_rollout/run_swebench_batch.sh --slice 0:3 --workers 2
```

### add_edit_tool 配置

```bash
cd /home/zhongmouhe/swe-re/swe-opd
PYTHONPATH=/home/zhongmouhe/swe-re/mini-swe-agent-plus/src:$PYTHONPATH \
MINI_BASE_CONFIG=/home/zhongmouhe/swe-re/swe-opd/config/mini_swe_agent_plus/swebench_add_edit_tool_compat.yaml \
bash scripts/agent_rollout/run_swebench_batch.sh --slice 0:3 --workers 2
```

## 成功标准

当前流程已经验证过以下结果：

- 服务器 A 上 SGLang `single` 模式可用
- 服务器 A 上 SGLang `router` 多 GPU 模式可用
- reverse tunnel 可用
- 服务器 B 上单实例 SWE-bench rollout 可用
- 服务器 B 上小 batch SWE-bench rollout 可用
- `add_edit_tool` 兼容配置可用，agent 可以成功调用 `edit_via_str_replace`

## 远程 rollout service

为下一阶段接入 `slime`，当前仓库已补充一套最小 HTTP rollout service：

- 服务端入口：
  - `bash scripts/agent_rollout/start_rollout_service.sh`
- 客户端入口：
  - `bash scripts/agent_rollout/remote_rollout.sh submit ...`
  - `bash scripts/agent_rollout/remote_rollout.sh wait ...`
  - `bash scripts/agent_rollout/remote_rollout.sh result ...`

服务会在服务器 B 上：

1. 接收单实例或 batch rollout 请求
2. 为每个 job 生成独立的 rendered config
3. 为每个 job 生成独立的 artifacts 目录
4. 调用现有 `run_swebench_single.sh` 或 `run_swebench_batch.sh`
5. 返回 job 状态、stdout/stderr tail 和结果文件路径
