# Rollout Bootstrap 实践记录

更新时间：2026-03-21

## 1. 结论

阶段目标已经达成：

- 服务器 A 上成功启动 SGLang，并对外提供 OpenAI-compatible 接口
- 服务器 B 上成功通过 mini-swe-agent-plus 在 Docker 中跑通单实例 SWE-bench rollout
- 服务器 B 上成功跑通小规模 batch rollout（`--slice 0:3 --workers 2`）
- 服务器 A 上成功切换到多 GPU 的 router 模式，并在不改 rollout 流程的前提下继续跑通服务器 B 的调用

当前结论只覆盖 rollout 链路，不包含：

- 训练
- teacher
- OPD
- reward / verifier 接入
- Slime 训练集成

## 2. 实际可用架构

实际跑通的链路不是“服务器 B 直接访问服务器 A 的公网服务”，而是：

1. 服务器 A 在计算节点上启动 SGLang
2. 服务器 A 主动 SSH 到服务器 B，建立 reverse tunnel
3. 服务器 B 通过本地 `127.0.0.1:<forwarded_port>` 调用服务器 A 上的 SGLang
4. mini-swe-agent-plus 在服务器 B 的 Docker 容器中完成 SWE-bench rollout

这是当前环境下最稳的方案，因为：

- Delta 登录需要密码和 Duo，不适合让服务器 B 反向自动登录服务器 A
- 服务器 A 到服务器 B 的主动 SSH 更容易做长期连接

## 3. 关键配置

### 服务器 A

推荐直接用 Hugging Face repo id 作为 `SGLANG_MODEL_PATH`，例如：

```env
SGLANG_MODEL_PATH=Kwai-Klear/Klear-AgentForge-8B
SGLANG_HOST=0.0.0.0
SGLANG_PORT=30000
SGLANG_LAUNCH_MODE=single
SGLANG_TP=1
SGLANG_DP_SIZE=1
SGLANG_MEM_FRACTION_STATIC=0.80
SGLANG_MODEL_NAME=Kwai-Klear/Klear-AgentForge-8B
```

如果服务器 A 有多张 GPU，可以切换到 router 模式，例如：

```env
SGLANG_MODEL_PATH=Kwai-Klear/Klear-AgentForge-8B
SGLANG_HOST=0.0.0.0
SGLANG_PORT=30000
SGLANG_LAUNCH_MODE=router
SGLANG_TP=1
SGLANG_DP_SIZE=2
SGLANG_MEM_FRACTION_STATIC=0.80
SGLANG_EXTRA_ARGS=--trust-remote-code
SGLANG_MODEL_NAME=Kwai-Klear/Klear-AgentForge-8B
```

经验结论：

- `single` 模式适合单实例服务或 TP 扩展
- `router` 模式更适合多 GPU 并发吞吐
- 对服务器 B 来说，只要最终统一入口还是一个 OpenAI-compatible endpoint，后续 rollout 工序不需要改

### 服务器 B

`agent_rollout.local.env` 里最关键的几项：

```env
MINI_SWE_AGENT_PLUS_ROOT=<服务器B上的绝对路径>
REMOTE_API_BASE=http://127.0.0.1:31000
REMOTE_API_KEY=EMPTY
REMOTE_MODEL_NAME=Kwai-Klear/Klear-AgentForge-8B
REMOTE_PROVIDER=openai
REMOTE_TEMPERATURE=0.0
REMOTE_DROP_PARAMS=true
MSWEA_COST_TRACKING=ignore_errors
MINI_BASE_CONFIG=<服务器B上的 mini-swe-agent-plus>/src/minisweagent/config/extra/swebench.yaml
```

注意：

- 服务器 B 的目录结构可以和服务器 A 完全不同
- 这里只要求填服务器 B 自己的绝对路径

## 4. 实际操作顺序

### Step 1：在服务器 A 上启动 SGLang

```bash
bash scripts/model_serving/start_sglang.sh
```

### Step 2：验证服务器 A 的接口

推荐优先用 `curl` 验证：

```bash
curl -s http://<A_IP>:30000/v1/models
curl -s http://<A_IP>:30000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer EMPTY' \
  -d '{
    "model": "Kwai-Klear/Klear-AgentForge-8B",
    "messages": [{"role": "user", "content": "Reply with exactly: bootstrap-ok"}],
    "temperature": 0.0,
    "max_tokens": 32
  }'
```

### Step 3：在服务器 A 上建立 reverse tunnel 到服务器 B

从真正运行 SGLang 的计算节点执行：

```bash
ssh -i /u/zhe3/.ssh/taurus_ssh_key \
  -o StrictHostKeyChecking=accept-new \
  -o ExitOnForwardFailure=yes \
  -o ServerAliveInterval=30 \
  -o ServerAliveCountMax=3 \
  -N \
  -R 127.0.0.1:31000:127.0.0.1:30000 \
  zhongmouhe@taurus.cs.ucsb.edu
```

### Step 4：在服务器 B 上验证 tunnel

```bash
curl -s http://127.0.0.1:31000/v1/models
curl -s http://127.0.0.1:31000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer EMPTY' \
  -d '{
    "model": "Kwai-Klear/Klear-AgentForge-8B",
    "messages": [{"role": "user", "content": "Reply with exactly: bootstrap-ok"}],
    "temperature": 0.0,
    "max_tokens": 32
  }'
```

### Step 5：在服务器 B 上做 rollout 侧 smoke test

```bash
bash scripts/agent_rollout/doctor.sh
```

### Step 6：跑单实例

```bash
bash scripts/agent_rollout/run_swebench_single.sh sympy__sympy-15599
```

### Step 7：跑小 batch

```bash
bash scripts/agent_rollout/run_swebench_batch.sh --slice 0:3 --workers 2
```

## 5. 多 GPU / router 模式补充记录

### 5.1 运行方式

当前 `start_sglang.sh` 已支持两种模式切换：

- `SGLANG_LAUNCH_MODE=single`
- `SGLANG_LAUNCH_MODE=router`

其中 router 模式会使用：

```bash
python -m sglang_router.launch_server --model ... --tp-size ... --dp-size ...
```

### 5.2 典型现象

router 模式启动时可能出现以下中间状态：

1. `ps` 中已经出现 `sglang::router` 和多个 `sglang::server`
2. `nvidia-smi` 显示多张 GPU 已开始吃显存
3. 端口已经监听
4. 但 `curl /v1/models` 一开始返回：

```text
No models available
```

这通常表示：

- worker 已经在启动
- 但尚未完全注册到 router

此时不要立刻判定为失败，应该：

1. 继续观察 GPU 显存是否上升
2. 再等待几十秒后重新请求 `/v1/models`

当 `/v1/models` 返回标准 JSON 列表后，说明 router 模式已 fully ready。

### 5.3 验证方式

在服务器 A 上建议按这个顺序验证：

```bash
nvidia-smi
ss -ltnp | grep 30000
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

### 5.4 对服务器 B 的影响

切换到多 GPU / router 模式后，服务器 B 侧原则上不需要修改 rollout 脚本。

只需要保证：

1. reverse tunnel 指向新的统一入口
2. `REMOTE_API_BASE` 指向服务器 B 本地对应的 tunnel 端口

也就是说，服务器 B 感知到的仍然只是：

```env
REMOTE_API_BASE=http://127.0.0.1:<forwarded_port>
```

而不是多个 worker 地址。

## 6. 本次踩坑记录

### 6.1 `scripts/lib` 被 `.gitignore` 误伤

顶层 `.gitignore` 有通用规则 `lib/`，导致 `scripts/lib/common.sh` 没有被正确同步。

修复方式：

- 将公共脚本目录改名为 `scripts/common/common.sh`

### 6.2 命令行覆盖的环境变量被 `.env` 再次覆盖

之前的 `load_bootstrap_env` 在 `source` env 文件后，会把命令行传入的变量覆盖掉。例如：

```bash
SGLANG_HOST=141.142.254.201 bash scripts/model_serving/check_openai_chat.sh
```

会被 `.env` 中的 `SGLANG_HOST=0.0.0.0` 覆盖。

修复方式：

- env 加载逻辑改为“命令行显式设置优先”

### 6.3 `health_generate` 空响应导致误报

SGLang 的 `/health_generate` 在当前环境下可能返回空 body，但服务本身是正常的。

修复方式：

- `check_http.sh` 不再要求 `health_generate` 必须返回 JSON
- 对 `health_generate` 只要求 HTTP 可达

### 6.4 `check_openai_chat.sh` 不如直接 `curl` 稳

在当前集群环境中，Python SDK/HTTP 客户端链路一度出现不稳定行为，而 `curl` 能稳定验证真实服务状态。

经验结论：

- 首次排障时优先使用 `curl`
- 脚本 smoke 主要用于回归验证，不要替代基础网络诊断

### 6.5 `swebench_add_edit_tool.yaml` 不适合当前单实例入口

该模板依赖 `{{working_dir}}`，但 `swebench_single.py` 当前上下文里没有提供这个变量，导致：

- `jinja2.exceptions.UndefinedError: 'working_dir' is undefined`

修复方式：

- 改用 `swebench.yaml` 作为 `MINI_BASE_CONFIG`
- 如果需要保留 edit tool 能力，则不要直接修改 `mini-swe-agent-plus` 仓库本身，而是在 `swe-opd/config/mini_swe_agent_plus/` 下维护一份兼容副本，把 `{{working_dir}}` 改为当前环境实际提供的 `{{cwd}}`

### 6.6 LiteLLM 不认识自定义模型名的成本映射

当模型名为 `Kwai-Klear/Klear-AgentForge-8B` 时，LiteLLM 的 cost calculator 不认识这个模型，导致 rollout 在成本统计阶段报错。

修复方式：

- 在服务器 B 环境中设置：

```env
MSWEA_COST_TRACKING=ignore_errors
```

### 6.7 batch 入口和单实例入口对 environment 配置的假设不同

`swebench_pool_way.py` 会直接调用：

```python
DockerEnvironment(**config["environment"])
```

而 `DockerEnvironmentConfig` 不接受 `environment_class` 字段，于是 batch 报错。

修复方式：

- 在生成 rollout config 时，如果 `environment_class == "docker"`，则移除该字段

### 6.8 router 模式依赖额外组件

如果使用：

```env
SGLANG_LAUNCH_MODE=router
```

则需要保证环境中已经安装 `sglang-router`。否则会出现：

```text
ModuleNotFoundError: No module named 'sglang_router'
```

### 6.9 reverse tunnel 端口冲突

从服务器 A 建 reverse tunnel 到服务器 B 时，如果远端端口已被旧 tunnel 占用，会出现：

```text
Error: remote port forwarding failed for listen port ...
```

处理方式：

1. 清理旧 tunnel
2. 或者直接换一个新的 forwarded port

## 7. 当前验收标准

可以认定阶段完成的标准：

1. 服务器 A 上 `curl /v1/models` 和 `curl /v1/chat/completions` 正常
2. reverse tunnel 建立成功，服务器 B 可访问 `127.0.0.1:31000`
3. `doctor.sh` 跑通
4. 单实例 rollout 跑通并生成 trajectory
5. 小 batch rollout 跑通并生成 `preds.json` 与多个 trajectory
6. 在单 GPU serving 和多 GPU router serving 之间切换后，服务器 B rollout 流程仍可复用

## 8. 下一步建议

当前 rollout 链路已经具备继续集成到 Slime 的前置条件。下一阶段建议按以下顺序推进：

1. 明确要保留哪些 trajectory 字段
2. 设计从 mini-swe-agent-plus trajectory 到 Slime `Sample` 的转换
3. 再讨论如何把这条 rollout 链接入训练、teacher 和 OPD
