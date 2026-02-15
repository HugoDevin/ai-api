# AI 開發測試基建（給 Spring Boot 使用）

你要的是「**獨立 AI 環境**」來給 Spring Boot 測試/開發，不是把 Spring Boot 打包進 Docker。

本專案現在提供的容器只包含：

- `ai-server`：Ollama（啟動時自動準備模型）
- `litellm`：Gateway（對外 API Key 驗證）

## 架構

Spring Boot (本機執行，spring-ai-ollama)
→ Ollama `http://127.0.0.1:11434`

LiteLLM `http://localhost:4000` 可獨立驗證模型列表與金鑰，但不是 Ollama `/api/chat` 端點。

## 1) 快速啟動 AI 基建

```bash
podman-compose up -d --build
```

啟動後：
- `ai-server`: `localhost:11434`
- `litellm`: `localhost:4000`

## 2) 模型準備


### NVIDIA GPU（Podman）
若你的主機是 NVIDIA，先確認目前 Podman 型態：

```bash
podman --version
podman compose version
```

- 若 `podman compose` 可用（新版 plugin + CDI）：

```bash
podman-compose -f podman-compose.yml -f podman-compose.nvidia.yml up -d --build
```

- 若 `podman compose` 不可用、且 `nvidia.com/gpu=all` 出現 `no such file or directory`：
  請改用 legacy override（直接映射 `/dev/nvidia*`）：

```bash
podman-compose -f podman-compose.yml -f podman-compose.nvidia.legacy.yml up -d --build
```

- 若你在 WSL2，且錯誤為 `stat /dev/nvidia0: no such file or directory`（只有 `/dev/dxg`）：
  請改用 WSL override：

```bash
podman-compose -f podman-compose.yml -f podman-compose.nvidia.wsl.yml up -d --build
```

驗證容器內是否可見 GPU：

```bash
podman-compose exec ai-server ollama ps
podman-compose exec ai-server sh -c 'ls -l /dev/dxg; ls -l /usr/lib/wsl/lib/libcuda.so.1'
```

> 前提：主機已安裝 NVIDIA Driver（`nvidia-smi` 正常）與對應 runtime/toolkit。  
> 若主機沒有 `/dev/nvidia0` 但有 `/dev/dxg`，代表你很可能在 WSL2，請使用 `podman-compose.nvidia.wsl.yml`。  
> 若 `ollama ps` 仍顯示 CPU，通常代表 Podman + WSL 的 GPU runtime 尚未完整接通（即使 `/dev/dxg` 可見）。此時建議改為：
> 1) 在 Windows/WSL 主機直接執行 Ollama（GPU）並讓 Spring Boot 連 `http://127.0.0.1:11434`，或  
> 2) 改用已驗證 GPU 直通較完整的 Docker Desktop + NVIDIA Container Toolkit。

#### Podman vs Docker（NVIDIA）
- **結論**：不是「Podman 完全不支援 NVIDIA」，而是 **Podman + WSL2** 目前在不同版本/安裝方式下，GPU 直通成功率與穩定性常比 Docker Desktop 低。
- 若你已確認 `nvidia-smi` 在主機正常，但 `podman-compose` 啟動後 Ollama 仍是 CPU，建議優先改用 Docker 測試，快速排除應用程式因素。

Docker 啟動（NVIDIA）：

```bash
docker compose -f podman-compose.yml -f docker-compose.nvidia.yml up -d --build
```

Docker 驗證 GPU：

```bash
docker compose exec ai-server ollama ps
docker run --rm --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi
```

若 Docker 可以吃到 GPU，而 Podman 不行，基本可判定是容器 runtime/WSL 整合問題，不是 Spring Boot 程式碼問題。

#### 一鍵啟動（WSL）
如果你想一次執行「關閉舊容器 → 啟動 ai-server/litellm → 等待 Ollama ready → 檢查 GPU 狀態」，可直接執行：

```bash
sh scripts/start-ai-wsl.sh
```

> 此腳本已支援 `/bin/sh`（例如 Ubuntu dash），不會再出現 `set: Illegal option -o pipefail`。

腳本會自動：
1. 檢查 `podman-compose` / `curl` 是否存在。
2. 優先使用 `podman-compose.nvidia.wsl.yml`（WSL `/dev/dxg` 路徑）。
3. 若主機缺少 `/dev/dxg`，自動嘗試 fallback 到 `podman-compose.nvidia.legacy.yml`。
4. 等待 `http://127.0.0.1:11434/api/tags` ready。
5. 印出容器內 GPU 相關檔案與 `ollama ps` 結果供比對。

`ai-server` 在啟動時會自動確保模型存在：
- `llama3`
- `mistral`

可用環境變數覆蓋：

```bash
export BOOTSTRAP_MODELS="llama3 mistral"
```

## 3) Spring Boot 對接設定

`application.yml`（或環境變數）設定：

```yaml
spring:
  ai:
    ollama:
      base-url: ${SPRING_AI_OLLAMA_BASE_URL:http://127.0.0.1:11434}

app:
  ai:
    gateway-api-key: ${AI_GATEWAY_API_KEY:dev-key}
    read-timeout: 90s
```

本機啟動 Spring Boot 前：

```bash
export SPRING_AI_OLLAMA_BASE_URL=http://127.0.0.1:11434
export AI_GATEWAY_API_KEY=dev-key
mvn spring-boot:run
```

## 4) 驗證 Gateway

```bash
curl http://localhost:4000/v1/models \
  -H "Authorization: Bearer dev-key"
```

## 5) 驗證 Spring API

```bash
curl -X POST http://localhost:8080/api/v1/analyze \
  -H "Content-Type: application/json" \
  -d '{"proposal":"請分析在 Kubernetes 上部署高可用支付系統"}'
```

若要繞過 `ChatClient`，直接用原生 Ollama `/api/chat` 流程驗證，可測試：

```bash
curl -X POST http://localhost:8080/api/v1/analyze-direct \
  -H "Content-Type: application/json" \
  -d '{"proposal":"請分析在 Kubernetes 上部署高可用支付系統"}'
```

若要再比對 Java 內建 `HttpClient` 呼叫方式（排除 `RestClient/ChatClient` 差異），可測試：

```bash
curl -X POST http://localhost:8080/api/v1/analyze-httpclient \
  -H "Content-Type: application/json" \
  -d '{"proposal":"請分析在 Kubernetes 上部署高可用支付系統"}'
```


## 6) 常見問題排除



### Q9: 我是 WSL2 + Podman 3.4.2，GPU 在 `docker run --gpus all` 正常，但 Podman 跑 Ollama 仍 CPU
這種組合很常見：
- `podman 3.4.x`（無 `podman compose` plugin）
- rootless Podman
- WSL2 `/dev/dxg`

在這個版本組合下，即使容器看得到 `/dev/dxg` 與 `libcuda.so.1`，Ollama 仍可能退回 CPU。
若你已確認以下命令成功：

```bash
docker run --rm --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi
```

可先判定「GPU 驅動正常、問題在 Podman+WSL runtime 整合」。建議：
1. 優先用 Docker 跑 Ollama（你目前環境最容易成功）。
2. 若要用 `docker compose`，需安裝 compose plugin（目前你的輸出顯示未安裝）。
3. 或升級 Podman 到較新版本並改走支援更完整的 GPU 路徑。

### Q1: `ai-server` 出現 `/entrypoint.sh: No such file or directory`
常見原因是 Windows/WSL 把 shell script 轉成 CRLF。現在 `infra/ai-server/Containerfile` 已在 build 時做 `sed -i 's/\r$//'`，並用 `sh /entrypoint.sh` 啟動，避免 shebang 解析失敗。

如果你之前建過舊 image，請強制重建：

```bash
podman-compose down
podman-compose build --no-cache ai-server
podman-compose up -d
```

### Q2: `curl /v1/models` 回 `{"error":{"message":"No connected db."...}}`
這通常是 LiteLLM 未讀到有效 `master_key` 設定。

本專案預設已在 `infra/litellm/config.yaml` 寫入 `master_key: dev-key`（開發用）。
請確認你是用最新檔案並重建 litellm：

```bash
podman-compose down
podman-compose up -d --build
```

驗證：

```bash
curl http://localhost:4000/v1/models -H "Authorization: Bearer dev-key"
```

### Q3: `litellm` logs 卡住沒輸出
`litellm` 可能在等待 `ai-server` ready 或沒有請求進來。可先檢查：

```bash
podman-compose ps
podman-compose logs --tail=200 ai-server
curl http://localhost:4000/v1/models -H "Authorization: Bearer dev-key"
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
