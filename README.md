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
export AI_GATEWAY_API_KEY=dev-key
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
