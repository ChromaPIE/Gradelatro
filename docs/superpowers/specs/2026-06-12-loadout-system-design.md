# Gradelatro 装配方案（Loadout）系统设计

日期：2026-06-12 · 状态：已获用户批准 · 取代旧"黄金左轮"携带（carry）系统

## 1. 背景与目标

旧 carry 系统（单卡袖套 + 窥视卡 + 上场滑入）游戏体验不达标，整体废弃。新系统以 **loadout（装配方案）** 为核心：玩家用 Ⓖ 购买**装配许可证**（12 级阶梯）与**运输服务**（5 档日程），把卡册中的小丑牌编入 loadout，赛局中按运输日程在 boss 盲注 payout 后入场，直接进入小丑区且无视槽位上限。配套**熟练度**成长系统，使玩家评级并真正游玩自己的私藏卡。

## 2. 已确认的设计决策（澄清记录）

| 议题 | 决策 |
|---|---|
| 磨损/丢失 | 评级卡：无磨损、无永久丢失。赛局内被卖/被毁仅本局退场（熟练度停止累积），赛局结束一律"回到"收藏（收藏卡从未离开）。 |
| 未评级（raw）卡 | **可以**编入 loadout，但：恒为 0 级熟练（永远无版本、不累积）、**每次入场结算一次分级磨损**（沿用现磨损模型）、G 视图加入时走二次点击确认警告。 |
| 运输模型 | 五档各自独立永久解锁，装配界面自由切换"当前启用"档；未持有任何运输 = loadout 无法入场。 |
| 熟练度口径 | 入场后每击败一个 boss 盲注 +1（入场底注本身不计）；局内被卖/被毁即停；输局前累积照算并落盘；跨赛局累计；仅评级卡累积。 |
| 入场窗口 | 每窗可选 0~上限张（0=跳过）；金档首窗至多 2 张；无可选卡时不弹窗；跳过/少选的名额**过期不补**；已入场的卡本局视为已消耗（被卖/毁不补）。 |
| 永恒贴纸（III 级） | 价值 = 防局内摧毁效果与误卖、保住整局熟练度收益。 |

## 3. 数据模型

### 3.1 `collection.loadout`（Storage.normalize 标准化）

```lua
loadout = {
    license = 0,            -- 0..12，已购级数（强制按序）
    transports = {},        -- 已解锁集合，如 { blue = true }
    active_transport = nil, -- 当前启用档 key 或 nil
    card_ids = {}           -- 成员卡 id 数组
}
```

### 3.2 卡牌元数据 `card.proficiency`（惰性创建）

```lua
proficiency = {
    antes = 0,            -- 累计通过底注数（仅评级卡累积）
    note = nil,           -- II 级：info queue 自定义文本
    badge_text = nil,     -- IV 级：自定义徽章文本
    tooltip_colour = nil, -- G 级：HEX 字符串（6 位，无 #）
    eternal = false       -- III 级：永恒偏好
}
```

### 3.3 运行态 `G.GAME.grdl_loadout`（随存档）

`{ run_id, entered = { card_id, ... } }`。重载安全：入场记录随赛局存档恢复。

## 4. 许可证矩阵（12 级）

级数 L → 层 t=⌈L/3⌉（1 入门/2 进阶/3 专业/4 G-Cert）、层内 k=((L-1)%3)+1。

- **容量**：L=1→1 张，L=2→2 张，L≥3→3 张（上限）。
- **构成规则**：本层稀有度至多 k 张；更低稀有度容量内不限；更高稀有度 0 张。
- **稀有度映射**：common→1，uncommon→2，rare→3，legendary 与其他模组稀有度（exotic 等）→4。

| 级 | 名称 | 价格Ⓖ | 容量 | 构成上限 |
|---|---|---|---|---|
| 1 | 入门 X1 | 80 | 1 | 仅普通 |
| 2 | 入门 X2 | 160 | 2 | 仅普通 |
| 3 | 入门 X3 | 300 | 3 | 仅普通 |
| 4 | 进阶 X1 | 500 | 3 | 罕见 ≤1 |
| 5 | 进阶 X2 | 750 | 3 | 罕见 ≤2 |
| 6 | 进阶 X3 | 1050 | 3 | 罕见不限 |
| 7 | 专业 X1 | 1400 | 3 | 稀有 ≤1 |
| 8 | 专业 X2 | 1850 | 3 | 稀有 ≤2 |
| 9 | 专业 X3 | 2400 | 3 | 稀有不限 |
| 10 | G-Cert X1 | 3200 | 3 | 传奇/其他 ≤1 |
| 11 | G-Cert X2 | 4200 | 3 | 传奇/其他 ≤2 |
| 12 | G-Cert X3 | 5500 | 3 | 不设限 |

（用户给出的 6 个示例逐条吻合；价格进 `config.loadout.license_prices`，可调。）

### 4.1 成员资格与校验

- raw 与 graded 均可；`queued`（送评中）与 `sold` 拒绝。
- 校验失败理由：`over_capacity` / `rarity_locked`（高于本层）/ `rarity_quota`（本层超 k）/ `invalid_status` / `duplicate` / `unknown_card`。
- 卡被卖出或送评时自动移出 loadout。
- 赛局内 loadout 配置锁定（加入/移出返回 `loadout_locked`）。

## 5. 运输服务

`config.loadout.transports`（key → 定义）：

| 档 | 价格Ⓖ | 入场底注×额度 |
|---|---|---|
| 蓝 blue | 200 | 5×1、6×1、7×1 |
| 绿 green | 450 | 3×1、5×1、7×1 |
| 红 red | 800 | 2×1、4×1、6×1 |
| 紫 purple | 1400 | 1×1、3×1、5×1 |
| 金 gold | 2200 | 1×2、4×1 |

每窗实际上限 = min(窗口额度, 未入场成员数)。切换启用档即时存档，赛局使用开局快照。

## 6. 入场流（赛局集成）

挂点：**boss 盲注 cash-out 完成路径**（Lua wrap + pcall，具体函数在计划期研究确定）。触发顺序：

1. **熟练度结算**：对已入场、仍在小丑区、评级的 loadout 卡 `antes += 1`，落盘（先计数后开窗 → 入场底注不计）。
2. **入场窗口**：当前底注在启用运输日程内且有未入场成员 → 弹选择框（实体卡 CardArea，点击高亮，选 0~上限张，确认/跳过两按钮，超选拦截音效）。以任何方式关闭弹窗（含 ESC/返回）等同跳过。

**生成规则**（确认入场每张卡）：

- `SMODS.add_card` 直接入小丑区，无视槽位上限（原版自然挤压；负片照常 +1 槽 = 占 0 槽）。
- 版本门控：熟练度 0 级强制无版本；I 级（≥5）起带收藏版本。raw 卡恒无版本。
- III 级（≥34）且 `proficiency.eternal` 开启 → 带永恒贴纸。
- raw 卡此刻结算一次分级磨损（`Condition.apply_wear`，参数块 `config.wear`）。
- 生成的小丑打 `ability.grdl_loadout_id`；`entered` 记录该 card_id。

**赛局结束**（胜/负皆同）：仅清运行态；熟练度已逐底注落盘，不回滚。

## 7. 熟练度系统

阈值：I=5、II=13、III=34、IV=89、G=100。

tooltip 通过**原版 info_queue 机制**为带 grdl 元数据的卡追加"熟练度"信息框：等级（0/I/II/III/IV/G）+ 进度（X/下一阈值；G 级显示满级）+ II 级后追加自定义文本行。

| 级 | perk | 操作入口 |
|---|---|---|
| 0 | 入场无版本 | — |
| I | 入场带版本 | 自动生效 |
| II | info queue 自定义文本 | G 视图按钮 → 原版文本输入框 |
| III | 永恒贴纸开关 | G 视图按钮；局内即时作用于在场小丑，局外改偏好 |
| IV | PSA 徽章下方自定义徽章 | G 视图按钮 → 文本输入（per-card） |
| G | tooltip 底色自定义（覆盖深灰底） | G 视图 HEX 输入框，框体背景随色值实时预览；非法 HEX 忽略不生效 |

补充口径：G 级底色作用于该卡 hover tooltip 的所有渲染处（卡册网格与在场 loadout 小丑）；II/IV 级文本长度上限沿用原版输入框 max_length 约束（实现期定具体值）。

**G 键路由扩展**：

- 在场 loadout 小丑（`ability.grdl_loadout_id`）→ **局内检视变体**：无送评/出售/装配按钮，有已解锁的 perk 按钮。
- 卡册检视（局外）→ 「加入装配 / 移出装配」+ 已解锁 perk 按钮。
- raw 卡加入装配：二次点击确认（同卖出 arm 模式），警示文案"会磨损且无熟练度"。

## 8. 界面

1. **卡册按钮行**新增「装配方案」。
2. **装配方案主界面**：顶部副元素 = 许可证等级名 + 容量/稀有度摘要 chips + 当前运输档；主元素 = loadout 实体卡 CardArea（可悬浮/G 检视）；按钮「装配许可证」+ 返回。
3. **装配许可证界面**：12 级阶梯按四层分组展示（已购/可购/锁定三态，仅下一级有购买按钮）+ 运输五档区（未购→购买，已购→启用选择，当前档高亮）+ ref 绑定反馈行。
4. **入场弹窗**：见第 6 节。全部沿用 `create_UIBox_generic_options` + 既有 chips/线框按钮/solid 按钮语汇。

## 9. 模块划分

| 模块 | 职责 | 依赖 |
|---|---|---|
| `src/loadout.lua`（新） | 纯逻辑：成员/矩阵校验、许可证与运输购买、日程窗口计算、入场消耗 | storage, condition, config |
| `src/proficiency.lua`（新） | 纯逻辑：计数、阈值/等级、perk 资格、元数据读写与 HEX 校验 | storage |
| `src/loadout_ui.lua`（新） | 三块界面 + 入场弹窗 + run 钩子 install + 生成逻辑 | loadout, proficiency, ui_common |
| `binder_ui.lua`（改） | G 视图按钮扩展（装配/perk）、G 键路由新分支 | loadout, proficiency |

## 10. 拆除与迁移

- 删除：`src/carry.lua`、`src/carry_ui.lua`、`tests/carry_test.lua`、`tests/carry_ui_test.lua`。
- binder_ui 摘除：toggle_carry、grdl_carry_toggle、检视携带按钮、开册 carry reconcile。
- binder.lua 摘除 `carried` 状态键。
- Storage.normalize 一次性迁移：`status == "carried"` → `raw`；`collection.carry` 清除。
- config：`carry` 参数块更名 `wear`（磨损算法 `Condition.apply_wear` 本体保留）。
- 本地化：carry 相关键删除；loadout 新键 en-us/zh_CN 成对补齐。
- main.lua：CarryUI 装载替换为 LoadoutUI。
- `G.GAME.grdl_carry_active` 旧存档残留标记无害，不处理。

## 11. 测试

- `loadout_test`：矩阵 12 级全覆盖（含用户 6 示例逐条断言）、容量、raw 允许/queued+sold 拒绝、重复、按序购买与扣费、运输购买/切换、日程窗口（含金档双窗）、入场消耗、局内锁定。
- `proficiency_test`：阈值映射、累积口径（仅评级/仅入场后/移除即停）、perk 门控、HEX 校验。
- `loadout_ui_test`：runtime funcs 注册、入场弹窗状态构建与选取钳制、确认入场（fake SMODS.add_card 断言版本门控/永恒/raw 磨损/entered 标记）、底注计数钩子。
- `binder_ui_test`：carry 块删除，新增装配按钮（raw 二次确认）与 perk 按钮处理器断言。
- `storage_test`：carried→raw 迁移。

## 12. 实施切片（每片 TDD + 原子提交）

1. 拆除 + 存储/config 迁移（套件在 carry 消失后全绿）
2. `loadout.lua` 核心 + 测试
3. `proficiency.lua` 核心 + 测试
4. 装配方案两界面 + 卡册入口按钮
5. G 视图：加入/移出装配（raw 二次确认）+ G 键路由局内分支
6. 赛局集成：cash-out 钩子、入场弹窗、生成（版本门控/永恒/磨损）、底注计数、运行态存读
7. perk 界面：info_queue 熟练度框、II 文本、III 永恒开关、IV 徽章、G HEX 实时预览

## 13. 可调参数汇总（`config.loadout`）

`license_prices[12]`、`transports{key→{price, antes, picks}}`、（熟练度阈值常量置于 proficiency.lua，如需调整再提升为 config）。
