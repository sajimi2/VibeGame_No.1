# 架构与接口

## 文件职责
- scripts/contracts：带类型的抽象端口和数据对象，已建立。方法不含业务实现。
- scripts/actors：CharacterBody2D 角色、输入适配器、行动状态机及 CombatantPort 实现。
- scripts/combat：攻击定义、命中区域、投射物、伤害结算辅助。
- scripts/items：物品定义、InventoryPort 实现和独立实例生成。
- scripts/progression：ProgressionPort 实现及加点策略。
- scripts/world：遭遇、交互、关卡流转、任务和掉落/经验分发。
- scripts/ui：只发出请求和显示状态，不计算伤害、不发奖。
- scripts/persistence：T07 存档版本、验证与恢复。
- scenes：可复用场景；data：配置 Resources；tests：无界面的业务测试；reports：任务证据。

以上是目录约定，不要求预先创建空目录或提前实现未来模块。

## 通信
PlayerInput / EnemyAI → ActorCommandPort → 角色移动与出招。
Hitbox / Projectile → 目标 CombatantPort.receive_hit(DamageEvent) → HitResult。
CombatantPort 信号 → UI；died → Encounter 奖励发放器 → Inventory/Progression。
装备成功后由装配层重算角色属性（基础值 + 当前装备修饰），不在旧结果上反复累加。降低上限时钳制当前值，卸装备不得产生免费治疗。
使用导出 NodePath/节点引用或父场景装配；禁止每帧全树扫描、跨场景硬编码路径、万能全局事件总线。第一版不需要 Autoload 单例。

## 角色节点建议
CharacterBody2D 根节点持有 CollisionShape2D、视觉节点，以及 ActorCommandPort 和 CombatantPort 两个具体子组件。输入/AI 作为可替换子节点。端口引用由角色场景连接；组件不假定父级名字。
状态机单点管理互斥状态。移动与动作发生在 _physics_process；输入适配器对按键边缘仅发出一次 request_action。UI 占用输入时清空意图。
攻击者每次被接受的攻击递增 attack_id，命中去重键为 (source_id, attack_id)。目标只需保留有限时长/数量去重记录；同一 ID 不得在残留判定有效时被重用。有效期结束禁用判定。
source_id 为实例 ID，team_id 区分阵营。攻击范围是世界逻辑像素，不能随窗口缩放改变。

## 接口边界
所有 *.gd 契约均有可解析的声明，抽象方法须由具体类实现。无默认假成功返回值。
协议注释和本文件共同规定语义；若冲突先报告给 Codex。Godot Resource 为引用类型，实例装备须复制 modifiers，不能修改共享定义。
Inventory 快照仅含可序列化值。装备变更只在成功后发信号，失败不改变状态。重载 UI 不得改变逻辑。
Progression 的加点请求、SaveService 的具体保存签名暂未冻结，分别在 T05/T07 开始时由 Codex 补定，Harness 不得自行扩展公共协议。

## 避免过度设计
先有可运行战斗场，再增加内容。禁止在 T01 搭 ECS、网络同步、通用技能编辑器、脚本化任务语言或插件系统。私有小型辅助类可自主添加。
