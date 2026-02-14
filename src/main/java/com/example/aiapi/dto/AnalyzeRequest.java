package com.example.aiapi.dto;

import jakarta.validation.constraints.NotBlank;

public record AnalyzeRequest(@NotBlank(message = "proposal 不可為空") String proposal) {
}
