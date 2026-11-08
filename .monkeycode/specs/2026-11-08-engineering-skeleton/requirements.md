# Requirements Document

## Introduction

frostrig 是用 Odin 实现的多算法 CPU 挖矿库。当前阶段只建立可扩展工程骨架：包边界、公共类型、算法注册表、平台抽象、FFI 句柄、worker 与 Stratum 骨架、main 组装。本阶段不实现具体哈希算法，不实现 Stratum 登录、job 解析或 share 提交。

## Glossary

- **System**: frostrig 工程骨架及其七个 Odin 包
- **Package**: 同一目录下声明相同 package 名的一组 `.odin` 文件
- **core**: `frostrig_core`，公共类型、错误集、生命周期契约
- **algo**: `frostrig_algo`，算法注册表与分发层
- **worker**: `frostrig_worker`，线程生命周期、任务队列、nonce 分配
- **platform**: `frostrig_platform`，大页内存、CPU 亲和性、NUMA 查询
- **ffi**: `frostrig_ffi`，RandomX 等外部 C 库绑定与 Odin 句柄
- **net**: `frostrig_net`，Stratum 协议骨架
- **main**: `package main`，仅负责组装和启动
- **Large Pages**: 操作系统大页内存（Linux huge pages / Windows large pages）
- **Handle**: ffi 对外暴露的 distinct 句柄，包外不可解释内部指针
- **Registry**: algo 包内按算法 ID 与名称查找函数指针的表
- **Not_Implemented**: `Error` 枚举值，表示骨架过程尚未提供真实行为

## Requirements

### Requirement 1

**User Story:** AS 库作者, I want 项目按固定七包分层, so that 后续算法与协议实现可以在单向依赖下扩展。

#### Acceptance Criteria

1. The System SHALL 将源码组织为 `core/`、`algo/`、`worker/`、`platform/`、`ffi/`、`net/` 与根目录 `main.odin`。
2. The System SHALL 在每个 `.odin` 文件中显式声明 package 名：`frostrig_core`、`frostrig_algo`、`frostrig_worker`、`frostrig_platform`、`frostrig_ffi`、`frostrig_net`、`main`。
3. WHEN 某个包需要导入另一个 frostrig 包, the System SHALL 仅允许按下表白名单导入：`core` 仅 Odin `core:`；`platform` 允许 `core`；`ffi` 允许 `core` 与 `platform`；`algo` 允许 `core` 与 `ffi`；`worker` 允许 `core`、`algo` 与 `platform`；`net` 允许 `core`；`main` 允许上述全部包。
4. IF 某次导入违反白名单, the System SHALL 将该导入视为缺陷并在检查点拒绝合并。

### Requirement 2

**User Story:** AS 库作者, I want core 提供跨包共享类型与错误集, so that 上层包使用同一套契约。

#### Acceptance Criteria

1. The System SHALL 在 `core/` 定义 `Algo_Id`、`Job_Id`、`Worker_Id`、`Nonce`、`Hash`、`Algo_Config`、`Job`、`Share`、`Miner_Config`。
2. The System SHALL 在 `core/` 定义 `Error` 枚举，取值包含 `None`、`Invalid_Argument`、`Not_Initialized`、`Already_Initialized`、`Unsupported_Algo`、`Out_Of_Memory`、`Huge_Pages_Unavailable`、`Thread_Spawn_Failed`、`Affinity_Failed`、`Ffi_Init_Failed`、`Ffi_Handle_Invalid`、`Queue_Full`、`Queue_Empty`、`Not_Implemented`、`Internal`。
3. The System SHALL 将 `Error.None` 的底层值设为 `0`。
4. The System SHALL 在 `core/` 定义 `Lifecycle` 枚举与 `Lifecycle_Hooks`（`init`、`start`、`stop`、`destroy`）。
5. The System SHALL 使 `core/` 不导入 `worker`、`net`、`algo`、`platform`、`ffi`。

### Requirement 3

**User Story:** AS 算法集成者, I want 用函数指针注册表选择算法, so that 具体哈希实现可以后续挂接而不改 worker。

#### Acceptance Criteria

1. The System SHALL 在 `algo/` 定义 `Algo_Handle`、`Algo_Create_Proc`、`Algo_Destroy_Proc`、`Algo_Prepare_Proc`、`Algo_Hash_Proc` 与 `Algo_Entry`。
2. The System SHALL 提供 `register`、`lookup`、`lookup_by_name`、`count`。
3. WHEN `register` 收到空名称, the System SHALL 返回 `Invalid_Argument`。
4. WHEN `register` 收到已存在的算法 ID, the System SHALL 返回 `Already_Initialized`。
5. WHEN `lookup` 或 `lookup_by_name` 未找到条目, the System SHALL 返回 `ok=false`。
6. The System SHALL 使 `algo/` 不包含 `foreign import` 与具体哈希过程体。

### Requirement 4

**User Story:** AS 性能实现者, I want platform 用真实系统调用分配大页内存, so that 后续 RandomX 可以走确定性大页路径。

#### Acceptance Criteria

1. The System SHALL 仅在 `platform/` 实现 `alloc_large_pages(size) -> (ptr, ok)` 与 `free_large_pages(ptr, size)`。
2. WHEN 目标操作系统为 Linux, the System SHALL 使用 `mmap` 申请大页内存。
3. WHEN 目标操作系统为 Windows, the System SHALL 使用 `VirtualAlloc` 申请大页内存。
4. IF 大页分配失败, the System SHALL 返回 `ok=false`，调用方可据此得到 `Huge_Pages_Unavailable`。
5. WHEN 调用方传入有效指针与对应 size, the System SHALL 用与分配匹配的系统调用释放该内存。
6. The System SHALL 将 Linux 实现放在 `memory_linux.odin`，将 Windows 实现放在 `memory_windows.odin`。
7. The System SHALL 使 `algo/`、`worker/`、`ffi/`、`net/`、`main` 不直接调用 `core:sys` 中的平台内存 API。

### Requirement 5

**User Story:** AS 性能实现者, I want CPU 亲和性与 NUMA 查询集中在 platform, so that 其他包通过抽象使用这些能力。

#### Acceptance Criteria

1. The System SHALL 在 `platform/` 声明 `bind_current_thread_to_cpu(cpu_index)` 与 `get_numa_node_for_current_thread()`。
2. The System SHALL 将亲和性实现放在 `affinity_linux.odin` 与 `affinity_windows.odin`。
3. The System SHALL 将 NUMA 查询放在 `numa_linux.odin` 与 `numa_windows.odin`。
4. WHILE 亲和性或 NUMA 仍为骨架, the System SHALL 返回 `Affinity_Failed` 或 `Not_Implemented`。

### Requirement 6

**User Story:** AS 算法集成者, I want ffi 用 Odin 句柄封装 RandomX C API, so that algo 不接触裸 C 指针。

#### Acceptance Criteria

1. The System SHALL 在 `ffi/` 定义 `Rx_Cache`、`Rx_Dataset`、`Rx_Vm` distinct 句柄与 `Rx_Flags`。
2. The System SHALL 声明 `rx_cache_create`、`rx_cache_destroy`、`rx_dataset_create`、`rx_dataset_destroy`、`rx_vm_create`、`rx_vm_destroy`、`rx_vm_set_cache`、`rx_vm_calculate`。
3. WHILE 哈希尚未实现, the System SHALL 使上述计算与创建过程返回 `Not_Implemented` 或 `Ffi_Handle_Invalid`。
4. The System SHALL 将 `foreign import` 与 `foreign` 块仅放在 `ffi/`，并按操作系统拆到 `randomx_linux.odin` 与 `randomx_windows.odin`。
5. The System SHALL 使 `algo/` 只通过上述句柄与过程访问 RandomX。

### Requirement 7

**User Story:** AS worker 实现者, I want 任务队列、nonce 切分与线程池骨架, so that 后续只需通过注册表分发哈希。

#### Acceptance Criteria

1. The System SHALL 在 `worker/queue.odin` 提供 `Job` 入队与出队。
2. IF 队列已满, the System SHALL 返回 `Queue_Full`。
3. IF 队列为空, the System SHALL 返回 `Queue_Empty`。
4. WHEN 给定 `nonce_start`、`nonce_count` 与 `thread_count`, the System SHALL 为每个线程计算互不重叠且并集覆盖原区间的 nonce 子区间。
5. The System SHALL 在 `worker/pool.odin` 提供线程池创建与停止骨架。
6. The System SHALL 使 worker 通过 `algo` 注册表分发任务，并避免直接调用 C 哈希函数与 Stratum 协议。

### Requirement 8

**User Story:** AS 协议实现者, I want Stratum 包只依赖 core 类型, so that 网络层与算法层解耦。

#### Acceptance Criteria

1. The System SHALL 在 `net/` 定义连接配置与会话状态类型。
2. The System SHALL 提供 `connect`、`login`、`submit`、`close` 骨架过程。
3. WHEN 调用上述骨架过程, the System SHALL 返回 `Not_Implemented`。
4. The System SHALL 使 `net/` 只导入 `frostrig_core` 与 Odin `core:`。

### Requirement 9

**User Story:** AS 库作者, I want main 只负责组装, so that 启动路径保持单薄。

#### Acceptance Criteria

1. The System SHALL 在根目录提供 `main.odin`，package 名为 `main`。
2. WHEN `main` 导入 frostrig 包, the System SHALL 在导入点显式指定别名。
3. The System SHALL 使 `main` 只执行包组装与骨架启动。

### Requirement 10

**User Story:** AS 库作者, I want 工程规范可被检查点验证, so that 骨架阶段不滑向算法或协议实现。

#### Acceptance Criteria

1. The System SHALL 使单个过程源码不超过 50 行。
2. The System SHALL 使平台特定逻辑使用 `_linux.odin` / `_windows.odin` 后缀文件。
3. The System SHALL 使 import 语句不带 `when`。
4. The System SHALL 将 vendor 依赖限制为用户明确批准的包；默认仅使用 Odin `core:`。
5. The System SHALL 将哈希算法实现与 Stratum 登录、job 解析、share 提交留到后续阶段。
