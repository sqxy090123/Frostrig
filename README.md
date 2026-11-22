# frostrig

frostrig 是用 [Odin](https://odin-lang.org) 实现的多算法 CPU 挖矿客户端。当前版本支持 **18 种内置算法**、多线程基准测试、插件化算法扩展、Stratum 联网挖矿、HTTP 控制 API、以及 Worm/2 行走轨迹可视化 viewer。

## 特性

- **多算法支持**：RandomX（默认 / WOW / V2 / C64 / V / XEQ / Keva / Odin 纯实现）、Argon2id、Argon2d（16000 / 1000）、VerusHash 2.2 / 3.1、**BLAKE2b、CryptoNight PICO、CryptoNight Heavy/0（软件 AES-128 默认，AES-NI 可选）、GhostRider**、**Worm/2（torus 行走轨迹）**
- **多线程**：最高 256 worker，每 worker 独立算法句柄
- **管道化哈希**：RandomX 系列采用 `first / next / last` 三段式流水线，Argon2 缓存初始化与 VM 执行重叠
- **大页内存**：Linux `mmap(MAP_HUGETLB)` / Windows `VirtualAlloc(MEM_LARGE_PAGES)`，2 MiB 对齐
- **插件化扩展**：`.so` / `.dll` 运行时加载，C 侧 vtable ABI，无需重编主程序
- **Stratum 联网**：`net/` 已实现 TCP 连接 / 登录 / 提交 / 关闭 + 读线程，矿池 URL 自动启用 stratum
- **HTTP 控制 API**：`api/` 提供 `/login`、`/config`、`/token/destroy` 端点（默认 `0.0.0.0:18081`，登录密钥启动时打印）
- **Worm/2 可视化**：`gui/` 提供自包含 HTML 页面，轮询 `/gui/trace` 在 Canvas 上渲染 torus 行走轨迹，`/gui/trace` 以每进程 token 门控
- **开发费与休息**：1% nonce 空间保留给开发者，每 64 个切片休眠 50 秒降低功耗
- **跨平台**：Linux（主要目标）/ Windows MSVC（CI 验证）
- **激进编译优化**：支持 `-O3 -march=native` 和 `-o:aggressive` 优化，相对 release 提升约 3–4%

## 目录结构

```
frostrig/
├── core/            公共类型、错误集、生命周期契约（frostrig_core）
├── algo/            算法注册表与分发层（frostrig_algo）
│   ├── registry.odin 算法注册表
│   ├── randomx.odin   RandomX 默认变体（rx/0）
│   ├── randomx_odin/  RandomX 纯 Odin 重实现（rx/odin）
│   │   ├── superscalar.odin / vm.odin / dataset.odin
│   │   ├── argon2.odin / blake2b.odin / context.odin
│   │   └── fpshim.c     C 侧性能 shim
│   ├── randomx_odin_entry.odin rx/odin 入口
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
│   ├── blake2b.odin   BLAKE2b
│   ├── cn_pico.odin   CryptoNight PICO
│   ├── cn_heavy.odin  CryptoNight Heavy/0 (软件 AES-128 默认)
│   ├── ghostrider.odin GhostRider
│   ├── worm2.odin     Worm/2 torus 行走轨迹
│   ├── plugin.h       插件 C ABI 头文件
│   └── plugin.odin    插件加载器（dlopen / dlsym）
├── worker/          线程生命周期、任务队列、nonce 分配（frostrig_worker）
│   ├── pool.odin      Worker 池 + 基准测试
│   ├── nonce.odin     nonce 范围切分
│   ├── fee.odin       开发费 + 休息窗口
│   └── queue.odin     任务队列
├── net/             Stratum 协议（frostrig_net，已实现）
│   ├── stratum.odin  TCP 连接 / 登录 / 提交 / 关闭 + 读线程
│   └── types.odin    会话与端点类型
├── api/             HTTP 控制 API（frostrig_api）
│   ├── http.odin     监听 + 路由 + 连接处理
│   ├── auth.odin     登录密钥（SHA-256 摘要）与认证
│   └── control.odin  运行时控制（pool_url / miner_name / password）
├── gui/             Worm/2 可视化 viewer（frostrig_gui）
│   ├── server.odin   HTTP 服务 + /gui/trace 轮询端点（token 门控）
│   └── page.odin    自包含 HTML 页面（Canvas 2D 渲染，无 CDN）
├── platform/        大页内存、CPU 亲和性、NUMA 查询（frostrig_platform）
│   ├── memory_linux.odin / memory_windows.odin
│   ├── affinity_linux.odin / affinity_windows.odin
│   ├── numa_linux.odin / numa_windows.odin
│   ├── dl.c + dl.h    C 侧 dlopen / dlsym / dlclose 包装
│   └── dl_linux.odin / dl_windows.odin  Odin FFI 绑定
├── ffi/             RandomX / Argon2 / VerusHash C 库绑定（frostrig_ffi）
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
├── tests/           Odin 单元测试（tests/ 目录，而非包根）
├── main.odin        程序入口 + 算法注册 + GUI/api/stratum 编排
├── main_cli.odin    CLI 参数解析
├── main_gui.odin    GUI viewer 启动（Worm/2 采样配置）
├── errhandler.odin  运行时日志/trace
└── build-fix.sh     Linux 本地构建脚本（编译 C 模块 + 链接静态库）
```

## 构建

### 前置要求

- Odin 编译器（`odin build` 自动查找；本项目验证版本为 nightly+2026-11a，commit `9a69916`）
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
# 一键构建（编译所有 C 模块 + 链接 vendored 静态库，产物为 ./frostrig）
./build-fix.sh

# 或手动分步：先编译 C FFI / 算法 C 模块，再编译 Odin 主程序
cc -O2 -fPIC -c platform/dl.c -o platform/dl.o

odin build . -target:linux_amd64 -o:speed \
  -out:frostrig \
  -extra-linker-flags="-lstdc++ -lpthread -ldl -lm $(pwd)/third_party/randomx/lib/linux-x86_64/librandomx.a $(pwd)/third_party/randomx-keva/lib/linux-x86_64/librandomx-keva.a"

# 激进优化版本（最高性能）
odin build . -target:linux_amd64 -microarch:native -o:aggressive \
  -out:frostrig_aggressive \
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
./frostrig --list-algos
```

输出 **18 个内置算法**（可选加载插件）：

```
rx/0 (alias: randomx)        (memory: 2336 MB)
rx/odin (alias: randomx-odin)  (memory: 2336 MB)
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
blake2b   (alias: blake2)    (memory: 0 MB)
cn-pico   (alias: cn_pico)    (memory: 0 MB)
cn-heavy/0 (alias: cn_heavy)  (memory: 4 MB)
ghostrider (alias: gr)       (memory: 1 MB)
worm/2   (alias: worm2)      (memory: 2048 MB)
```

### 基准测试

```bash
# 单线程基准测试
./frostrig -a blake2b -t 1 --bench --bench-count 2000 --no-gui

# 4 线程基准测试
./frostrig -a rx/0 -t 4 --bench --bench-count 2000 --no-gui

# 激进优化版本性能对比
./frostrig -a blake2b --bench --bench-count 1000 --no-gui
./frostrig_aggressive -a blake2b --bench --bench-count 1000 --no-gui

# 关闭大页（用于对照）
./frostrig -a rx/0 -t 4 --bench --bench-count 2000 --no-huge-pages --no-gui
```

**性能优化效果**（aggressive 相对 release，Odin nightly+2026-11a 实测）：
- **BLAKE2b**: 激进优化比标准版本快 3.8%
- **CN-PICO**: 激进优化比标准版本快 3.1%
- **GhostRider**: 激进优化比标准版本快 3.2%
- **RandomX/0**: 激进优化比标准版本快 2.6%（历史实测，未在本次重测）

### 加载插件

```bash
# 加载 BLAKE2b 插件
./frostrig --list-algos --plugin plugins/blake2b_plugin.so

# 使用插件进行基准测试
./frostrig -a blake2b -t 1 --bench --bench-count 500 --plugin plugins/blake2b_plugin.so --no-gui
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
      --stratum             （legacy）矿池 URL 现在自动启用 stratum
      --no-gui              无 GUI 模式运行
      --list-algos          列出已注册算法并退出
      --bench               运行基准测试并退出
      --bench-count <n>     基准测试哈希次数（默认：2000）
      --gui                 打开 Worm/2 行走 viewer（无矿池 URL）并持续服务
      --gui-port <p>        viewer 端口（默认：18090）
      --gui-stride <n>      行走标记步长（默认：4096）
      --gui-trail <n>       淡出轨迹保留的格子数（1..11）
      --test                先跑一次基准哈希，然后永久服务 viewer
      --plugin <path>       加载算法插件（.so/.dll），可重复
```

### Worm/2 可视化 viewer

```bash
# 启动 Worm/2 torus 行走 viewer（无矿池 URL，持续服务）
./frostrig --algo worm/2 --gui

# 自定义采样步长与轨迹长度，然后打开浏览器访问 http://<host>:18090/
./frostrig --algo worm/2 --gui --gui-stride 1024 --gui-trail 5

# 先跑一次基准哈希，再保持 viewer 打开（--test 要求 --gui 且无矿池 URL）
./frostrig --algo worm/2 --test --gui
```

- 页面是自包含 HTML（无 CDN），轮询 `/gui/trace` 在 Canvas 2D 上渲染 torus 行走轨迹
- `/gui/trace` 以**每进程 token 门控**：token 在启动时生成并嵌入页面，页面经 `X-Trace-Token` 头回显；缺失或错误 token 返回 403
- `--gui` 仅驱动 Worm/2 行走且需无矿池 URL；配其它算法或带矿池 URL 时给出提示并继续

### HTTP 控制 API

```bash
# 启动矿工（会打印 login key）
./frostrig -a rx/0 -t 1 --url stratum+tcp://pool.example.com:3333 -u wallet -p x

# 另开终端：用 login key 获取 token，再调用控制端点
curl -X POST http://127.0.0.1:18081/login -H 'Content-Type: application/json' \
  -d '{"key":"<login-key>"}'
curl -X POST http://127.0.0.1:18081/config -H 'Content-Type: application/json' \
  -H "Authorization: Bearer <token>" -d '{"pool_url":"...","miner_name":"...","password":"..."}'
curl -X POST http://127.0.0.1:18081/token/destroy -H "Authorization: Bearer <token>"
```

- 默认监听 `0.0.0.0:18081`；启动时打印一次性 login key（只保留其 SHA-256 摘要）
- `/login` 交换 login key 换取访问 token；`/config` 更新运行时矿池配置；`/token/destroy` 吊销并轮换 token（新 token 打印到 stdout）
- token 可从 `Authorization: Bearer <token>`、`X-Auth-Token: <token>` 或 `?token=<token>` 查询参数提供（按此顺序）
- **loopback 豁免**：来自本机且未携带代理头的请求免 token（便于本地运维）；经代理转发的请求仍须带 token
- 监听失败非致命：矿工照常运行，仅无 API

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

- 插件 `id` 从 `FROSTRIG_ALGO_PLUGIN_BASE`（= 1000）起取，避免与内置算法（0–18）冲突
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
main → net / worker / algo / api / gui → core / ffi / platform
```

- `core:sys` 仅允许出现在 `platform/` 后缀文件（`memory_linux.odin`、`numa_linux.odin`、`affinity_linux.odin`）
- `foreign import` 仅允许出现在 `ffi/` 与 `platform/` 的 `.o` 包装
- 每个 `.odin` 文件必须显式声明包名（`frostrig_core`、`frostrig_algo` 等）；禁止条件导入

## 测试

```bash
# Odin 单元测试（tests/ 目录）
odin test tests/

# 基准测试
./frostrig -a rx/0 -t 4 --bench --bench-count 2000 --no-gui
```

测试覆盖：fee 计算、nonce 切分、注册表、Stratum 网络、生命周期、worker 线程、RandomX 纯 Odin 实现、Worm/2 行走、GUI viewer（页面/token 门控/采样配置）、API 端点。

## 性能参考

| 算法 | 1 线程（release `-o:speed -microarch:generic`） | 4 线程 | aggressive（`-o:aggressive -microarch:native`）相对提升 | 备注 |
|------|--------|--------|-------------|------|
| rx/0（内置） | ~38.9 H/s | ~75.8 H/s | +2.6% | 含 pipeline |
| rx0-plugin（插件） | ~42.7 H/s | ~40.7 H/s | - | 插件路径，略低 |
| argon2id | ~200 H/s | ~800 H/s | - | 轻量算法 |
| **BLAKE2b** | ~4.3M H/s | - | **+3.8%** | 无状态算法 |
| **CN-PICO** | ~1.55M H/s | - | **+3.1%** | 256 KiB 内存池 |
| **CN-Heavy/0** | ~70K H/s | - | - | 软件 AES 默认 |
| **GhostRider** | ~950K H/s | - | **+3.2%** | 1 MiB 密钥流缓冲 |

*以上为本开发环境（无 2 GB hugepages、Odin nightly+2026-11a）实测：`-a <algo> -t 1 --bench --bench-count 100000 --no-gui`，每种模式 3–5 轮取均值。rx/0、argon2id、CN-Heavy/0 的历史数值未在本次重测（rx/0 需 2 GiB 数据集，本机内存不足）。基准值随 CPU / 内存 / 大页配置而异。*

## 新增算法说明

### BLAKE2b
- **类型**: 状态less哈希算法
- **内存使用**: 0 MB
- **特点**: 高性能，无状态，适合CPU挖矿
- **性能**: ~4.3M H/s（release `-o:speed`）

### CryptoNight PICO
- **类型**: CryptoNight变体
- **内存使用**: 0 MB
- **特点**: 256 KiB内存池，轻量级实现
- **性能**: ~1.55M H/s（release `-o:speed`）

### CryptoNight Heavy/0
- **类型**: CryptoNight 变体
- **内存使用**: 4 MB
- **特点**: 4 MiB 内存池 + AES-128-ECB 步骤。AES-128 默认走**可移植软件实现**（无 arch-flag 依赖，跨编译器/目标确定），可选 `FROSTRIG_CN_AESNI`（gcc `-maes`）启用 AES-NI 硬件加速路径；两路径密文一致（已对照 openssl NIST/FIPS 向量验证）
- **性能**: 软件默认路径约 70K H/s（1 线程，无 2 GB hugepages）

### GhostRider
- **类型**: 变色龙哈希算法
- **内存使用**: 1 MB
- **特点**: 1 MiB BLAKE2b密钥流缓冲区，2-8轮变色龙链
- **性能**: ~950K H/s（release `-o:speed`，aggressive 模式约 +3%）

### RX/ODIN (rx/odin)
- **类型**: RandomX 纯 Odin 重实现
- **内存使用**: 2336 MB
- **特点**: 完整移植 argon2d / blake2b / superscalar VM / 2 GiB 数据集，`algo/randomx_odin/` 无 C 库依赖，仅一个 `fpshim.c` 提供 SIMD shim
- **状态**: 与 C 版 librandomx 结果对齐，可作交叉校验与去 C 依赖的备选路径

### WORM/2 (worm/2)
- **类型**: torus 行走轨迹算法（非挖矿哈希）
- **内存使用**: 2048 MB
- **特点**: 在 torus 矩阵上行走，`gui/` 提供 Canvas viewer 实时可视化；`--gui-stride` 控制标记步长（默认 4096），`--gui-trail` 控制淡出轨迹格数（1..11，默认 11）
- **说明**: 配合 `--gui` 使用（需无矿池 URL）；`--test` 先跑一次基准哈希再长期服务 viewer

## 当前限制

- 插件仅验证 Linux `.so`；Windows `.dll` 路径已 stub 但未 CI 验证
- 开发费与休息窗口为占位实现；未来应支持可配置费率与调度
- `--coin` 参数仅信息性，未接入币种数据库
- HTTP 控制 API 与 GUI viewer 默认绑定 `0.0.0.0`（api 为 18081、viewer 为 18090）；暴露到公网前应在防火墙/反代层收敛监听地址
- 生产环境应启用 `LARGE_PAGES`（需宿主机 2 GB hugepages 配置）

## 许可证

本项目（frostrig 自研代码）以 **MIT** 许可证发布，见仓库根目录 `LICENSE`。

第三方组件（随仓库 vendored，保留其原版权/许可证声明，均为宽松许可、无强 copyleft）：

| 组件 | 位置 | 上游 | 许可证 |
|------|------|------|--------|
| VerusHash C++ 核心 | `algo/verushash/` | VerusCoin `src/crypto/verus_hash.cpp` | MIT |
| Verus clhash (portable) | `algo/verushash/vh_clhash_portable.cpp` | VerusCoin `verus_clhash_portable.cpp`（源自 Lemire clhash） | Apache-2.0 |
| Haraka | `algo/verushash/haraka_portable.c` | Haraka (kste, 2016) | MIT |
| sse2neon | `algo/verushash/sse2neon.h` | SSE2NEON 项目 | MIT |
| Argon2 / BLAKE2b 参考头 | `algo/{blake2b,cryptonight,ghostrider}/` | Argon2 reference | CC0 1.0 / Apache-2.0 |
| RandomX | `third_party/randomx`、`third_party/randomx-keva` | RandomX 项目 | MIT |
| Argon2 C 实现 | `third_party/argon2` | Argon2 reference | CC0 1.0 / Apache-2.0 |

再分发时请保留上述组件随附的版权声明与许可证文本；Apache-2.0 组件需按其条款提供许可与变更说明。

## AI 使用与贡献声明

- 本项目允许使用 AI 工具（含代码生成）辅助开发与贡献。
- 由 AI 生成、经项目维护者审核后合并的代码，随仓库整体受根目录 MIT 许可证约束。
- AI 生成内容不单独主张版权；人类维护者对最终合并的代码负责。

