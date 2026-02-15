package com.example.aiapi.service;

import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.List;
import java.util.Map;

import com.example.aiapi.dto.AnalysisResult;
import com.example.aiapi.exception.AnalysisFailedException;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.ai.chat.client.ChatClient;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestClient;

@Service
public class MultiAgentAnalysisService {

    private static final Logger log = LoggerFactory.getLogger(MultiAgentAnalysisService.class);

    private final ChatClient architectChatClient;
    private final ChatClient securityChatClient;
    private final ChatClient moderatorChatClient;
    private final RestClient restClient;
    private final HttpClient httpClient;
    private final ObjectMapper objectMapper;
    private final Duration readTimeout;
    private final String ollamaBaseUrl;

    public MultiAgentAnalysisService(
            @Qualifier("architectChatClient") ChatClient architectChatClient,
            @Qualifier("securityChatClient") ChatClient securityChatClient,
            @Qualifier("moderatorChatClient") ChatClient moderatorChatClient,
            RestClient.Builder restClientBuilder,
            ObjectMapper objectMapper,
            @Value("${app.ai.read-timeout:90s}") Duration readTimeout,
            @Value("${spring.ai.ollama.base-url}") String ollamaBaseUrl) {
        this.architectChatClient = architectChatClient;
        this.securityChatClient = securityChatClient;
        this.moderatorChatClient = moderatorChatClient;
        this.restClient = restClientBuilder.baseUrl(ollamaBaseUrl).build();
        this.httpClient = HttpClient.newBuilder().connectTimeout(readTimeout).build();
        this.objectMapper = objectMapper;
        this.readTimeout = readTimeout;
        this.ollamaBaseUrl = ollamaBaseUrl;
    }

    private void logTroubleshootingHint(RuntimeException ex) {
        String message = ex.getMessage();
        if (message == null) {
            return;
        }

        if (message.contains("Connection refused") && ollamaBaseUrl.contains("localhost")) {
            log.error("[ai-analysis] hint: base-url={} 連線被拒絕。若在主機環境執行，請先改用 http://127.0.0.1:11434（避免 localhost 走 IPv6 ::1）；若在容器內請改用 http://ai-server:11434。",
                    ollamaBaseUrl);
        }
    }

    public AnalysisResult analyze(String topic) {
        try {
            String architectOpinion = architectChatClient.prompt()
                    .user(u -> u.text("請針對以下主題提出架構設計建議：{topic}").param("topic", topic))
                    .call()
                    .content();

            String securityReview = securityChatClient.prompt()
                    .user(u -> u.text("主題：{topic}\n\n架構師觀點：\n{architectOpinion}\n\n請提出資安風險與改進建議。")
                            .param("topic", topic)
                            .param("architectOpinion", architectOpinion))
                    .call()
                    .content();

            String moderatorSummary = moderatorChatClient.prompt()
                    .user(u -> u.text("""
                            主題：{topic}

                            架構師觀點：
                            {architectOpinion}

                            資安專家觀點：
                            {securityReview}

                            請輸出：
                            1. 共識
                            2. 主要分歧
                            3. 建議採取的下一步
                            """)
                            .param("topic", topic)
                            .param("architectOpinion", architectOpinion)
                            .param("securityReview", securityReview))
                    .call()
                    .content();

            return new AnalysisResult(topic, architectOpinion, securityReview, moderatorSummary);
        } catch (RuntimeException ex) {
            String errMsg = String.format("[ai-analysis] failed topic=%s root=%s message=%s",
                    topic, ex.getClass().getName(), ex.getMessage());
            log.error(errMsg, ex);
            logTroubleshootingHint(ex);
            throw new AnalysisFailedException("多代理分析失敗，請稍後再試。", ex);
        }
    }

    public AnalysisResult analyzeDirect(String topic) {
        try {
            String architectOpinion = callOllamaChat("llama3", "請針對以下主題提出架構設計建議：" + topic);
            String securityReview = callOllamaChat("mistral",
                    "主題：" + topic + "\n\n架構師觀點：\n" + architectOpinion + "\n\n請提出資安風險與改進建議。");
            String moderatorSummary = callOllamaChat("llama3",
                    "主題：" + topic + "\n\n架構師觀點：\n" + architectOpinion + "\n\n資安專家觀點：\n" + securityReview
                            + "\n\n請輸出：\n1. 共識\n2. 主要分歧\n3. 建議採取的下一步");

            return new AnalysisResult(topic, architectOpinion, securityReview, moderatorSummary);
        } catch (RuntimeException ex) {
            String errMsg = String.format("[ai-analysis-direct] failed topic=%s root=%s message=%s",
                    topic, ex.getClass().getName(), ex.getMessage());
            log.error(errMsg, ex);
            logTroubleshootingHint(ex);
            throw new AnalysisFailedException("直接呼叫 Ollama API 失敗，請稍後再試。", ex);
        }
    }

    public AnalysisResult analyzeViaHttpClient(String topic) {
        try {
            String architectOpinion = callOllamaChatWithHttpClient("llama3", "請針對以下主題提出架構設計建議：" + topic);
            String securityReview = callOllamaChatWithHttpClient("mistral",
                    "主題：" + topic + "\n\n架構師觀點：\n" + architectOpinion + "\n\n請提出資安風險與改進建議。");
            String moderatorSummary = callOllamaChatWithHttpClient("llama3",
                    "主題：" + topic + "\n\n架構師觀點：\n" + architectOpinion + "\n\n資安專家觀點：\n" + securityReview
                            + "\n\n請輸出：\n1. 共識\n2. 主要分歧\n3. 建議採取的下一步");
            return new AnalysisResult(topic, architectOpinion, securityReview, moderatorSummary);
        } catch (RuntimeException ex) {
            String errMsg = String.format("[ai-analysis-httpclient] failed topic=%s root=%s message=%s",
                    topic, ex.getClass().getName(), ex.getMessage());
            log.error(errMsg, ex);
            logTroubleshootingHint(ex);
            throw new AnalysisFailedException("使用 Java HttpClient 直接呼叫 Ollama API 失敗，請稍後再試。", ex);
        }
    }

    private String callOllamaChat(String model, String prompt) {
        Map<String, Object> response = restClient.post()
                .uri("/api/chat")
                .body(Map.of(
                        "model", model,
                        "stream", false,
                        "messages", List.of(Map.of("role", "user", "content", prompt))))
                .retrieve()
                .body(Map.class);

        return extractContent(response);
    }

    private String callOllamaChatWithHttpClient(String model, String prompt) {
        String requestBody;
        try {
            requestBody = objectMapper.writeValueAsString(Map.of(
                    "model", model,
                    "stream", false,
                    "messages", List.of(Map.of("role", "user", "content", prompt))));
        } catch (JsonProcessingException ex) {
            throw new IllegalStateException("組裝 Ollama 請求失敗", ex);
        }

        HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(ollamaBaseUrl + "/api/chat"))
                .timeout(readTimeout)
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(requestBody))
                .build();

        try {
            HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());
            if (response.statusCode() < 200 || response.statusCode() >= 300) {
                throw new IllegalStateException("Ollama HTTP 狀態異常: " + response.statusCode() + ", body=" + response.body());
            }
            Map<String, Object> json = objectMapper.readValue(response.body(), Map.class);
            return extractContent(json);
        } catch (IOException ex) {
            throw new IllegalStateException("呼叫 Ollama 失敗（I/O）", ex);
        } catch (InterruptedException ex) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("呼叫 Ollama 被中斷", ex);
        }
    }

    private String extractContent(Map<String, Object> response) {
        if (response == null) {
            throw new IllegalStateException("Ollama 回應為空");
        }

        Object messageObj = response.get("message");
        if (!(messageObj instanceof Map<?, ?> messageMap)) {
            throw new IllegalStateException("Ollama 回應缺少 message 欄位: " + response);
        }

        Object contentObj = messageMap.get("content");
        if (!(contentObj instanceof String content) || content.isBlank()) {
            throw new IllegalStateException("Ollama 回應缺少 content: " + response);
        }
        return content;
    }
}
