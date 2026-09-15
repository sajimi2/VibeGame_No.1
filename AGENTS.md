# Outpost RPG 工程规则

本项目由 Codex 负责设计、接口与审查，DeepSeek Harness 负责具体实现，用户负责方向与手感确认。

## 开始前
1. 明确当前工作目录是本文件所在的 OutpostRPG，不是上级引擎目录。
2. 阅读 HANDOFF.md、docs/DESIGN.md、docs/ARCHITECTURE.md、docs/TASKS.md 和当前任务对应接口。
3. 阅读 docs/STATUS.md 和已有 reports，检查当前改动；保留其他人的未提交工作。

## 实现约束
- Godot 4.7.2 标准版、GDScript、Windows、Compatibility 渲染器；不引入插件、C#、服务端或第三方测试框架。
- scripts/contracts 是公共协议；通过继承实现抽象端口，不直接实例化它们。
- 可以补充私有方法和实现文件。若需更改公共签名、数据格式或整体玩法，先写 reports/CHANGE_REQUEST.md 描述原因、调用方影响及迁移方案，交给 Codex 审查。
- 常规 bug 修复、私有实现、参数调优在任务内自主完成；不要逐步向用户索要确认。
- 一个任务一份实现报告。基础数值标记为试调默认值，不当作用户最终要求。
- 状态采用 TODO / IN_PROGRESS / READY_FOR_REVIEW / CHANGES_REQUESTED / ACCEPTED。实现者只能推进至 READY_FOR_REVIEW；ACCEPTED 由 Codex 审查后记录。
- T01 和 T02 各有一个审查点；审查通过后再进入下一任务。后续依赖见任务表。
- 不声称占位界面已可玩，不声称无头启动通过就证明手感或图形效果正确。
- 不把 API 密钥、Harness 配置、引擎二进制或本地缓存加入项目。

## 验证和报告
用户最新指示：当前是最小 demo，采用 docs/REVIEW.md 的原型验收标准。只阻塞启动失败、崩溃、常规操作明显失效和核心闭环无法完成；边缘窗口/DPI、非关键整洁度及美术细节记录后继续。不要因已知且非阻塞的未验证项反复返工或询问用户。
运行 scripts/check.ps1 验证导入、脚本解析和启动。按任务添加有意义的边界测试（体力原子性、重复命中、死亡一次性、装备交换、经验跨级、存档往返）。
手动验证按 docs/REVIEW.md 执行；没有实际操作的项写“未验证”。
报告使用 reports/TEMPLATE.md，记录变更文件、命令与退出码、观察结果、未验证项和遗留问题。
