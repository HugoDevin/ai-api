# AI 開發測試基建（Docker + NVIDIA GPU 版本）

本文件只保留「**已驗證成功**」的路徑：
- WSL + Docker Engine
- NVIDIA GPU
- Ollama + LiteLLM

---

## 架構

- `ai-server`：Ollama（對外 `11434`）
- `litellm`：Gateway（對外 `4000`）
- Spring Boot（本機）連 `http://127.0.0.1:11434`

---

## 1) 啟動 AI 基建（Docker + GPU）

### 方式 A：一鍵腳本（建議）

```bash
sh scripts/start-ai-docker.sh
```

腳本會自動：
1. 檢查 `docker compose`（無 plugin 則 fallback `docker-compose`）。
2. 啟動 `docker-compose.yml + docker-compose.nvidia.yml`。
3. 等待 `http://127.0.0.1:11434/api/tags` ready。
4. 顯示 `ollama ps`（可看到 CPU/GPU Processor）。

### 方式 B：手動啟動

```bash
docker compose -f docker-compose.yml -f docker-compose.nvidia.yml up -d --build
```

---

## 2) 驗證 GPU / 模型

```bash
# 驗證 Docker GPU runtime
docker run --rm --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi

# 驗證 Ollama 執行器（CPU/GPU）
docker compose -f docker-compose.yml -f docker-compose.nvidia.yml exec ai-server ollama ps

# 快速推論測試
docker compose -f docker-compose.yml -f docker-compose.nvidia.yml exec ai-server ollama run llama3 "hello"

# 驗證本地模型清單
curl http://127.0.0.1:11434/api/tags
```

---

## 3) Spring Boot 對接

建議環境變數：

```bash
export SPRING_AI_OLLAMA_BASE_URL=http://127.0.0.1:11434
export AI_GATEWAY_API_KEY=dev-key
mvn spring-boot:run
```

---

## 4) API 驗證

### LiteLLM gateway

```bash
curl http://localhost:4000/v1/models -H "Authorization: Bearer dev-key"
```

### Spring API

```bash
curl -X POST http://localhost:8080/api/v1/analyze \
  -H "Content-Type: application/json" \
  -d '{"proposal":"請分析在 Kubernetes 上部署高可用支付系統"}'
```

---

## 5) 常見問題

### Q1: `docker-credential-desktop.exe: executable file not found in $PATH`
你在 WSL 直跑 Docker Engine（非 Docker Desktop integration）時常見。

目前 `scripts/start-ai-docker.sh` 已自動處理：
- 偵測 helper 缺失
- 使用暫時 `DOCKER_CONFIG`（移除 `credsStore/credHelpers`）後繼續啟動

若你需要 private registry，請執行：

```bash
docker login
```

### Q2: `ollama ps` 顯示 CPU
先確認：

```bash
docker run --rm --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi
```

若這條成功但 `ollama ps` 仍 CPU，建議：
1. 重建並重啟 stack：
   ```bash
   docker compose -f docker-compose.yml -f docker-compose.nvidia.yml down
   docker compose -f docker-compose.yml -f docker-compose.nvidia.yml up -d --build
   ```
2. 再跑一次 `ollama run llama3 "hello"` 後檢查 `ollama ps`。

### Q3: 看即時 log

```bash
docker compose -f docker-compose.yml -f docker-compose.nvidia.yml logs -f ai-server
```
