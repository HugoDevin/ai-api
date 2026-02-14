package com.example.aiapi.service;

import com.example.aiapi.dto.AnalysisResult;
import com.example.aiapi.exception.AnalysisFailedException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.ai.chat.client.ChatClient;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.stereotype.Service;

@Service
public class MultiAgentAnalysisService {

    private static final Logger log = LoggerFactory.getLogger(MultiAgentAnalysisService.class);

    private final ChatClient architectChatClient;
    private final ChatClient securityChatClient;
    private final ChatClient moderatorChatClient;

    public MultiAgentAnalysisService(
            @Qualifier("architectChatClient") ChatClient architectChatClient,
            @Qualifier("securityChatClient") ChatClient securityChatClient,
            @Qualifier("moderatorChatClient") ChatClient moderatorChatClient) {
        this.architectChatClient = architectChatClient;
        this.securityChatClient = securityChatClient;
        this.moderatorChatClient = moderatorChatClient;
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
            throw new AnalysisFailedException("多代理分析失敗，請稍後再試。", ex);
        }
    }
}
