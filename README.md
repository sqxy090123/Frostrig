# frostrig

frostrig 是用 [Odin](https://odin-lang.org) 实现的多算法 CPU 挖矿客户端。当前版本支持 12 种内置算法、多线程基准测试、插件化算法扩展，以及 1% 开发费 + 周期性"休息"的矿工体验机制。

## 特性

- **多算法支持**：RandomX（默认 / WOW / V2 / C64 / V / XEQ / Keva）、Argon2id、Argon2d（16000 / 1000）、VerusHash 2.2 / 3.1
- **多线程**：最高 256 worker，每 worker 独立算法句柄
- **管道化哈希**：RandomX 系列采用 `first / next / last` 三段式流水线，Argon2 缓存初始化与 VM 执行重叠
- **大页内存**：Linux `mmap(MAP_HUGETLB)` / Windows `VirtualAlloc(MEM_LARGE_PAGES)`，2 MiB 对齐
- **插件化扩展**：`.so` / `.dll` 运行时加载，C 侧 vtable ABI，无需重编主程序
- **开发费与休息**：1% nonce 空间保留给开发者，每 64 个切片休眠 50 秒降低功耗
- **跨平台**：Linux（主要目标）/ Windows MSVC（CI 验证）

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
│   └── demo.c       演示插件（包装 rx/0）
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

### Linux 构建

```bash
# 1. 编译 C FFI 包装（platform/dl.o 是 Odin foreign import 目标）
cc -O2 -fPIC -c platform/dl.c -o platform/dl.o

# 2. 编译主程序（链接 vendored 静态库）
odin build . -target:linux_amd64 -microarch:generic -o:speed \
  -out:.debug/frostrig \
  -extra-linker-flags="-lstdc++ -lpthread -ldl -lm $(pwd)/third_party/randomx/lib/linux-x86_64/librandomx.a $(pwd)/third_party/randomx-keva/lib/linux-x86_64/librandomx-keva.a"
```

### Windows 构建（MSVC）

Windows 构建由 CI 验证（见 `.github/workflows`），使用 MSVC + vendored ucrt.lib。手动构建需配置 Visual Studio 环境并链接对应 `.lib`。

### 构建示例插件

```bash
# 编译 demo 插件（包装 rx/0，ID = 1000）
cc -shared -fPIC -Ithird_party/randomx/include -Ialgo \
   plugins/demo.c \
   third_party/randomx/lib/linux-x86_64/librandomx.a \
   -lstdc++ -lpthread -ldl -lm -o plugins/demo.so
```

## 使用

### 列出算法

```bash
.debug/frostrig --list-algos
```

输出 12 个内置算法（可选加载插件）：

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
```

### 基准测试

```bash
# 单线程
.debug/frostrig -a rx/0 -t 1 --bench --bench-count 2000 --no-gui

# 4 线程
.debug/frostrig -a rx/0 -t 4 --bench --bench-count 2000 --no-gui

# 关闭大页（用于对照）
.debug/frostrig -a rx/0 -t 4 --bench --bench-count 2000 --no-huge-pages --no-gui
```

基准测试输出格式：

```
benchmark: 4 threads x 2000 hashes in 10261 ms  (780.2 H/s total)
```

### 加载插件

```bash
# 加载一个或多个插件（可重复）
.debug/frostrig --list-algos --plugin plugins/demo.so
.debug/frostrig -a rx0-plugin -t 1 --bench --bench-count 500 --plugin plugins/demo.so --no-gui
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

- 插件 `id` 从 `FROSTRIG_ALGO_PLUGIN_BASE`（= 1000）起取，避免与内置算法（0–11）冲突
- 插件自包含：链接自己的 librandomx / argon2 等依赖
- `create` 在主线程或 worker 线程调用均可（RandomX 2 GB 数据集在 worker 线程验证通过）
- 卸载顺序：先 destroy 所有 per-thread handle，再 `dlclose`（`unload_all_plugins` 保证）

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

| 算法 | 1 线程 | 4 线程 | 备注 |
|------|--------|--------|------|
| rx/0（内置） | ~38.9 H/s | ~75.8 H/s | 含 pipeline |
| rx0-plugin（插件） | ~42.7 H/s | ~40.7 H/s | 插件路径，略低 |
| argon2id | ~200 H/s | ~800 H/s | 轻量算法 |

*基准值因 CPU / 内存 / 大页配置而异；上述为本开发环境（无 2 GB hugepages）实测。*

## 当前限制

- `net/` Stratum 协议未实现（骨架阶段，所有方法返回 `Not_Implemented`）
- 插件仅验证 Linux `.so`；Windows `.dll` 路径已 stub 但未 CI 验证
- 开发费与休息窗口为占位实现；未来应支持可配置费率与调度
- `--coin` 参数仅信息性，未接入币种数据库
- 生产环境应启用 `LARGE_PAGES`（需宿主机 2 GB hugepages 配置）

## 许可证

见 `.gitignore` 与 `third_party/` 中各库许可证（RandomX: MIT；Argon2: BSD-2-Clause；Keva: MIT）。
