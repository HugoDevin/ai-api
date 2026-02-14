package com.example.aiapi.config;

import java.time.Duration;

import org.springframework.ai.chat.client.ChatClient;
import org.springframework.ai.chat.model.ChatModel;
import org.springframework.ai.ollama.api.OllamaOptions;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.client.JdkClientHttpRequestFactory;
import org.springframework.boot.web.client.RestClientCustomizer;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class AiClientConfig {

    @Bean
    public RestClientCustomizer ollamaGatewayCustomizer(
            @Value("${app.ai.gateway-api-key}") String apiKey,
            @Value("${app.ai.read-timeout:90s}") Duration readTimeout) {
        return restClientBuilder -> restClientBuilder
                .defaultHeader("Authorization", "Bearer " + apiKey)
                .defaultHeader("X-API-KEY", apiKey)
                .requestFactory(createRequestFactory(readTimeout));
    }

    private JdkClientHttpRequestFactory createRequestFactory(Duration readTimeout) {
        JdkClientHttpRequestFactory requestFactory = new JdkClientHttpRequestFactory();
        requestFactory.setReadTimeout(readTimeout);
        return requestFactory;
    }

    @Bean("architectChatClient")
    public ChatClient architectChatClient(ChatModel chatModel) {
        return ChatClient.builder(chatModel)
                .defaultOptions(OllamaOptions.builder().model("llama3").temperature(0.2).build())
                .defaultSystem("""
                        你是資深系統架構師，回答必須聚焦：
                        1) 高可用性（HA）
                        2) 可擴展性（Scalability）
                        3) 可觀測性與維運策略
                        請提供具體、可落地的設計建議。
                        """)
                .build();
    }

    @Bean("securityChatClient")
    public ChatClient securityChatClient(ChatModel chatModel) {
        return ChatClient.builder(chatModel)
                .defaultOptions(OllamaOptions.builder().model("mistral").temperature(0.1).build())
                .defaultSystem("""
                        你是資安專家，回答必須聚焦：
                        1) 威脅建模
                        2) 常見漏洞（OWASP Top 10）
                        3) 防禦與監控建議
                        請針對已提供的架構觀點進行風險評論。
                        """)
                .build();
    }

    @Bean("moderatorChatClient")
    public ChatClient moderatorChatClient(ChatModel chatModel) {
        return ChatClient.builder(chatModel)
                .defaultOptions(OllamaOptions.builder().model("llama3").temperature(0.2).build())
                .defaultSystem("""
                        你是中立主持人，請整合架構師與資安專家的重點，
                        輸出共識、分歧、與建議下一步。
                        """)
                .build();
    }
}
