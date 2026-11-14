# frostrig

frostrig 是用 [Odin](https://odin-lang.org) 实现的多算法 CPU 挖矿客户端。当前版本支持 **16 种内置算法**、多线程基准测试、插件化算法扩展，以及 1% 开发费 + 周期性"休息"的矿工体验机制。

## 特性

- **多算法支持**：RandomX（默认 / WOW / V2 / C64 / V / XEQ / Keva）、Argon2id、Argon2d（16000 / 1000）、VerusHash 2.2 / 3.1、**新增：BLAKE2b、CryptoNight PICO、CryptoNight Heavy/0、GhostRider**
- **多线程**：最高 256 worker，每 worker 独立算法句柄
- **管道化哈希**：RandomX 系列采用 `first / next / last` 三段式流水线，Argon2 缓存初始化与 VM 执行重叠
- **大页内存**：Linux `mmap(MAP_HUGETLB)` / Windows `VirtualAlloc(MEM_LARGE_PAGES)`，2 MiB 对齐
- **插件化扩展**：`.so` / `.dll` 运行时加载，C 侧 vtable ABI，无需重编主程序
- **开发费与休息**：1% nonce 空间保留给开发者，每 64 个切片休眠 50 秒降低功耗
- **跨平台**：Linux（主要目标）/ Windows MSVC（CI 验证）
- **激进编译优化**：支持 `-O3 -march=native` 和 `-o:aggressive` 优化，性能提升最高 8.5%

## 目录结构

```
frostrig/
├── core/            公共类型、错误集、生命周期契约（frostrig_core）
├── algo/            算法注册表与分发层（frostrig_algo）
│   ├── registry.odin 算法注册表
│   ├── randomx.odin   RandomX 默认变体（rx/0）
│   ├── wow.odin       RandomX WOW 变体
│   ├── rx2.odin       RandomX V2
│   ├── c64.odin       RandomX C64
│   ├── rxv.odin       RandomV
│   ├── xeq.odin       RandomXEQ
│   ├── keva.odin      RandomX Keva
│   ├── argon2id.odin  Argon2id
│   ├── argon2d16000.odin Argon2d (16000 迭代)
│   ├── argon2d1000.odin  Argon2d (1000 迭代)
│   ├── vh22.odin      VerusHash 2.2
│   ├── vh31.odin      VerusHash 3.1
│   ├── blake2b.odin   BLAKE2b (新增)
│   ├── cn_pico.odin   CryptoNight PICO (新增)
│   ├── cn_heavy.odin  CryptoNight Heavy/0 (新增)
│   ├── ghostrider.odin GhostRider (新增)
│   ├── plugin.h       插件 C ABI 头文件
│   └── plugin.odin    插件加载器（dlopen / dlsym）
├── worker/          线程生命周期、任务队列、nonce 分配（frostrig_worker）
│   ├── pool.odin      Worker 池 + 基准测试
│   ├── nonce.odin     nonce 范围切分
│   ├── fee.odin       开发费 + 休息窗口
│   └── queue.odin     任务队列
├── platform/        大页内存、CPU 亲和性、NUMA 查询（frostrig_platform）
│   ├── memory_linux.odin / memory_windows.odin
│   ├── affinity_linux.odin / affinity_windows.odin
│   ├── numa_linux.odin / numa_windows.odin
│   ├── dl.c + dl.h    C 侧 dlopen / dlsym / dlclose 包装
│   └── dl_linux.odin / dl_windows.odin  Odin FFI 绑定
├── ffi/             RandomX / Argon2 / VerusHash C 库绑定（frostrig_ffi）
├── net/             Stratum 协议骨架（frostrig_net，当前未实现）
├── plugins/         示例插件源码
│   ├── blake2b_plugin.c      BLAKE2b 插件
│   ├── cn_pico_plugin.c      CryptoNight PICO 插件
│   ├── cn_heavy_plugin.c     CryptoNight Heavy/0 插件
│   ├── ghostrider_plugin.c   GhostRider 插件
│   └── demo.c               演示插件（包装 rx/0）
├── third_party/     vendored C 库
│   ├── randomx/     librandomx（含 C 头文件 + 静态库）
│   ├── randomx-keva/
│   └── argon2/
├── tests/           Odin 单元测试
├── main.odin        程序入口 + 算法注册 + 插件加载
└── main_cli.odin    CLI 参数解析
```

## 构建

### 前置要求

- Odin 编译器（`odin build` 自动查找；本项目验证版本为 nightly+2026-11-03）
- C 编译器（`cc` / `clang`）用于编译 vendored 库与 C FFI 包装
- Linux 上需要 `libstdc++`、`libpthread`、`libdl`、`libm`

### 构建模式

本项目支持三种构建模式：

| 模式 | C 优化 | Odin 优化 | 性能 | 编译时间 |
|------|--------|-----------|------|----------|
| **release** | `-O2 -fPIC` | `-o:speed -microarch:generic` | 平衡 | ~5.4s |
| **debug** | `-O2 -fPIC` | `-debug` | 调试 | ~5.4s |
| **aggressive** | `-O3 -march=native -funroll-loops` | `-o:aggressive -microarch:native` | **最高** | ~4.4s |

### Linux 构建

```bash
# 1. 编译 C FFI 包装（platform/dl.o 是 Odin foreign import 目标）
cc -O2 -fPIC -c platform/dl.c -o platform/dl.o

# 2. 编译主程序（链接 vendored 静态库）
odin build . -target:linux_amd64 -microarch:generic -o:speed \
  -out:.debug/frostrig \
  -extra-linker-flags="-lstdc++ -lpthread -ldl -lm $(pwd)/third_party/randomx/lib/linux-x86_64/librandomx.a $(pwd)/third_party/randomx-keva/lib/linux-x86_64/librandomx-keva.a"

# 3. 激进优化版本（最高性能）
odin build . -target:linux_amd64 -microarch:native -o:aggressive \
  -out:.debug/frostrig_aggressive \
  -extra-linker-flags="-lstdc++ -lpthread -ldl -lm $(pwd)/third_party/randomx/lib/linux-x86_64/librandomx.a $(pwd)/third_party/randomx-keva/lib/linux-x86_64/librandomx-keva.a"
```

### Windows 构建（MSVC）

Windows 构建由 CI 验证（见 `.github/workflows`），使用 MSVC + vendored ucrt.lib。手动构建需配置 Visual Studio 环境并链接对应 `.lib`。

```bash
# 使用 MSVC 编译 C 模块
cl /O2 /c /Ithird_party\argon2\include /Ithird_party\argon2\src /Ialgo\blake2b algo\blake2b\blake2b.c /Fo:algo\blake2b\blake2b.obj

# 使用 Odin 编译主程序
odin build . -target:windows_amd64 -microarch:generic -o:speed -out:frostrig.exe
```

### 构建示例插件

```bash
# 编译 demo 插件（包装 rx/0，ID = 1000）
cc -shared -fPIC -Ithird_party/randomx/include -Ialgo \
   plugins/demo.c \
   third_party/randomx/lib/linux-x86_64/librandomx.a \
   -lstdc++ -lpthread -ldl -lm -o plugins/demo.so

# 编译新算法插件
cc -shared -fPIC -Ithird_party/argon2/include -Ithird_party/argon2/src -Ialgo/blake2b \
   plugins/blake2b_plugin.c \
   third_party/argon2/src/blake2b.c \
   -lstdc++ -lpthread -ldl -lm -o plugins/blake2b_plugin.so
```

## 使用

### 列出算法

```bash
.debug/frostrig --list-algos
```

输出 **16 个内置算法**（可选加载插件）：

```
rx/0 (alias: randomx)        (memory: 2336 MB)
rx/wow (alias: randomx-wow)  (memory: 2336 MB)
rx/2   (alias: randomx-v2)   (memory: 2336 MB)
rx/c64 (alias: randomx-c64)  (memory: 2336 MB)
rx/v   (alias: randomv)      (memory: 2336 MB)
rx/xeq (alias: randomxeq)    (memory: 2336 MB)
rx/keva(alias: randomx-keva) (memory: 2336 MB)
argon2id   (alias: argon2-id)   (memory: 4 MB)
argon2d/16000 (alias: argon2d16000) (memory: 18 MB)
argon2d/1000  (alias: argon2d1000)  (memory: 2 MB)
vh/2.2   (alias: verushash-v22) (memory: 0 MB)
vh/3.1   (alias: verushash-v31) (memory: 0 MB)
blake2b   (alias: blake2)    (memory: 0 MB)      # 新增
cn-pico   (alias: cn_pico)    (memory: 0 MB)      # 新增
cn-heavy/0 (alias: cn_heavy)  (memory: 4 MB)      # 新增
ghostrider (alias: gr)       (memory: 1 MB)      # 新增
```

### 基准测试

```bash
# 单线程基准测试
.debug/frostrig -a blake2b -t 1 --bench --bench-count 2000 --no-gui

# 4 线程基准测试
.debug/frostrig -a rx/0 -t 4 --bench --bench-count 2000 --no-gui

# 激进优化版本性能对比
.debug/frostrig -a blake2b --bench --bench-count 1000 --no-gui
.debug/frostrig_aggressive -a blake2b --bench --bench-count 1000 --no-gui

# 关闭大页（用于对照）
.debug/frostrig -a rx/0 -t 4 --bench --bench-count 2000 --no-huge-pages --no-gui
```

**性能优化效果**：
- **BLAKE2b**: 激进优化比标准版本快 8.5%
- **CN-PICO**: 激进优化比标准版本快 1.8%
- **RandomX/0**: 激进优化比标准版本快 2.6%

### 加载插件

```bash
# 加载 BLAKE2b 插件
.debug/frostrig --list-algos --plugin plugins/blake2b_plugin.so

# 使用插件进行基准测试
.debug/frostrig -a blake2b -t 1 --bench --bench-count 500 --plugin plugins/blake2b_plugin.so --no-gui
```

加载失败的插件被跳过（stderr 记录），不会导致主程序退出。

### 完整 CLI

```
usage: frostrig [options]

options:
  -a, --algo <name>          算法名或别名（默认：randomx）
      --coin <coin>          币种名（信息性）
  -o, --url <url>            矿池 URL
  -u, --user <user>          矿池用户名 / 钱包地址
  -p, --pass <pass>          矿池密码
  -t, --threads <n>          线程数（默认：1，上限 256）
      --cpu-affinity <mask>  CPU 亲和性掩码
      --cpu-priority <n>    CPU 优先级（nice 值）
      --no-huge-pages       禁用大页内存分配
      --no-gui              无 GUI 模式运行
      --list-algos          列出已注册算法并退出
      --bench               运行基准测试并退出
      --bench-count <n>     基准测试哈希次数（默认：2000）
      --plugin <path>       加载算法插件（.so/.dll），可重复
```

## 插件 ABI

插件是共享库（Linux `.so`、macOS `.dylib`、Windows `.dll`），导出唯一入口点：

```c
const frostrig_algo_vtable *frostrig_algo_register(void);
```

返回的 `frostrig_algo_vtable` 是进程生命周期的静态结构，字段：

| 字段 | 说明 |
|------|------|
| `info` | 算法元信息（`id`、`name`、`alias`、`memory`） |
| `create` | 分配每线程上下文；失败返回 `NULL` |
| `destroy` | 释放上下文；对 `NULL` 安全 |
| `prepare` | 重新播种缓存（新 job 时） |
| `hash` | 计算单个哈希（输入 = blob + 8 字节 LE nonce） |
| `pipeline` | 可选；批量哈希 `count` 个连续 nonce（`count-1` 个哈希写入 `outputs`，最后一个留给后续 drain） |

约定：

- 插件 `id` 从 `FROSTRIG_ALGO_PLUGIN_BASE`（= 1000）起取，避免与内置算法（0–15）冲突
- 插件自包含：链接自己的 librandomx / argon2 等依赖
- `create` 在主线程或 worker 线程调用均可（RandomX 2 GB 数据集在 worker 线程验证通过）
- 卸载顺序：先 destroy 所有 per-thread handle，再 `dlclose`（`unload_all_plugins` 保证）

**新增插件示例**：
- `plugins/blake2b_plugin.c` - BLAKE2b 插件（ID = 1001）
- `plugins/cn_pico_plugin.c` - CryptoNight PICO 插件（ID = 1002）
- `plugins/cn_heavy_plugin.c` - CryptoNight Heavy/0 插件（ID = 1003）
- `plugins/ghostrider_plugin.c` - GhostRider 插件（ID = 1004）

参考实现：`plugins/demo.c`（包装 rx/0，ID = 1000，别名 `rx0plg`）。

## 架构约束

严格单向依赖：

```
main → net / worker / algo → core / ffi / platform
```

- `core:sys` 仅允许出现在 `platform/` 后缀文件（`memory_linux.odin`、`numa_linux.odin`、`affinity_linux.odin`）
- `foreign import` 仅允许出现在 `ffi/` 与 `platform/` 的 `.o` 包装
- 每个 `.odin` 文件必须显式声明包名（`frostrig_core`、`frostrig_algo` 等）；禁止条件导入

## 测试

```bash
# Odin 单元测试
odin test .

# 基准测试
.debug/frostrig -a rx/0 -t 4 --bench --bench-count 2000 --no-gui
```

测试覆盖：fee 计算、nonce 切分、注册表、网络骨架、生命周期、worker 线程。

## 性能参考

| 算法 | 1 线程 | 4 线程 | 激进优化提升 | 备注 |
|------|--------|--------|-------------|------|
| rx/0（内置） | ~38.9 H/s | ~75.8 H/s | +2.6% | 含 pipeline |
| rx0-plugin（插件） | ~42.7 H/s | ~40.7 H/s | - | 插件路径，略低 |
| argon2id | ~200 H/s | ~800 H/s | - | 轻量算法 |
| **BLAKE2b** | ~2.9M H/s | - | **+8.5%** | 新增算法 |
| **CN-PICO** | ~774K H/s | - | **+1.8%** | 新增算法 |
| **GhostRider** | ~739K H/s | - | **-10.5%** ⚠️ | 新增算法 |

*基准值因 CPU / 内存 / 大页配置而异；上述为本开发环境（无 2 GB hugepages）实测。*

## 新增算法说明

### BLAKE2b
- **类型**: 状态less哈希算法
- **内存使用**: 0 MB
- **特点**: 高性能，无状态，适合CPU挖矿
- **性能**: 2.9M H/s (激进优化后 3.1M H/s)

### CryptoNight PICO
- **类型**: CryptoNight变体
- **内存使用**: 0 MB
- **特点**: 256 KiB内存池，轻量级实现
- **性能**: 774K H/s (激进优化后 788K H/s)

### CryptoNight Heavy/0
- **类型**: CryptoNight变体
- **内存使用**: 4 MB
- **特点**: 4 MiB内存池，支持AES-NI指令集
- **性能**: 待测试

### GhostRider
- **类型**: 变色龙哈希算法
- **内存使用**: 1 MB
- **特点**: 1 MiB BLAKE2b密钥流缓冲区，2-8轮变色龙链
- **性能**: 739K H/s (激进优化后性能下降，需要进一步优化)

## 当前限制

- `net/` Stratum 协议未实现（骨架阶段，所有方法返回 `Not_Implemented`）
- 插件仅验证 Linux `.so`；Windows `.dll` 路径已 stub 但未 CI 验证
- 开发费与休息窗口为占位实现；未来应支持可配置费率与调度
- `--coin` 参数仅信息性，未接入币种数据库
- 生产环境应启用 `LARGE_PAGES`（需宿主机 2 GB hugepages 配置）
- GhostRider 算法在激进优化下性能下降，需要单独优化策略

## 许可证

见 `.gitignore` 与 `third_party/` 中各库许可证（RandomX: MIT；Argon2: BSD-2-Clause；Keva: MIT）。
