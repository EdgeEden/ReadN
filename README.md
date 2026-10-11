# ReadN

<p align="center">
  <strong>新一代面向科研与深度学习的跨平台 PDF / Markdown 智能阅读工作台</strong><br>
  <em>AI-Powered Cross-Platform Scholarly PDF Reader & Knowledge Workspace</em>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/version-v1.1.27-blue.svg?style=flat-square" alt="Version">
  <img src="https://img.shields.io/badge/Flutter-3.47+-02569B?style=flat-square&logo=flutter&logoColor=white" alt="Flutter">
  <img src="https://img.shields.io/badge/FastAPI-0.110+-009688?style=flat-square&logo=fastapi&logoColor=white" alt="FastAPI">
  <img src="https://img.shields.io/badge/Platform-Web%20%7C%20Windows%20%7C%20Android-green?style=flat-square" alt="Platforms">
  <img src="https://img.shields.io/badge/license-MIT-purple.svg?style=flat-square" alt="License">
</p>

---

## 📖 简介 (Introduction)

**ReadN**（Read + Note + Next）是一款专为学术论文研读、专业技术文档阅读及知识精细化沉淀而设计的现代化阅读器。

针对传统 PDF 阅读器公式无法提取、排版僵硬、批注与知识管理脱节等痛点，ReadN 提供了**双模态阅读引擎**，结合内置的高性能 LaTeX 公式交互、深度 Mineru 智能解析、多端云同步以及多模型 AI 辅助，让学术论文与大部头技术书籍的阅读更专注、更流畅。

---

## ✨ 核心特性 (Key Features)

- 📑 **双模态阅读引擎**
  - **原生 PDF 模式**：基于流式加载与虚拟化视口渲染，即便面对数百兆的大型文献也能秒级开启、拒绝卡死。
  - **Markdown 智能重排模式**：将扫描件/复杂排版 PDF 一键转化为结构清晰的 Markdown 文档，支持段落重排、目录自动解析与图片自适应嵌入。
- 🧮 **深度 LaTeX 公式交互与高亮**
  - 原生渲染行内公式（`$...$`）与展示公式（`$$...$$`），字符级垂直居中对齐。
  - **首创公式-文本混合荧光高亮**：选区跨越多个数学公式时自动智能切片，保留精致发光胶囊视觉的同时确保文本流式折行，杜绝排版断裂。
  - 支持公式源码一键复制与公式级划词提问。
- 💡 **精细化学术批注与知识卡片**
  - **多色荧光笔**：支持多色高亮、自动容错锚定。
  - **知识卡片 (Knowledge Cards)**：划词一键提炼概念，生成可视化卡片并汇聚于侧边栏。
  - **边读边记 (Margin Notes)**：支持行间即时注解与富文本沉淀。
  - **多端实时同步**：毫秒级本地缓存，联网状态下自动双向云同步。
- ✍️ **移动端手写笔与触控分离架构 (Stylus Mode & Hand-Pen Separation)**
  - **原生手写笔特化 (Android 平板/手机)**：开启手写笔模式后，笔尖划过文本即选即弹菜单，无需费力长按；笔尖长按任意空白处直接插入点位批注；手指与手掌仅用于页面滚动与双指缩放，彻底杜绝手掌误触。
  - **全平台交互兼容**：非手写笔模式下支持手指长按划词与长按批注；桌面端 (Windows/Web PC) 保持传统鼠标右键、框选交互，完全不受移动端手势干扰。
  - **边缘自适应与防溢出**：选区浮动菜单自适应屏幕边界，选区靠近屏幕边缘时触发平滑自适应边缘滚屏。
  - **PDF / Markdown 双模态交互体验一致**：手写笔划词选区、气泡菜单与批注卡片在 PDF 和 Markdown 引擎下保持高度一致的使用手感。
- 🤖 **内置深度 AI 学术伴读助手**
  - 支持自定义接入 OpenAI、DeepSeek、Moonshot (Kimi) 等兼容 OpenAI 协议的模型。
  - **思维链可视化**：完整展现模型的深度思考与推理过程（Reasoning State）。
  - 支持划词即问、长篇综述总结、知识卡片自动提炼。
- ⚡ **智能 OCR 与无缝分片**
  - 深度整合 Mineru 高性能解析引擎。
  - 针对单文件 200MB / 200 页限制，后台静默自动切片并发解析并平滑合并，提供上传速率与全流程进度感知。

---

## 🏗️ 架构概览 (Architecture)

```mermaid
graph LR
    subgraph Frontend ["前端 (Flutter Multi-Platform)"]
        UI["Reader & Bookshelf Views"]
        Engine1["Native PDF Engine (pdfrx)"]
        Engine2["Markdown Engine (flutter_markdown + KaTeX)"]
        Annotation["Highlight & Card Manager"]
        AIClient["AI Chat & Prompt Engine"]
    end

    subgraph Backend ["后端 (FastAPI Cloud Service)"]
        API["FastAPI REST Endpoints"]
        Sync["Annotation & Document Sync"]
        Cache["Static & Chunk Cache"]
        MineruProxy["Mineru OCR Acceleration"]
    end

    UI --> Engine1
    UI --> Engine2
    UI --> Annotation
    UI --> AIClient
    Annotation <--> Sync
    Engine2 <--> MineruProxy
```

- **Frontend**：Flutter 3.47+ (Dart 3.13+)，支持 Web、Windows x64 桌面端及 Android 移动端。
- **Backend**：FastAPI (Python 3.10+)、Uvicorn、SQLite / PostgreSQL。
- **Deployment**：支持 Docker 化部署或一键部署至轻量云服务器。

---

## 🔑 凭据与 API Key 配置指南 (API Key Configuration)

为了保障您的数据私密与资金安全，**ReadN 开源仓库不包含任何硬编码密钥或云端服务器地址**。所有 API Key 均采用**客户端本地存储 (Local Storage) 或服务端环境变量**管理：

### 1. AI 伴读大模型 API Key（用于侧边栏对话、划词提问与思维链推理）
ReadN 原生兼容 OpenAI 标准 API 规范，支持国内外主流大语言模型：
- **DeepSeek (强烈推荐)**：访问 [DeepSeek 开放平台](https://platform.deepseek.com) 注册并创建 API Key，畅享 DeepSeek-V3 与 DeepSeek-R1 深度推理模型。
- **硅基流动 (SiliconFlow)**：访问 [SiliconFlow 平台](https://cloud.siliconflow.cn) 获取 API Key，享受高速云端模型聚合。
- **OpenAI**：访问 [OpenAI Platform](https://platform.openai.com/api-keys) 获取 API Key。
- **Moonshot (Kimi)**：访问 [Moonshot 开放平台](https://platform.moonshot.cn) 获取 API Key。

> **配置方式**：在阅读界面点击右上角 **AI 设置 (⚙️)**，填入对应的 API Key 与模型名称。Key 仅保存在您本机的浏览器缓存或本地设备中，绝不上传至任何中间服务器。

### 2. MinerU 智能 PDF 转 Markdown API Token（用于论文/公式/图表精准提取）
- **获取方式**：访问 [MinerU 官方开放平台 (mineru.net)](https://mineru.net)，注册登录后进入“API 接口”页面创建并获取您的专属 Token。
- **配置方式**：
  - **客户端配置**：在阅读界面点击“转换为 Markdown”，展开**【高级选项】**，在输入框填入您的 MinerU Token 即可（客户端会自动记住供后续使用）。
  - **服务端配置**：若搭建私有化后端，可在启动时设置环境变量：
    ```bash
    export MINERU_API_TOKEN="your_mineru_token_here"
    ```

### 3. 百度飞桨 PaddleOCR Token（备用 OCR 引擎）
- **获取方式**：访问 [百度飞桨 AI Studio (aistudio.baidu.com)](https://aistudio.baidu.com) 申请 API 访问 Token。
- **配置方式**：在转换弹窗的高级选项中填入，或在服务端设置环境变量 `export BAIDU_OCR_TOKEN="your_token_here"`。

### 4. 后端服务器地址配置
客户端默认连接本地开发地址 `http://localhost:18903`。若您部署了远程专属服务器，可在主界面右上角**设置 -> 服务器连接**中填入您的服务器地址与端口。

---

## 🚀 快速上手 (Quick Start)

### 1. 环境准备
- [Flutter SDK](https://flutter.dev/docs/get-started/install) (>= 3.24.0)
- [Python](https://www.python.org/) (>= 3.10)

### 2. 后端服务启动
```bash
# 1. 进入后端目录
cd backend

# 2. 安装 Python 依赖
pip install -r requirements.txt

# 3. 启动开发服务器
uvicorn app.main:app --host 0.0.0.0 --port 18903 --reload
```

后端服务启动后，可在浏览器访问 `http://localhost:18903/docs` 查看交互式 API 文档。

### 3. 前端启动与构建
```bash
# 1. 进入前端目录
cd frontend

# 2. 获取依赖
flutter pub get

# 3. 本地调试 (Web / 桌面端)
flutter run -d chrome
# 或运行 Windows 桌面端
flutter run -d windows

# 4. 生产打包
flutter build web --release      # Web 发布包
flutter build windows --release  # Windows 安装包
flutter build apk --release      # Android APK
```

---

## 📦 版本控制与部署 (Versioning & Deployment)

ReadN 内置了自动化版本管理规范：

- **版本自增**：运行 `python scripts/bump_version.py` 或通过 Git 提交钩子自动更新 Semantic Version（当前版本 `v1.1.27`）。
- **一键服务器部署**：
  ```bash
  python scripts/deploy_to_hk.py
  ```
  自动化完成前端产物同步、TAR 打包、SCP 上传、远程解压以及 systemd 服务无缝热重启。

---

## 📝 开源协议 (License)

本项目采用 [MIT License](LICENSE) 开源协议。

