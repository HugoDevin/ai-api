# AI 開發測試基建（給 Spring Boot 使用）

你要的是「**獨立 AI 環境**」來給 Spring Boot 測試/開發，不是把 Spring Boot 打包進 Docker。

本專案現在提供的容器只包含：

- `ai-server`：Ollama（啟動時自動準備模型）
- `litellm`：Gateway（對外 API Key 驗證）

## 架構

Spring Boot (本機執行)
→ LiteLLM `http://localhost:4000`
→ Ollama `ai-server:11434`

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
export OLLAMA_MODELS="llama3 mistral"
```

## 3) Spring Boot 對接設定

`application.yml`（或環境變數）設定：

```yaml
spring:
  ai:
    ollama:
      base-url: ${SPRING_AI_OLLAMA_BASE_URL:http://localhost:4000}

app:
  ai:
    gateway-api-key: ${AI_GATEWAY_API_KEY:dev-key}
    read-timeout: 90s
```

本機啟動 Spring Boot 前：

```bash
export SPRING_AI_OLLAMA_BASE_URL=http://localhost:4000
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
先看 `ai-server` 啟動 log：

```bash
podman-compose logs --tail=200 ai-server
```

若看到 `configured models` 顯示成 `${OLLAMA_MODELS...}` 這類未展開字串，代表 compose 在你的環境沒有正確套用預設值。
新版 entrypoint 會自動回退到 `llama3 mistral`，請重建並重啟：

```bash
podman-compose down
podman-compose build --no-cache ai-server
podman-compose up -d
```

模型首次下載需要時間，下載完成前 `ollama list` 可能暫時為空。
