\# jyd-cpu-project

基于 RV32I 的五级流水线 CPU 设计



\## 项目介绍

本项目是一个基于 RISC-V 32I 指令集的五级流水线 CPU，使用 SystemVerilog 开发，可在 Xilinx xc7k325tffg900-2 开发板上运行。



\## 文件结构

.

├── adapted\_sources/    # CPU 核心设计文件

│   ├── myCPU.sv        # 五级流水线 CPU 顶层模块

│   └── tb\_myCPU\_auto.sv  # 自动测试平台

├── report\_materials.md # 设计报告材料

├── .gitignore          # 过滤 Vivado 生成文件

└── README.md           # 项目说明



\## 开发环境

\- 开发板：xc7k325tffg900-2

\- 开发工具：Vivado

\- 设计语言：SystemVerilog

\- 指令集：RV32I



\## 功能说明

\- 实现完整的 RV32I 基础指令集

\- 五级流水线：取指、译码、执行、访存、写回

\- 支持上板验证

\- 包含自动化测试平台



\## 使用方法

1\. 将所有 .sv 文件导入 Vivado 工程

2\. 添加 xdc 引脚约束

3\. 综合、实现、生成比特流

4\. 下载到开发板运行

