# AI 開發測試基建（給 Spring Boot 使用）

你要的是「**獨立 AI 環境**」來給 Spring Boot 測試/開發，不是把 Spring Boot 打包進 Docker。

本專案現在提供的容器只包含：

- `ai-server`：Ollama（啟動時自動準備模型）
- `litellm`：Gateway（對外 API Key 驗證）

## 架構

Spring Boot (本機執行，spring-ai-ollama)
→ Ollama `http://localhost:11434`

LiteLLM `http://localhost:4000` 可獨立驗證模型列表與金鑰，但不是 Ollama `/api/chat` 端點。

## 1) 快速啟動 AI 基建

```bash
podman-compose up -d --build
```

啟動後：
- `ai-server`: `localhost:11434`
- `litellm`: `localhost:4000`

## 2) 模型準備

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
      base-url: ${SPRING_AI_OLLAMA_BASE_URL:http://localhost:11434}

app:
  ai:
    gateway-api-key: ${AI_GATEWAY_API_KEY:dev-key}
    read-timeout: 90s
```

本機啟動 Spring Boot 前：

```bash
export SPRING_AI_OLLAMA_BASE_URL=http://localhost:11434
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


## 6) 常見問題排除

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
export SPRING_AI_OLLAMA_BASE_URL=http://localhost:11434
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
