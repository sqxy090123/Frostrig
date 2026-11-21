# User Instruction Memory

This file records user instructions, preferences, and teachings for reference in future interactions.

## Format

### User Instruction Entry
User instruction entries should follow this format:

[User Instruction Summary]
- Date: [YYYY-MM-DD]
- Context: [Mentioned scenario or time]
- Instructions:
  - [Content of user teaching or instruction, described line by line]

### Project Knowledge Entry
Entries discovered by the Agent during task execution should follow this format:

[Project Knowledge Summary]
- Date: [YYYY-MM-DD]
- Context: Discovered by Agent while performing [specific task description]
- Category: [Operations & Deployment|Build Methods|Testing Methods|Troubleshooting & Debugging|Workflow & Collaboration|Environment Configuration]
- Instructions:
  - [Specific knowledge points, described line by line]

## Deduplication Strategy
- Before adding a new entry, check for similar or identical instructions.
- If a duplicate is found, skip the new entry or merge it with the existing one.
- When merging, update the context or date information.
- This helps avoid redundant entries and keeps the memory file tidy.

## Entries

[Project Knowledge Summary]
- Date: 2026-11-14
- Context: Discovered by Agent while fixing CryptoNight portable AES-128-ECB (software + AES-NI paths)
- Category: Troubleshooting & Debugging
- Instructions:
  - CryptoNight 软件 AES-128 曾产生错误密文，三处根因：(1) `xtime()` GF(2^8) 乘法公式错——旧式 `((x&0x80)?(x^0x1b):0)|((x&0x7f)<<1)` 在 0x80 分支保留了高位，正确为 `((x&0x7f)<<1)^((x&0x80)?0x1b:0)`，单此一条就破坏 MixColumns；(2) `cn_aes_encrypt_block` 的 AddRoundKey 索引在 state/round-key 字节序上转置了；(3) AES-NI 路径误用 `_mm_aesenc` 做密钥扩展（错误原语，它带 MixColumns）并双重应用了 rk[0]。
  - AES-NI 正确做法：密钥扩展复用软件 `cn_aes_key_expand` 的字节结果，`_mm_loadu_si128` 装成 `__m128i` 轮密钥；加密序为 `d ^= rk[0]` → 9 次 `_mm_aesenc(d, rk[1..9])` → `_mm_aesenclast(d, rk[10])`。`_mm_xor_si128` 需 `<emmintrin.h>`（`<wmmintrin.h>` 已含）。
  - AES-128-ECB 基准 oracle 用 openssl：`openssl enc -aes-128-ecb -K <hexkey> -nosalt` 输出含 PKCS7 padding（32 字节），前 16 字节=单块 ECB 密文。NIST SP800-38A（key `000102..0f`, pt `001122..ff` → `69c4e0d86a7b0430d8cdb78070b4c55a`）；FIPS-197（key `2b7e1516..4f3c`, pt `3243f6a8..0b32` → `f84c5d77a7cc60b220ccce00f88128a9`，注意网传 `3925841d...` 不是该 key/pt 的正向密文）。
  - 可信任的 S-box 来源：tree 内 RandomX `third_party/randomx-keva/src/soft_aes.cpp` 的 sbox（与标准 256 表 0-diff）。`xxd` 不可用，用 `od -A n -t x1` 看十六进制。
  - 验证 AES 路径无需整项目构建：把 `crypto_night.c` 的 AES 函数段抽出到 `/tmp/*.c`，stub 掉外部 `blake2b`（签名 `int blake2b(void*,size_t,const void*,size_t,const void*,size_t)`，带 `ARGON2_LOCAL`=hidden visibility），再与 openssl 值比对。

[User Instruction Summary]
- Date: 2026-11-08
- Context: Odin 工程骨架初始化
- Instructions:
  - 严格单向依赖：`main → net/worker/algo → core/ffi/platform`，禁止循环导入
  - `core:sys` 只允许出现在 `platform/` 后缀文件；`foreign import` 只允许出现在 `ffi/`
  - 每个 `.odin` 文件必须显式声明 `frostrig_*` 包名；禁止条件导入
  - 哈希算法、Stratum 协议、网络通信、挖矿产出测试一律不实现；验证仅限连接性与断点
  - 平台大页必须用真实 `mmap`（Linux）/ `VirtualAlloc + MEM_LARGE_PAGES`（Windows），2 MiB 对齐

[Project Knowledge Summary]
- Date: 2026-11-08
- Context: Discovered by Agent while running Odin toolchain setup; updated 2026-11-17 with nightly 17937e9 syntax facts
- Category: Environment Configuration
- Instructions:
  - Odin 编译器：`/usr/local/bin/odin`（wrapper），真实二进制在 `/opt/odin/odin-linux-amd64-nightly+2026-11-03/odin`
  - 需要 `clang`（已通过 apt 安装）作为 LLVM 后端 linker
  - 库包检查命令：`odin check <dir> -no-entry-point`
  - 主包检查/构建：`odin check /workspace -no-entry-point`、`odin build /workspace -out:/tmp/opencode/frostrig`
  - **nightly 17937e9（2026-11-16）语法事实**：无 `var` 关键字（`var x: T` 报错，用 `x := T(0)` 或 `x: T`）；无 receiver 方法语法（`(r: ^T) name :: proc(...)` 不支持，须普通 proc 首参传对象指针）；`@(init)` 须 `proc "contextless" ()`；`for x in a..<b` 循环变量作用域限于循环（结束值须在外部另存）；`+%`/`*%` 报 `Expected an operand`；`[^]u8 + int` 指针算术不支持（须 slice）；`_` 开头 odin 文件被拒；`odin run <file> -file` 单文件模式；switch 须穷举（缺 case 报 "Unhandled switch cases"）；`free()` 只收 `rawptr`，传 `make()` 得到的 `[]u8` 切片会报类型不匹配，需要零分配的 helper 应改为写入调用方提供的缓冲；`make()` 的堆切片转 `string(buf[:])` 后**禁止** `free(buf)`（该 nightly 下 free 需 rawptr），应让调用方持栈数组；字符串拼接 `a + b` 只接受常量，动态拼接用 `fmt.tprintf`（返回单个 string，无 error 通道）；返回栈数组的 `string(arr[:])` 会报 "It is unsafe to return ... refers to the stack memory"。

[Project Knowledge Summary]
- Date: 2026-11-08
- Context: Discovered by Agent while writing and running Odin tests
- Category: Testing Methods
- Instructions:
  - 测试文件放入 `tests/` 目录，package 名统一为 `frostrig_tests`
  - 测试过程必须标注 `@(test)`，签名 `proc(t: ^testing.T)`，import `testing "core:testing"`
  - 断言用 `testing.expect(t, cond, "msg")`
  - 运行命令：`odin test ./tests -define:ODIN_TEST_FANCY=false`（在 `/workspace` 下执行）
  - `odin test` 会自动检测内存泄漏并 WARN；测试中 `new()` 的一次性分配需 `defer free(ptr)` 消除 WARN；`split_nonce_range` 返回的 `[dynamic]Nonce_Range`（来自 `make()`）无法通过 `free()` 直接释放（类型不匹配），相关 WARN 属已知噪声，不影响测试通过
  - `odin test` 第一参数是相对路径 `./tests`，不能写 `tests` 或不带 `./`
  - 当前已覆盖：`lifecycle_test.odin`、`core_test.odin`、`registry_test.odin`、`worker_test.odin`、`nonce_test.odin`、`net_test.odin`（共 18 个测试）
  - 剩余未覆盖（需真实平台权限或 C 桩）：task 6.5（Linux huge pages）、6.6（huge page 属性测试）、7.4（空句柄路径）

[Project Knowledge Summary]
- Date: 2026-11-09
- Context: Discovered by Agent while implementing RandomX FFI binding and CLI
- Category: Troubleshooting & Debugging
- Instructions:
  - Odin nightly 2026-11-03 的 switch 语句存在 bug：同一 switch 块中，只有**第一个** `case` 子句被正确编译，后续 case 会被静默丢弃，导致匹配到这些 case 的输入落入 `default`。解决方法：改用 `if/else if` 链替代多 case 的 switch。
  - `free(&dynarr)` 用于释放 `[dynamic]u8` 时，必须传 `&buf`（数组头地址），不能传 `&buf[0]`（数据指针）；但 `make([dynamic]u8, n)` 分配的数据由 Odin GC 管理，在 FFI 回调路径中若手动 `free(&buf)` 会导致 ASan 崩溃，应直接省略 free 让 GC 回收。
  - `librandomx.a` 是 C++ 静态库，链接时必须加 `-extra-linker-flags="-lstdc++ -lpthread -ldl -lm"`。
  - `randomx_get_flags()` 返回 `0x6a`（JIT|HARD_AES|ARGON2），不含 Large_Pages；OR 上 Large_Pages → `0x6b` → `randomx_alloc_cache` 在沙箱中返回 nil。`rx_try_create` 已实现自动降级：清 Large_Pages 位重试，返回实际使用的 `flags_used`。

[Project Knowledge Summary]
- Date: 2026-11-10
- Context: Discovered by Agent while fixing GitHub Actions android-build workflow (CI log access + NDK URL)
- Category: Troubleshooting & Debugging
- Instructions:
  - GitHub Actions CI 日志/状态查询：用 `echo -e "protocol=https\nhost=api.github.com\n" | git credential fill | grep ^password= | cut -d= -f2` 提取令牌，再调 GitHub API；下载 job 日志需加 `-L`（302 跳转）
  - Android NDK 下载 URL 格式为 `https://dl.google.com/android/repository/android-ndk-<ver>-linux.zip`（文件名带 `android-` 前缀，写 `ndk-<ver>-linux.zip` 会 404 返回 HTML）
  - NDK zip 解压后顶层目录名为 `android-ndk-<ver>/`，`find` 匹配须用 `android-ndk-*` 而非 `ndk-*`
  - NDK 目标三元组：aarch64 用 `aarch64-linux-android36`，armv7 用 `armv7a-linux-androideabi29`；clang/clang++ 命令即 `<triple>-clang`
  - RandomX 上游源码包 `v1.4.6`；`third_party/` 被 gitignore，CI 无法拿到 vendored `librandomx.a`，须在线拉源码交叉编译为 `.so`
  - Android .so 链接跨架构命名的 .so（如 `librandomx-aarch64.so`）时，`-l` 无法匹配，须直接传完整文件路径

[Project Knowledge Summary]
- Date: 2026-11-13
- Context: Discovered by Agent while making build-release Windows jobs pass with MSVC
- Category: Build Methods
- Instructions:
  - Windows CI 用 MSVC `cl.exe`（经 `vcvars64.bat` + Ninja）编译 RandomX/Keva 及 C 模块；MinGW 产出的 `.obj` 会被 `lld-link` 拒绝（`Error(007)` section size mismatch），必须改用 MSVC。
  - MSVC Ninja 产出的库名为 `randomx.lib`（无 `lib` 前缀），FFI 引用的是 `librandomx.lib`，故 CI 须 `cp randomx.lib third_party/.../librandomx.lib` 重命名。
  - Keva `configuration.h` 必须包含 `RANDOMX_FREQ_FMUL_R`、`RANDOMX_FREQ_FDIV_M`、`RANDOMX_FREQ_FSQRT_R`，否则 MSVC C++ 编译 `bytecode_machine.hpp` 报 `C2065` 未声明。
  - MSVC 编译的对象引用 `__imp__aligned_malloc` 等 UCRT 符号，须将 x64 `ucrt.lib`（Windows Kits `*/ucrt/x64/ucrt.lib`）复制到工作区根目录再传完整路径（避免 `C:\Program Files (x86)` 空格被 shell 拆分报 `Error(002) unknown file format "C:\Program"`），同时加 `/NODEFAULTLIB:libucrt.lib /NODEFAULTLIB:libucrtd.lib` 防止静态 `libucrt.lib` 与 DLL 导入重复定义 `calloc`（`Error(024)`）。
  - YAML `run: |` 块内写 `.bat` 时，heredoc `<<BATCH` 内容行须与块首行同缩进（11 空格）；`@echo off` 在列 1 会被 YAML 解析器当作非法 token 报 `found character '@'`。改用 `{ echo "@echo off"; ... } > file.bat` 逐行 echo 写批处理文件最稳妥。
  - `find ... | xargs dirname` 在 GitHub Actions bash 里若 `find` 无输出会触发 `xargs: missing operand` 使步骤退出码 123；`find` 的 `-path` 过滤应直接匹配完整文件名（如 `*/ucrt/x64/ucrt.lib`）而非只匹配目录名 `*/x64`。

[Project Knowledge Summary]
- Date: 2026-11-14
- Context: Discovered by Agent while building and running the frostrig binary; updated 2026-11-14 after adding 4 new C algo modules
- Category: Build Methods
- Instructions:
  - 完整本地构建脚本：`./build-fix.sh`（在 `/workspace` 下），镜像 CI Linux 构建流程（C 模块 → ar 归档 → Odin 链接）
  - Odin 链接必须附带 RandomX 静态库：`-extra-linker-flags="-lstdc++ -lpthread -ldl -lm ${PWD}/third_party/randomx/lib/linux-x86_64/librandomx.a ${PWD}/third_party/randomx-keva/lib/linux-x86_64/librandomx-keva.a"`
  - cryptonight.c 使用 AES-NI 内建函数（wmmintrin.h），gcc 基线 x86-64 无 aes 目标，须加 `-maes`（`-march=native` 隐含）；MSVC 侧用 `/arch:AVX2`
  - C 模块 include 依赖 argon2 树头文件：`-Ithird_party/argon2/include -Ithird_party/argon2/src -Ialgo/<name>`；MSVC 下源文件用 `#include "blake2.h"`（引号形式）以便先命中本地副本
  - argon2_all.o / verushash_all.o 用 `ar rcs` 合成（third_party 源 + algo 包装层）；verushash 的 C++ 源用 `c++ -std=c++11`
  - 运行测试：`odin test ./tests -define:ODIN_TEST_FANCY=false`（23 个测试）；验证 `odin check . -no-entry-point`（rc=0）后再 build
  - 算法冒烟测试：`./frostrig -a <algo> --bench --bench-count 3`（无参数直接运行会进入挖矿循环挂住，需 timeout）

[Project Knowledge Summary]
- Date: 2026-11-13
- Context: Discovered by Agent while optimizing rx/0 via RandomX pipeline (first/next/last batching)
- Category: Troubleshooting & Debugging
- Instructions:
  - rx/0 性能瓶颈是 Argon2 缓存初始化 + `randomx_get_flags()` 无 LARGE_PAGES（0x6a）。Argon2 init 强顺序依赖（每 block 依赖前一 block），无法跨 hash 重叠，因此 `calculate_hash_first/next/last` 双缓冲收益被吃掉，实测仅 +1.5~3.2%（1线程 37.7→38.9，4线程 74.7→75.8 H/s），远低于理论 20-40%。
  - 真正有效的提升方向只有宿主机 2GB 大页（`vm.nr_hugepages` + Large_Pages flag），属运维层面，超出代码层微观优化。
  - C 批量流水线契约：`frostrig_rx0_hash_pipeline(ctx,input,size,start_nonce,count,outputs)` 写 count-1 个 hash，末个 pending，需 `frostrig_rx0_hash_last` 排空；`Algo_Entry.pipeline` 为可选字段（nil 则回退逐 hash 循环），`mine_slice`/`bench_worker_data` 已接入 pipeline 分支。
   - Odin FFI 注意：`c.uint64` 不存在，须用 `c.uint64_t`；FFI 包装函数放 `ffi/randomx_0.odin`（`rx0_hash_pipeline` 签名 `ctx,input,start_nonce:u64,count:u64,outputs:[]u8`）。
   - **mining 看似"卡住"实为 stratum 未实现**：`net/stratum.odin` 的 connect/login/submit/close 全是 `.Not_Implemented`，主路径从不调 net.connect；旧 `for{sleep(1)}` 是静默忙等，无任何 H/s 输出，用户体感"15s 后无响应"。解法（`worker.mine`/`mine_loop` + 主循环 5s 调 `worker.report`）：跨 worker 线程对合成 blob 跑 pipeline，原子计数，周期打印 `[H/s] <algo> threads=N  X H/s  (total Y)`。
   - **Odin `atomic_add` 计数在慢算法下窗口过大=读不出**：rx/0 单 hash ~24ms，`WINDOW=1024` 时一次 `atomic_add` 间隔 ~25s，5s 的 H/s 报告永远读到 0。窗口需调小（`WINDOW=8`）让计数连续累计；原子计数/标志字段放 `[dynamic]u64`/`[dynamic]bool`（堆对齐、池内 rooting）比结构体普通字段更稳。

[User Instruction Summary]
- Date: 2026-11-14
- Context: GitHub authentication and workflow management during Frostrig build process
- Instructions:
  - Use `git credential fill` to authenticate with GitHub CLI for workflow operations
  - This command extracts GitHub credentials from the configured credential helper
  - Required for manual GitHub Actions workflow triggering via `gh workflow run`
  - Usage pattern: `echo -e "protocol=https\nhost=api.github.com\n" | git credential fill | grep ^password= | cut -d= -f2` to extract token
  - Alternative: Set `GH_TOKEN` environment variable with personal access token

[Project Knowledge Summary]
- Date: 2026-11-13
- Context: Discovered by Agent while implementing plugin ABI and FFI
- Category: Troubleshooting & Debugging
- Instructions:
  - Odin FFI cannot directly index C memory (^byte) - must use C helper functions to read data
  - C function pointers in vtable must be read with frostrig_dl_read_ptr (reads *(base+offset))
  - Odin function pointer types: c_*_fn is a function literal type, not a pointer type
  - Call C function pointers with cast(c_*_fn) pe.*_fn (not ^c_*_fn or *c_*_fn)
  - C vtable struct layout: frostrig_algo_info (32 bytes) + 5x8-byte function pointers
  - Plugin ID 1000 (FROSTRIG_ALGO_PLUGIN_BASE) works correctly with linear scan plugin_forward
  - randomx_alloc_cache with 2GB dataset works in both main thread and worker threads
   - demo plugin wraps rx/0 and achieves 44.2 H/s (1-thread) / 73.4 H/s (4-threads), matching built-in rx/0 performance

[Project Knowledge Summary]
- Date: 2026-11-15
- Context: Discovered by Agent while adding Windows x86 (i386) build support to build-release.yaml
- Category: Build Methods
- Instructions:
  - **Odin 架构 build tag 不自动匹配 target 架构**：`#+build windows`（仅 OS tag）会按 target OS 自动选中；但 `#+build windows, amd64` / `#+build windows, i386` 的架构 tag 在 `-target:windows_i386` 下不会被自动排除（两个架构 tag 文件会同时编译 → 符号重定义错误）。OS tag 自动匹配，架构 tag 不匹配。因此跨架构 FFI 不能用架构 build tag 拆分，应采用**架构中性**方案：FFI 引用固定目录（如 `third_party/randomx/lib/windows/librandomx.lib`），CI 每个 job 独立、把当前架构编译出的 `.lib` 拷入该固定目录。
  - **Ninja 生成器不接受 `-A <platform>`**：CMake `cmake -G Ninja -A x64` 报 "Generator Ninja does not support platform specification"。arch 由激活的 vcvars 环境决定（`call vcvars64` = x64，`call vcvarsall x86` = Win32），Ninja 继承 PATH 上的 cl 架构。故 Ninja + MSVC 时去掉 `-A`。
  - **i386 MSVC 需显式链接 `msvcrt.lib`**：32-bit MSVC 的 SEH 异常帧引用 `__except_handler4_common`（MSVCRT 符号）；强制 UCRT import（ucrt/x86/ucrt.lib + /NODEFAULTLIB）后该符号未解析，报 `LNK1120 unresolved external`。解法：i386 链接时追加 `msvcrt.lib`（amd64 走 UCRT，无需）。
  - **i386 aggressive 构建**：32-bit 不支持 AVX2，C 侧 `/arch:AVX2` 去掉、退化为 `/O2`；Odin `-microarch:generic`（不能用 native，64-bit runner 会生成 x86-64 指令塞进 32-bit PE）。vcvars 用 `vcvarsall.bat x86`、`/MACHINE:X86`、ucrt `x86`。
  - **matrix 多架构 include 陷阱**：base `matrix.os×mode`（6 组合）+ `include` 行若对同一 `(os,mode)` 组合写多个不同 `arch`，GitHub 合并时后写覆盖前写，i386 被丢弃。正确做法：把 `arch` 做成 base 轴（`arch: [amd64]`），再用**逐 mode 的 include 行**（每行带 os+mode+arch:i386）新增 i386 组合 → 共 9 job（linux amd64×3 + windows {amd64,i386}×3）。
  - **运行时限制（非构建问题）**：i386 下 RandomX 2 GiB dataset（`RANDOMX_DATASET_BASE_SIZE`）超出 32-bit 4 GiB 用户地址空间，二进制可编译链接但 RandomX 大页运行时会失败；构建层面不受影响。

[Project Knowledge Summary]
- Date: 2026-11-18
- Context: Discovered by Agent while porting the RandomX interpreter VM to pure Odin (`/tmp/opencode/odinrx`)
- Category: Testing Methods
- Instructions:
  - **纯 Odin RandomX interpreter 已过官方测试向量**：`key="test key 000"` / `input="This is a test"` → `639183aae1bf4c9a35884cb46b09cad9175f04efd7684e7262a0ac1c2f0b4e3f`（V1，等价 `RANDOMX_FLAG_FULL_MEM` interpreter 模式）。
  - **两级验证法**（gold 参考 = 官方 `librandomx.a` + per-run 转储 harness `ref_vm_gold3.cpp`）：(1) 秒级测试用**确定性 dataset**（`dataset[i*8]=u64(i)*0x9E3779B97F4A7C15^0xD1B54A32D192ED03`，共 2181038016 字节），VM 与 gold 输出 `7791044d9e6a04c9ff731b5a337a46cb9485c9831c84c70bd1191468a22837e7` 一致；(2) 全量测试用真实 `init_cache` + 34,078,719 个 `init_dataset_item`，单线程约 34 分钟。
  - **构建命令**：`cd /tmp/opencode/odinrx && odin build . -out:buildasm/t`（必须带 `-o:speed`/release，普通 `+`/`*` 才是 wrap 语义）；`./buildasm/t vm` 秒级、`./buildasm/t full` 约 34 分钟。
  - **interpreter VM 移植的四个关键坑**：(1) scratchpad 必须 **16 字节对齐**（`mem.alloc(n, 16)`），`make([]u8,n)` 只有 8 字节对齐，写 `Vec` 时 LLVM 生成 `movaps` → SIGSEGV；(2) `mem.mx` 更新是 C++ **引用语义**（`auto& mp=mem.mx; mp^=...`），必须 `vm.mem.mx ~= ...`；(3) 最终 `blake2b` 输出长度是 **32**（RANDOMX_HASH_SIZE）不是 64；(4) C++ 的 `pc += 1` 在循环尾部（无条件），CBRANCH 用寄存器值当下一条指令地址，未写过寄存器时 target=-1 → pc 必须无条件递增否则越界。
  - **Odin nightly 计时 API**：`os.get_time` 不存在；用 `start := time.now()` + `f64(time.duration_nanoseconds(time.since(start))) / 1e9`（`Time` 是 struct，不能直接相减；`time.Second` 是 `Duration` 与 `Time` 不可相除）。

[Project Knowledge Summary]
- Date: 2026-11-18
- Context: Discovered by Agent while writing repo regression tests for the pure-Odin RandomX package (`tests/randomx_odin_test.odin`)
- Category: Testing Methods
- Instructions:
  - **纯 Odin RandomX 包的回归测试已进 repo**：`tests/randomx_odin_test.odin`，跑法 `cd /workspace && odin test ./tests -define:ODIN_TEST_FANCY=false -target:linux_amd64`（当前 31 个测试全绿；`nonce` 相关 WARN 是既有已知噪声）。覆盖 Blake2b 标准向量（0/3/55/56/64/127/128/129/200/300 字节）+ AES `fillAes1Rx4`/`fillAes4Rx4`/`hashAes1Rx4`（参考值见 `/tmp/opencode/odinrx/ref_aes_gold.txt`）。
  - **写测试向量前先与 Python `hashlib.blake2b` 对拍**，别凭记忆手抄：本轮曾把 256-bit 版 digest 当成 512-bit 版、以及 AES gold 手工拆行时少抄 2 个字符，两次都误判成"实现有 bug"。hex 参考串务必用程序从 gold 文件切分生成。
  - **本 nightly 的 u64 位运算：`~` 既是二元 XOR 也是一元 NOT**（`a ~ b` = XOR，`~a` = NOT），**`^` 不是合法二元运算符**（`a ^ b` 直接 Syntax Error）。因此 `h[i] = h[i] ~ v[i] ~ v[i+8]` 是正确的 BLAKE2b 末轮，`~=` 是 XOR-assign。
  - **`mem.alloc(size, align)` 在本版本只接受 size 整数**，返回 `(rawptr, bool)`，不能传类型；测试里改用**栈数组**（`buf: [3200]u8`）最省事且无泄漏 WARN。
  - **本 nightly 缺少的 API**：`strings.unhex`、`mem.cmp`、`fmt.sprintf`（`fmt.printf` 返回 `int` 不是 `string`）。比对 hex 期望值时自己写逐字节解析 + 差异时 `fmt.printfln` 打印。
  - **数组/结构体复合字面量**：全局作用域**不能**直接给数组变量赋字面量（`x: [T] = {...}` 报 "Expected a type, got '='"），要放进 proc 里用值数组 `[N]T` + 下标赋值；结构体字段与数组元素**都必须带尾随逗号**（含最后一个元素）。
  - **`odin test` 只编译 `tests/`，不影响 `odin build .`**；改动仅测试文件时无需重跑 34 分钟的全量 RandomX 向量回归。

[Project Knowledge Summary]
- Date: 2026-11-18
- Context: Discovered by Agent while making `tests/randomx_odin_entry_test.odin` match the official C library
- Category: Troubleshooting & Debugging
- Instructions:
  - **写 C 侧 gold harness 拼 RandomX 输入时，nonce 必须存进 64 位变量**。`for i in 0..8: buf[len+i] = u8(nonce >> (i*8))` 中若 `nonce` 是 32 位 `unsigned`，`i>=4` 时移位量 ≥ 宽度属**未定义行为**，GCC `-O2` 会算出垃圾字节（实测 nonce=1 拼成 `01 00 00 00 01 00 00 00`）。这会让 nonce≥1 的 gold 值全错、端口看起来"只有第 1 个向量对"。nonce=0 恒为 0 所以永远不暴露 → 极易误判成实现 bug。`core.Nonce :: u64`，Odin 侧无此问题。
  - **定位"端口 vs gold 不一致"的正确顺序**：(1) 先证明 gold 侧确定性（同一输入起**多个独立进程**各算一次，值必须相同；C 侧 `randomx_calculate_hash` 与调用次序无关）；(2) 再用 Python `hashlib.blake2b(d, digest_size=64)` 当第三方裁判验第一步的 `blake2b(input+nonce)`，即可立刻分清是端口错还是 harness 错；(3) 最后才逐字段比 program/寄存器。
  - **逐字段对拍脚手架**：C 侧用 `InterpretedVmDefault` + `randomx_blake2b` 打印 TEMP/SCR/PROG(entrop y 前 128 字节)/REGA/REGE/REGF/REGR/mem.mx/mem.ma/datasetOffset；Odin 侧在包内加临时 `diag_run` proc（包外访问不到未 export 的 `run`/`blake2b`），从测试调起后 diff。`Program` 首字段就是 `entropy[16]`，`RegisterFile` 内存序 r,f,e,a（各 64 字节）。
  - **本 nightly 无 `fmt.hex_str`**；打印字节序列只能循环 `fmt.printfln("%02x", b[i])`。`mem.free` 直接收 `rawptr`（`mem.alloc` 的返回值），不要 cast 成 `^anydata`/`voidptr`（两者都未声明）。
   - **交叉构建 windows 目标需 Windows SDK**（`-windows-sdk-root:<path>`），本环境不具备；`-target:linux_amd64` 已通过即可验证平台中性改动可编译。

[Project Knowledge Summary]
- Date: 2026-11-19
- Context: Discovered by Agent while building `api/` (HTTP/1.1 on core:net) and wiring it into main.odin
- Category: Environment Configuration
- Instructions:
  - **本 nightly（2026-11-16）Odin 陷阱清单（均实测报错/误判）**：
    - `odin build .` 输出的二进制以**目录名**命名：在 `/workspace` 下构建得到 `./workspace`，不是 `./frostrig`（仓库里那个 `frostrig` 是旧产物，不带新 flag，直接跑会误判为"flag 未生效"）。`-out` 参数不存在。
    - `var x: T`（无初始化）是语法错误，用 `x: T`（colon 声明，零值）或 `x := T(0)`。
    - `string([]u8)` **别名**底层字节，不拷贝：`read_request` 里 `string(hdr[:])` 后 `delete(hdr)` 会让 method/path/header 值悬垂（use-after-free，表现为路由 404/垃圾值）。凡返回给调用方的 string 必须 `strings.clone` 或显式拷贝。
    - `strings.split(line, " ")` 返回的元素是**视图**（指进临时数组）：直接 `return fields[1]` 会把悬垂字符串交给调用方，表现为 path 变成单个垃圾字节（0x4C）导致路由 404。返回前必须重新编码，如 `return fmt.tprintf("%s", fields[1])`（tprintf 结果是新分配，安全）。
    - `fmt.tprintf` 把 `{}` 当占位符：`fmt.tprintf(`{"ok":true,"token":"%s"}`, tok)` 输出 `%!(MISSING CLOSE BRACE)ok":true,...`。JSON 字面量拼接用 `strings.concatenate([]string{...})`，或把 `{"x":` 这类花括号片段用 `append(&parts, ...)` 单独追加、数字部分才走 tprintf。
    - **运行时 `+` 字符串拼接禁止**：本 nightly 对任何 `str + var`（无论 backtick 还是双引号、常量还是变量）报 `Error: String concatenation is only allowed with constant strings`（实测：`a+b` 两个变量也报错）。字符串动态拼接一律用 `strings.concatenate([]string{...})`、`strings.builder` 或 `fmt.tprintf`。
    - `sync.Mutex` 用自由函数 `sync.lock(&mu)`/`sync.unlock(&mu)`，`mu.lock()` 报 "no field 'lock'"。
    - `append(&dyn, ..slice)`：slice 展开用 `..` **前缀**（Go 的 `...` 后缀报 `Expected ')', got '..'`）；单元素 `append(&dyn, v)`。
    - map 删键是 `delete_key(&map, key)`，不是 `delete(map, key)`；`delete(m)` 只删整表。
    - `strings.atoi` 不存在；`strconv.parse_int(s, base) -> (value: int, ok: bool)`（atoi 已弃用，`parse_int` 第 3 参是 `^int` 不是 bit_size）。
    - `time.now() - Duration` 不支持，用 `time.time_add(t, -d)`。
    - `core:net`：`net.send`/`net.recv`/`net.send_tcp` 都存在、都返回 `(n, err)` 二元组；string→[]byte 用 `transmute([]byte)str`（`[]u8(str)` 报错）；`net.Address :: union{IP4_Address, IP6_Address}`、`IP4_Any/IP4_Loopback/IP6_Loopback`；`IP6_Address :: distinct [8]u16be`，取字节须 `u16(x)>>8`，不能 `x[0]`。
    - `thread.run_with_poly_data(data: $T, fn: proc(T))` 按**值**传参（`fn(server)` 收到 `^T` 值本身）；`thread.run(fn)` 无参。API 回调须 `proc(^Api_Server)` 而非 `proc()`。
    - **HTTP/1.1 头部键一律小写存储**（parse 时 `to_lower`）；大小写无关查询用 `strings.equal_fold` 遍历（避免 `strings.to_lower` 每次分配泄漏）。
    - Odin stdlib **无 HTTP server**；自建 HTTP/1.1 用 `core:net` 的 `listen_tcp`/`accept_tcp`（accept 返回对端 `Endpoint`）+ `thread.run_with_poly_data` 每连接一线程。
