package com.example.aiapi.dto;

public record AnalysisResult(
        String topic,
        String architectOpinion,
        String securityReview,
        String moderatorSummary
) {
}
