# USRP收发机原型系统

这是一个基于MATLAB+USRP的通信原型系统，实现了用户设备(UE)的上行数据发送功能。**注意：此版本仅支持发送功能，接收功能请参考项目USRP_RX。**

## 系统架构

```
USRP_TR/
├── PHYReceive/          # 物理层接收模块
├── PHYTransmit/         # 物理层发送模块  
├── PHYParams/           # 物理层参数配置
├── MAC/                 # MAC层状态管理
├── RRC/                 # 无线资源控制
├── utils/               # 工具函数
├── logs/                # 日志文件
└── cache_file/          # 缓存文件
```

## 主要功能

- **物理层收发**: 基于OFDM的信号调制解调
- **连接状态管理**: UE与CBS之间的5阶段连接协议
- **参数控制**: 动态PHY参数配置和传输
- **实时处理**: 多进程并行的信号处理架构

## 运行要求

- MATLAB R2020b或更高版本
- Communications Toolbox
- DSP System Toolbox  
- USRP硬件设备(如N310/B210)
- 至少4GB内存用于数据缓冲

## 运行步骤

### 1. 清理环境(可选但推荐)

如果系统之前运行过，**首先在所有MATLAB进程中执行**：
```matlab
clear all;
close all;
```

然后运行清理脚本：
```matlab
deleteCacheLogsFiles
```

⚠️ **重要提示**: 清理缓存前必须先clear所有变量，否则会遇到文件权限错误。

### 2. 启动系统(需要2个MATLAB进程)

#### 进程1: 上行发送
```matlab
USRPUplinkTransmit
```
- 负责UE端上行数据发送
- 管理发送波形生成和传输控制
- 处理连接状态变化触发的数据更新

#### 进程2: 控制终端
用于优雅退出发送进程：
```matlab
% 停止信号发送
stop_receiving
```

### 3. 运行流程

1. **启动顺序**: 先启动进程1(发送)
2. **系统初始化**: 发送进程会自动建立内存映射和缓冲区
3. **开始发送**: 按提示按回车键开始信号发送
4. **状态监控**: 观察终端输出的发送状态和数据速率
5. **优雅退出**: 在进程2中运行停止脚本

## 重要文件说明

### 配置文件
- [`PHYParams/PHYParams.json`](PHYParams/PHYParams.json) - 物理层参数配置
- [`PHYParams/setDefaultParams.m`](PHYParams/setDefaultParams.m) - 默认参数设置

### 核心处理模块
- [`PHYReceive/processOneFrameData.m`](PHYReceive/processOneFrameData.m) - 单帧数据处理
- [`MAC/ueConnectionStateManager.m`](MAC/ueConnectionStateManager.m) - UE连接状态管理
- [`PHYTransmit/transmitData.m`](PHYTransmit/transmitData.m) - 数据发送控制

### 内存管理
- [`PHYReceive/cache_file/received_buffer_new.bin`](PHYReceive/cache_file/) - 接收数据缓冲区
- [`PHYTransmit/cache_file/current_waveform.mat`](PHYTransmit/cache_file/) - 发送波形缓存

## 连接状态说明

系统实现5阶段UE-CBS连接协议：
- **阶段0**: 初始状态，等待CBS广播
- **阶段1**: 接收到CBS信号，发送连接请求  
- **阶段2**: 接收连接响应，发送确认
- **阶段3**: 连接建立，正常数据传输
- **阶段4**: 接收控制参数
- **阶段5**: 确认参数接收

## 日志监控

- **连接日志**: [`MAC/logs/UE_connection_brief_log.txt`](MAC/logs/)
- **详细日志**: [`MAC/logs/UE_connection_verbosity_log.txt`](MAC/logs/)
- **系统日志**: [`logs/`](logs/) 目录下的各种运行日志

## 故障排除

### 常见问题
1. **权限错误**: 确保清理前已clear所有变量
2. **内存不足**: 检查可用内存是否≥4GB
3. **USRP连接**: 确认硬件连接和驱动安装
4. **进程冲突**: 确保按正确顺序启动进程

### 调试选项
- 设置 `cfg.verbosity = true` 启用详细输出
- 设置 `cfg.enableScopes = true` 显示信号分析图
- 检查 [`logs/`](logs/) 目录下的错误日志

## 性能监控

系统提供实时性能指标：
- **误码率(BER)**: 传输质量指标
- **数据速率**: 实时吞吐量统计  
- **信号质量**: EVM、MER、RSSI、CFO测量
- **连接状态**: 实时状态转换监控

---

更多技术细节请参考各模块目录下的源代码注释。