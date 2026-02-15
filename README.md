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

### Q4: `podman-compose exec ai-server ollama list` 一直是空的
`BOOTSTRAP_MODELS` 是本專案自訂的「要預先 pull 哪些模型」，
`OLLAMA_MODELS` 則是 Ollama 官方的「模型存放路徑」環境變數，兩者用途不同。

`curl http://localhost:4000/v1/models` 有資料**不代表** Ollama 本地模型已下載完成。
LiteLLM 的 `/v1/models` 會回傳它設定檔中的模型清單（`config.yaml`），不是直接等同於 `ollama list` 的本地快取狀態。

先看 `ai-server` 啟動 log：

```bash
podman-compose logs --tail=200 ai-server
```

如果看到持續輸出 `ensuring model` / `waiting model to appear in local list`，表示還在下載或整理模型，完成後會看到：

```text
[ai-server] model bootstrap complete
```

再驗證本地模型：

```bash
podman-compose exec ai-server ollama list
podman-compose exec ai-server curl -s http://localhost:11434/api/tags
```

若 `bootstrap models` 顯示成 `${BOOTSTRAP_MODELS...}` 這類未展開字串，代表 compose 在你的環境沒有正確套用預設值。請重建：

```bash
podman-compose down
podman-compose build --no-cache ai-server
podman-compose up -d
```


### Q5: 模型實體檔案放在哪裡？
預設在容器內 `~/.ollama/models`（root 使用者即 `/root/.ollama/models`）。

本專案把該目錄透過 named volume 持久化：`ollama-data:/root/.ollama`，
所以重建容器後模型仍會保留在 volume 內。

可用以下指令確認：

```bash
podman-compose exec ai-server sh -c 'echo ${OLLAMA_MODELS:-/root/.ollama/models}; ls -lah /root/.ollama; ls -lah /root/.ollama/models'
podman volume inspect ai-api_ollama-data
```

若你曾把 `OLLAMA_MODELS` 設成像 `"llama3 mistral"` 這種值，
Ollama 可能會把它當成「路徑」而不是模型清單，導致你在 `/root/.ollama/models` 看不到檔案。


### Q6: `ResourceAccessException` 打到 `http://localhost:4000/api/chat`
若錯誤是：

```
org.springframework.web.client.ResourceAccessException: I/O error on POST request for "http://localhost:4000/api/chat"
```

代表你把 `spring.ai.ollama.base-url` 指到 LiteLLM（4000）了。
`spring-ai-ollama` 會呼叫 Ollama 原生端點 `/api/chat`，請改成：

```bash
export SPRING_AI_OLLAMA_BASE_URL=http://127.0.0.1:11434
```

然後重啟 Spring Boot。

若你要走 LiteLLM (`/v1/*` OpenAI 相容路徑)，需改用 OpenAI 相容的 Spring AI client。


### Q7: 看不到 AI 診斷 log
本專案已改為使用 Log4j2，設定檔在：`src/main/resources/log4j2-spring.xml`。
預設會把 `com.example.aiapi` 的 INFO log 同時輸出到 console 與檔案 `logs/ai-api.log`（每日/大小輪替）。

若仍看不到，請確認是用最新程式碼重新啟動 Spring Boot，且啟動參數沒有覆蓋 logging config。

可用以下指令即時查看檔案 log：

```bash
tail -f logs/ai-api.log
```



### Q8: `Connection refused` 打到 `http://localhost:11434/api/chat`
若 log 顯示：

```
I/O error on POST request for "http://localhost:11434/api/chat": Connection refused
```

通常是「Spring Boot 執行位置」與 base-url 不匹配：
- Spring Boot 在**主機**上跑：優先用 `http://127.0.0.1:11434`（避免 `localhost` 走 IPv6 `::1`）
- Spring Boot 在**容器**裡跑：用 `http://ai-server:11434`（同一 compose network）

可先從 Spring Boot 所在環境測試：

```bash
curl http://127.0.0.1:11434/api/tags
# 或（容器內）
curl http://ai-server:11434/api/tags
```



### Q9: API 回 `AI_ANALYSIS_FAILED` 並提示 `Connection refused`
新版 API 錯誤訊息會在連線被拒絕時附上環境提示：
- Spring Boot 在主機：`SPRING_AI_OLLAMA_BASE_URL=http://127.0.0.1:11434`
- Spring Boot 在容器：`SPRING_AI_OLLAMA_BASE_URL=http://ai-server:11434`

可先確認 Ollama 健康狀態：

```bash
curl http://127.0.0.1:11434/api/tags
```
