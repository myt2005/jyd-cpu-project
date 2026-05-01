# CPU比赛报告填写材料

本文档用于把当前工程的仿真与性能结果整理成报告素材。可以按需复制到 `仿真报告模版.docx` 和 `设计报告模版.docx` 中。

## 一、仿真报告：2.1 RV32I 指令集测试

### 2.1.1 RV32I 37条指令覆盖测试用例

本测试用于验证自研 CPU 对 RV32I 基础整数指令集中 37 条指令的支持情况。根据比赛要求，测试范围为 RV32I 基础指令中除 `fence`、`ecall`、`ebreak` 外的 37 条指令，覆盖 U 型、J 型、B 型、I 型访存、S 型存储、I 型算术逻辑和 R 型算术逻辑指令。

覆盖指令如下：

| 类别 | 指令 |
| --- | --- |
| U 型 | `lui`, `auipc` |
| 跳转 | `jal`, `jalr` |
| 分支 | `beq`, `bne`, `blt`, `bge`, `bltu`, `bgeu` |
| 访存 Load | `lb`, `lh`, `lw`, `lbu`, `lhu` |
| 存储 Store | `sb`, `sh`, `sw` |
| I 型运算 | `addi`, `slti`, `sltiu`, `xori`, `ori`, `andi`, `slli`, `srli`, `srai` |
| R 型运算 | `add`, `sub`, `sll`, `slt`, `sltu`, `xor`, `srl`, `sra`, `or`, `and` |

测试程序存放在模板工程的 IROM 初始化文件中。CPU 从 `0x8000_0000` 开始取指并运行测试程序。每个指令测试用例执行结束后，程序会根据测试结果更新内存中的通过/失败计数器：

| 项目 | 地址 | 期望值 |
| --- | --- | --- |
| PASS 计数 | `0x8010_0000` | `37` |
| FAIL 计数 | `0x8010_0004` | `0` |

自动检查 testbench 为 `adapted_sources/tb_myCPU_auto.sv`。该 testbench 直接例化 `student_top`，监听 CPU 通过 `perip_bridge` 发出的写操作。当 CPU 向 `PASS_ADDR` 或 `FAIL_ADDR` 写数据时，testbench 自动记录计数值。当 PASS 与 FAIL 的总测试数达到 37 后，自动判断是否满足 `pass_cnt == 37` 且 `fail_cnt == 0`。

源代码体现位置：

| 内容 | 文件位置 |
| --- | --- |
| PASS/FAIL 地址和期望值 | `adapted_sources/tb_myCPU_auto.sv` 第 4 到 10 行 |
| 直接例化 `student_top` | `adapted_sources/tb_myCPU_auto.sv` 第 34 到 42 行 |
| 监听 `perip_wen/perip_addr/perip_wdata` | `adapted_sources/tb_myCPU_auto.sv` 第 78 到 106 行 |
| 自动判断 37 条指令测试结果 | `adapted_sources/tb_myCPU_auto.sv` 第 127 到 145 行 |
| CPU 接入 IROM/DRAM/外设桥 | `digital_twin.srcs/sources_1/new/student_top.sv` 第 52 到 80 行 |

### 2.1.2 指令相关流水线冒险测试用例

由于 RV32I 指令测试程序中包含连续算术运算、访存后使用、条件分支和跳转等场景，因此同时覆盖了流水线冒险处理能力：

| 场景 | 验证内容 | CPU 实现 |
| --- | --- | --- |
| 数据相关 | 后续指令立即使用前序 ALU 结果 | EX/MEM 与 MEM/WB 前递 |
| load-use 冒险 | load 后一条指令立即使用加载结果 | 插入 1 个 stall |
| 分支/跳转 | 条件分支、`jal`、`jalr` 改变 PC | EX 阶段判断跳转并 flush |

源代码体现位置：

| 内容 | 文件位置 |
| --- | --- |
| stall 信号定义 | `adapted_sources/myCPU.sv` 第 69 行 |
| load-use stall 条件 | `adapted_sources/myCPU.sv` 第 352 到 354 行 |
| flush 与 next PC 选择 | `adapted_sources/myCPU.sv` 第 75 到 76 行 |
| 前递信号 `ex_forward_rs1/rs2` | `adapted_sources/myCPU.sv` 第 490 到 510 行 |
| 分支比较与跳转目标 | `adapted_sources/myCPU.sv` 第 553 到 565 行 |

## 二、仿真报告：2.2 RV32I CPU 性能测试

### 2.2.1 五级流水线运行周期测试

本 CPU 采用五级流水线结构：

```text
IF -> ID -> EX -> MEM -> WB
```

在指令集自动测试中，37 个 RV32I 指令测试用例全部通过，仿真输出显示：

```text
cycle_cnt = 859
pass_cnt  = 37 (0x00000025)
fail_cnt  = 0  (0x00000000)
PASS: RV32I 37 instruction tests passed.
```

该结果说明 CPU 能够在流水线结构下完成模板指令测试程序，并正确处理数据相关、访存相关和控制相关。`cycle_cnt = 859` 表示从释放复位到 37 个测试全部完成共消耗 859 个 CPU 周期。若按工程顶层 PLL 中 CPU 时钟 `50 MHz` 计算，37 个测试用例完成时间约为：

```text
859 cycles / 50 MHz = 17.18 us
```

注意：`tb_myCPU_auto` 中为了加快仿真，局部生成的 `cpu_clk` 周期为 10 ns；但板级顶层 `top.sv` 中 CPU 时钟由 PLL 输出，工程实现报告中为 50 MHz。

### 2.2.2 时序性能测试

使用 Vivado 2023.2 对工程进行综合、实现并查看实现后时序报告。当前实现结果满足时序约束：

```text
All user specified timing constraints are met.
clk_out2_pll Period = 20.000 ns, Frequency = 50.000 MHz
WNS = 4.327 ns
TNS = 0.000 ns
Failing Endpoints = 0
```

其中 `clk_out2_pll` 为 CPU 和 `student_top` 主要工作时钟。WNS 为正说明当前设计在 50 MHz 约束下满足建立时间要求。根据 WNS 粗略估算，最差路径等效周期约为：

```text
20.000 ns - 4.327 ns = 15.673 ns
```

理论等效频率约为：

```text
1 / 15.673 ns ≈ 63.8 MHz
```

该值仅为基于当前时序余量的估算，实际修改 PLL 频率后仍需重新综合实现并检查时序。

最差路径位于：

```text
student_top_inst/Core_cpu/ex_mem_alu_result_reg
    -> student_top_inst/bridge_inst/dram_driver_inst/.../RAMS64E/WE
```

说明当前工程的关键路径主要出现在 CPU 访存地址/写使能到模板 DRAM 分布式 RAM 的路径上，而不是 ALU 内部运算路径。

### 2.2.3 资源使用测试

综合后整个工程资源使用如下：

```text
Slice LUTs      : 2142
Slice Registers : 1934
Block RAM Tile  : 0
DSPs            : 0
```

实现后资源使用如下：

```text
Slice LUTs      : 44784
  LUT as Logic  : 12016
  LUT as Memory : 32768
Slice Registers : 1966
Block RAM Tile  : 0
DSPs            : 0
```

实现后 LUT 数量明显增大，主要原因是模板中的 IROM/DRAM 采用 distributed RAM 方式映射，占用了 `32768` 个 LUT 作为存储器。CPU 本体未使用 DSP 和 BRAM，资源占用较低。

## 三、仿真报告：2.3 RV32I CPU 其它测试

### 2.3.1 模板顶层 UART/数字孪生接口测试

本测试使用模板自带 `tb_top.sv`，仿真顶层为 `tb_top`，用于验证完整模板顶层链路是否正常工作：

```text
tb_top serial_rx
    -> top
    -> uart
    -> twin_controller
    -> virtual_sw / virtual_key
    -> status_buffer
    -> uart serial_tx
```

测试流程如下：

| 步骤 | UART 输入 | 作用 |
| --- | --- | --- |
| 1 | `0x00` | 空命令，期望无发送数据 |
| 2 | `0x81` | 设置 `SW[0] = 1` |
| 3 | `0xA0` | 设置 `SW[31] = 1` |
| 4 | `0xC1` | 设置 `KEY[0] = 1` |
| 5 | `0x80` | 读回 18 字节状态数据 |

仿真输出：

```text
PASS: 0x00 instruction
RX[5] = 01
RX[6] = 01
RX[9] = 80
PASS: SW[0] KEY[0] SW[31] data error
```

其中模板最后一行打印文字存在歧义，`tb_top.sv` 中代码实际逻辑为：当 `rx_data[5][0] == 1`、`rx_data[6][0] == 1`、`rx_data[9][7] == 1` 时进入 `else` 并打印 PASS。因此该结果表示 KEY/SW 回读正确。

源代码体现位置：

| 内容 | 文件位置 |
| --- | --- |
| 完整例化 `top` | `digital_twin.srcs/sim_1/new/tb_top.sv` 第 31 到 38 行 |
| UART 发送任务 | `digital_twin.srcs/sim_1/new/tb_top.sv` 第 52 到 66 行 |
| UART 接收任务 | `digital_twin.srcs/sim_1/new/tb_top.sv` 第 68 到 82 行 |
| 发送 SW/KEY 命令 | `digital_twin.srcs/sim_1/new/tb_top.sv` 第 103 到 116 行 |
| 接收并判断 18 字节状态 | `digital_twin.srcs/sim_1/new/tb_top.sv` 第 118 到 128 行 |
| `rx_data` 写入 `sw/key` | `digital_twin.srcs/sources_1/new/twin_controller.sv` 第 122 到 130 行 |
| 18 字节状态排列 | `digital_twin.srcs/sources_1/new/twin_controller.sv` 第 139 到 164 行 |

### 2.3.2 存储器与外设桥接测试

该测试通过 CPU 执行 COE 程序时产生的总线访问，验证 CPU 到模板 `perip_bridge` 的接口连接正确。测试观察信号包括：

```text
perip_wen
perip_addr
perip_wdata
perip_rdata
perip_mask
```

当 CPU 正确执行指令测试程序时，会向 `0x8010_0000` 写 PASS 计数，向 `0x8010_0004` 写 FAIL 计数。自动测试结果中 PASS 计数连续递增至 37，FAIL 计数保持 0，说明 CPU 的访存、存储、数据通路和外设桥接均能够正常工作。

## 四、仿真结果：可直接填写的结果文字

### 3.1 RV32I 指令集测试结果

运行 `tb_myCPU_auto` 后，仿真控制台输出显示 37 个测试用例全部进入 PASS 分支，最终结果如下：

```text
PASS counter write: 37
cycle_cnt = 859
pass_cnt  = 37 (0x00000025)
fail_cnt  = 0  (0x00000000)
PASS: RV32I 37 instruction tests passed.
```

因此，自研 CPU 能够正确执行 RV32I 基础整数指令集中除 `fence`、`ecall`、`ebreak` 外的 37 条指令。

### 3.2 RV32I CPU 性能测试结果

CPU 采用五级流水线结构，并实现了数据前递、load-use stall 和分支 flush。37 个 RV32I 指令测试用例全部完成共消耗 859 个 CPU 周期。工程实现报告显示 CPU 时钟 `clk_out2_pll` 为 50 MHz，WNS 为 4.327 ns，TNS 为 0，Failing Endpoints 为 0，说明设计在 50 MHz 约束下满足时序要求。

综合后资源使用约为 LUT 2142、寄存器 1934、DSP 0、BRAM 0。实现后由于 IROM/DRAM 映射为 distributed RAM，LUT as Memory 为 32768，整体 Slice LUT 为 44784。

### 3.3 RV32I CPU 其它测试结果

运行模板自带 `tb_top` 后，UART 数字孪生链路测试通过。仿真通过 UART 设置 `SW[0]`、`SW[31]`、`KEY[0]` 后，再发送 `0x80` 读回状态，得到：

```text
RX[5] = 01
RX[6] = 01
RX[9] = 80
```

其中 `RX[5][0]` 对应 `KEY[0]`，`RX[6][0]` 对应 `SW[0]`，`RX[9][7]` 对应 `SW[31]`，均与输入命令一致，说明模板顶层 UART、`twin_controller`、虚拟开关/按键回读链路工作正常。

## 五、设计报告可补充内容

### 2.1 RV32I 指令集支持情况

本 CPU 支持 RV32I 基础整数指令集中除 `fence`、`ecall`、`ebreak` 外的 37 条指令，包括 U 型、J 型、B 型、I 型访存、S 型存储、I 型算术逻辑和 R 型算术逻辑指令。当前设计未实现中断、异常、CSR、乘除法扩展、浮点扩展和压缩指令扩展。

### 2.2 CPU 整体架构

CPU 采用五级流水线结构，主要模块包括取指 PC、IF/ID 流水寄存器、译码与立即数生成、寄存器堆、ID/EX 流水寄存器、ALU 与分支判断、EX/MEM 流水寄存器、访存接口、MEM/WB 流水寄存器、写回选择逻辑、数据前递逻辑、load-use stall 逻辑和分支 flush 逻辑。

### 3.1 性能优化：五级流水线

相比单周期 CPU，五级流水线将取指、译码、执行、访存和写回分散到不同周期中，使多条指令能够重叠执行。理想情况下普通 ALU 指令能够接近每周期提交一条。

### 3.2 性能优化：数据前递与冒险处理

CPU 实现了 EX/MEM 和 MEM/WB 到 EX 阶段的前递路径，用于减少连续相关 ALU 指令产生的等待。同时对 load-use 冒险进行检测，在加载结果尚未可用时插入一个气泡，保证功能正确性。对于分支和跳转指令，CPU 在 EX 阶段完成条件判断和目标地址计算，并对错误取入的指令执行 flush。

### 4.1 特色功能：模板外设桥接适配

CPU 按模板工程接口接入 IROM、DRAM 和 MMIO 外设桥。取指地址从 `0x8000_0000` 开始，`student_top` 使用 `pc[13:2]` 作为 IROM 地址。数据访存通过 `perip_addr`、`perip_wen`、`perip_mask`、`perip_wdata` 和 `perip_rdata` 与 `perip_bridge` 连接，从而支持模板中的 DRAM、LED、数码管、按键、开关和计数器地址空间。

## 六、截图与取证步骤

### A. 指令集测试截图

1. 在 Vivado 中将仿真顶层设置为 `tb_myCPU_auto`。
2. 点击 `Run Simulation` 或 `Relaunch Simulation`。
3. 在 Tcl Console 输入：

```tcl
restart
run all
```

4. 截图控制台中以下内容：

```text
PASS counter write: 37
cycle_cnt = 859
pass_cnt  = 37
fail_cnt  = 0
PASS: RV32I 37 instruction tests passed.
```

5. 建议配图标题：

```text
图 x  RV32I 37条指令自动测试通过结果
```

6. 波形中建议添加信号：

```tcl
add_wave /tb_myCPU_auto/uut/pc
add_wave /tb_myCPU_auto/uut/instruction
add_wave /tb_myCPU_auto/uut/perip_wen
add_wave /tb_myCPU_auto/uut/perip_addr
add_wave /tb_myCPU_auto/uut/perip_wdata
add_wave /tb_myCPU_auto/uut/perip_rdata
add_wave /tb_myCPU_auto/uut/Core_cpu/stall
add_wave /tb_myCPU_auto/uut/Core_cpu/flush
add_wave /tb_myCPU_auto/uut/Core_cpu/ex_branch_taken
add_wave /tb_myCPU_auto/uut/Core_cpu/ex_forward_rs1
add_wave /tb_myCPU_auto/uut/Core_cpu/ex_forward_rs2
```

7. 波形截图重点：定位最后一次 `PASS counter write: 37` 附近，展示 `perip_wen` 有效、`perip_addr = 0x80100000`、`perip_wdata = 0x00000025`。

### B. CPU 性能测试截图

1. 使用 `tb_myCPU_auto` 的控制台结果截图 `cycle_cnt = 859`。
2. 在 Vivado 左侧选择：

```text
IMPLEMENTATION -> Open Implemented Design -> Reports -> Timing Summary
```

3. 截图 `Design Timing Summary`，包含：

```text
WNS = 4.327 ns
TNS = 0
Failing Endpoints = 0
All user specified timing constraints are met
```

4. 截图 `Clock Summary`，包含：

```text
clk_out2_pll Period = 20.000 ns
Frequency = 50.000 MHz
```

5. 截图 `Report Utilization`，包含 LUT、寄存器、BRAM、DSP。

6. 建议配图标题：

```text
图 x  CPU时钟域实现后时序报告
图 x  工程资源使用报告
```

### C. 其它测试截图

1. 在 Vivado 中将仿真顶层设置为模板自带 `tb_top`。
2. 点击 `Run Simulation`。
3. 默认只会运行 `1000ns`，继续在 Tcl Console 输入：

```tcl
run all
```

4. 截图控制台中以下内容：

```text
PASS: 0x00 instruction
RX[5] = 01
RX[6] = 01
RX[9] = 80
PASS: SW[0] KEY[0] SW[31] data error
```

5. 波形中建议添加信号：

```tcl
add_wave /tb_top/serial_rx
add_wave /tb_top/serial_tx
add_wave /tb_top/uut/uart_inst/rx_ready
add_wave /tb_top/uut/uart_inst/rx_data
add_wave /tb_top/uut/uart_inst/tx
add_wave /tb_top/uut/uart_inst/tx_start
add_wave /tb_top/uut/uart_inst/tx_data
add_wave /tb_top/uut/twin_controller_inst/sw
add_wave /tb_top/uut/twin_controller_inst/key
add_wave /tb_top/uut/twin_controller_inst/status_buffer
add_wave /tb_top/uut/student_top_inst/virtual_led
add_wave /tb_top/uut/student_top_inst/virtual_seg
```

6. 波形截图重点：展示 `serial_rx` 发送 `0x81/0xA0/0xC1/0x80` 后，`key` 和 `sw` 被置位，并通过 `serial_tx` 发送回 18 字节状态。

### D. 源代码截图建议

报告里每类测试建议至少配一张源码截图：

| 报告部分 | 推荐截图代码 |
| --- | --- |
| 指令集测试设计 | `tb_myCPU_auto.sv` 第 4 到 14 行、第 78 到 106 行 |
| 指令集测试结果判断 | `tb_myCPU_auto.sv` 第 127 到 145 行 |
| 性能优化设计 | `myCPU.sv` 第 352 到 354 行、第 490 到 510 行、第 553 到 565 行 |
| 顶层其它测试 | `tb_top.sv` 第 103 到 128 行 |
| UART/虚拟外设机制 | `twin_controller.sv` 第 122 到 164 行 |

