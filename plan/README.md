# SWE-OPD Plan

本文档目录用于记录 `swe-opd` 项目的目标与阶段计划。

当前文档列表：

- `goals.md`：项目总体目标、当前边界与成功标准
- `overall-plan.md`：从基础设施到最终训练的整体阶段计划
- `rollout-bootstrap.md`：当前阶段的具体计划，只打通模型服务侧 SGLang 与 agent rollout 侧 mini-swe-agent-plus
- `rollout-working-flow.md`：当前已验证可工作的精简流程，包含服务器 A / 服务器 B 的关键配置与运行命令

当前阶段范围明确如下：

- 不做任何训练
- 不接 teacher
- 不接 OPD
- 不接 reward / verifier
- 只打通一条可运行的 agent rollout 链路

当前阶段的核心目标：

1. 模型服务侧启动并暴露一个可远程访问的 SGLang OpenAI-compatible endpoint
2. agent rollout 侧能通过 LiteLLM 调用远程模型
3. agent rollout 侧能在 Docker 中跑通 mini-swe-agent-plus 的 SWE-bench rollout
4. 至少完成单实例和小规模并行 batch 的端到端验证
