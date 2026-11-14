# frostrig 未来规划

> 基于当前工程状态（插件化 ABI 完成、12 算法注册、基准测试通过）制定的后续路线图。
> 优先级按 P0 → P2 排列；P0 为近期必须完成项，P2 为探索项。

## P0 — 近期必须完成

### 1. Stratum 协议实现（net 包）

当前 `net/stratum.odin` 全部方法返回 `Not_Implemented`。需实现：

- **TCP 连接与登录**：解析矿池返回的 `login` 响应，提取 session 与难度
- **Job 分发**：收到 `mining.job` 通知 → 解析 blob / seed / target → 入队 `Job_Queue`
- **Share 提交**：worker 发现合格 nonce → `submit(session, share)` → 解析 ack / stale
- **重连与退避**：指数退避（初始 1s，上限 60s），保留最近 N 个 job
- **心跳**：每 30s 发送 `keepalive`，3 次无响应断开

依赖：`core:net`（TCP socket）+ `core:json`（Stratum 消息解析）。

验收：`--url --user --pass` 参数可用，连接测试矿池（如 `stratum+tcp://` 本地 mock）能完成 login → job → submit 全链路。

### 2. 算法实现补全

| 算法 | 状态 | 需补全 |
|------|------|--------|
| `rx/wow` | 注册但 C 侧未实现 | 链接 librandomx-wow 或降级为 rx/0 + 不同 flag |
| `rx/2` | 同上 | 链接 librandomx-v2 |
| `rx/c64` | 同上 | 链接 C64 变体库 |
| `vh/2.2` / `vh/3.1` | 注册但 C 侧未实现 | 实现 VerusHash C 库（纯 C，~500 行） |
| `argon2d/1000` / `16000` | 已实现 | 无 |

目标：所有 12 个内置算法在 `--list-algos` + `--bench` 下均可运行。

### 3. 插件生命周期完善

当前 `unload_all_plugins` 仅在 `--bench` 路径调用。需补全：

- 普通挖掘路径（非 bench）退出时正确卸载插件
- 支持运行时热加载 / 热卸载（`--plugin-reload <path>`）
- 插件加载失败时打印 stderr 诊断（当前静默跳过）

### 4. 错误处理与日志

- 统一 stderr 日志格式：`[YYYY-MM-DD HH:MM:SS] [LVL] [pkg] msg`
- `errhandler.odin` 扩展为可配置日志级别（`--log-level <debug|info|warn|error>`）
- 算法 create / prepare 失败时打印具体原因（当前仅返回 `Ffi_Init_Failed`）

## P1 — 中期目标

### 5. 大页内存全平台支持

- Linux：`mmap(MAP_HUGETLB | MAP_HUGE_2MB)`（已实现）
- Windows：`VirtualAlloc(MEM_LARGE_PAGES)`（已 stub）
- 运行时探测：启动时检查 `/proc/meminfo` 的 `HugePages_Total`，不足时自动降级并警告
- 配置项：`--huge-pages <auto|on|off>`（当前仅 `--no-huge-pages` 布尔）

### 6. CPU 亲和性 + NUMA 优化

- `platform/affinity_*.odin` 已实现基础设置，需补全：
  - `--cpu-affinity <mask>` 解析（十六进制掩码 → CPU 集合）
  - NUMA 感知：每 worker 绑定到 NUMA node 本地 CPU + 本地内存分配
- 验收：4 线程在 2-NUMA 机器上，每 2 线程绑同一 node，性能提升 ≥ 5%

### 7. 可配置开发费与休息

当前 `worker/fee.odin` 硬编码 `1%` 开发费 + 每 64 切片休息 50s。需补全：

- CLI 参数：`--dev-fee <bps>`、`--rest-interval <slices>`、`--rest-duration <sec>`
- 配置文件：`~/.frostrig/config.json`（费率、矿池地址、线程数、算法）
- 开发费 nonce 区间保留但不哈希（当前实现已做）；未来接入真实矿池时定向提交到开发者地址

### 8. 单元测试补全

当前 `tests/` 覆盖 fee / nonce / registry / lifecycle / worker / net 骨架。需补全：

- 算法 hash 正确性：对 rx/0 输入固定 blob + nonce，断言输出与 C 侧 `randomx_calculate_hash` 一致
- 插件加载失败路径：`--plugin /nonexistent.so` → 不崩溃，stderr 记录
- 多线程竞争：4 worker 并发 enqueue / dequeue，断言无丢 job
- 大页降级：`--no-huge-pages` 下 rx/0 仍可比对（用普通 4 KB 页）

## P2 — 探索项

### 9. 更多挖矿算法

按工作量排序：

| 算法 | 复杂度 | 备注 |
|------|--------|------|
| VerusHash 1.0 | 低 | 已有 2.2 / 3.1，1.0 是简化版 |
| X17 / X16（多算法拼接） | 高 | 需实现 17 / 16 种哈希拼接，每步 ~50 行 C |
| Ethash（CPU 模式） | 中 | 已有 DAG 生成器参考实现 |
| BLAKE2s / Ske（轻量 PoW） | 低 | 适合小额币种 |
| 自定义 ASIC-resist 算法 | 高 | 需密码学背景 |

### 10. 插件 SDK 与示例库

- 提供 `frostrig-plugin-template`（CMake 项目 + CI 模板）供第三方快速开发插件
- 插件文档：ABI 参考、常见错误、性能调优（pipeline vs 逐 hash）
- 示例插件库：`plugins/argon2d-custom.so`（不同迭代参数）、`plugins/x17-demo.so`

### 11. GUI 层

`--no-gui` 参数暗示未来有 GUI。探索方向：

- 原生：Odin 无成熟 GUI 库；可用 webview 嵌入（`--gui webview`）
- 远程：Web 仪表盘（WebSocket + Chart.js），主进程 `--gui http` 暴露 8080 端口
- 监控：实时 H/s、每线程温度、功耗估算、矿池连接状态

### 12. 跨平台构建与发布

- CI：Linux x86_64 / aarch64 / Windows x64 / macOS arm64 矩阵
- 发布：静态链接（Linux 用 `-static`，Windows 已静态链接 ucrt.lib），提供 `.tar.xz` / `.zip`
- 版本管理：git tag + `--version` 输出 commit hash

### 13. 矿池协议扩展

- 支持多矿池 failover（配置 3 个 URL，任一可用即连）
- 支持 Stratum v2（WebSocket 升级）
- 支持 P2P 直接广播（无需矿池，用于测试网）

### 14. 性能优化

- SIMD 加速：Argon2 的 Blamka 函数可用 AVX2 加速（当前用 SSE2）
- 批量哈希：`count` 参数从固定切片改为动态（根据 H/s 自适应）
- 内存布局：RandomX dataset 2 GB 改为 1 GB + 2 GB（减少 cache 污染）

## 里程碑

| 里程碑 | 包含项 | 目标日期 |
|--------|--------|----------|
| M1：可用挖矿 | P0（Stratum + 算法补全 + 插件生命周期 + 日志） | 2026-12-15 |
| M2：生产就绪 | P1（大页全平台 + 亲和性 + 可配置费 + 测试补全） | 2027-01-15 |
| M3：扩展 | P2（更多算法 + SDK + GUI + 发布） | 2027-Q2 |

## 风险与开放问题

1. **Stratum 矿池可用性**：当前无公开 Stratum 矿池可测试；需用本地 mock（`tests/net_test.odin` 已有骨架）
2. **插件安全**：`dlopen` 加载第三方 `.so` 存在代码执行风险；需文档警告 + 可选签名验证（P2）
3. **大页内存不可用**：部分云主机禁用 hugepages；降级路径已实现但性能损失 ~15%，需文档说明
4. **Odin 编译器稳定性**：nightly 版本可能有 breaking change；CI 锁定 commit hash（`odin-linux-amd64-nightly+2026-11-03`）
5. **Keva 变体许可证**：`third_party/randomx-keva` 需确认许可证与 MIT 兼容

## 贡献指南

1. 分支命名：`YYMMDD-<type>-<short-desc>`（见 `submodule-commit-workflow.md`）
2. 提交前运行 `odin check . -no-entry-point` + `odin test .`
3. 新增 C 依赖：vendored 到 `third_party/`，CI 中编译静态库
4. 新增算法：`algo/<name>.odin` + `ffi/<name>_linux.odin` / `_windows.odin` + 注册到 `main.odin`
5. 新增插件 ABI 字段：`algo/plugin.h` 向后兼容（追加字段，不改偏移）
