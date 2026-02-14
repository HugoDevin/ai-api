package com.example.aiapi.exception;

import java.time.Instant;
import java.util.Map;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.validation.FieldError;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

@RestControllerAdvice
public class GlobalExceptionHandler {

    @ExceptionHandler(AnalysisFailedException.class)
    public ResponseEntity<Map<String, Object>> handleAnalysisFailed(AnalysisFailedException ex) {
        return ResponseEntity.status(HttpStatus.BAD_GATEWAY).body(Map.of(
                "timestamp", Instant.now().toString(),
                "error", "AI_ANALYSIS_FAILED",
                "message", buildUserMessage(ex)
        ));
    }

    private String buildUserMessage(AnalysisFailedException ex) {
        Throwable root = ex;
        while (root.getCause() != null) {
            root = root.getCause();
        }

        String details = root.getMessage();
        if (details == null) {
            return ex.getMessage();
        }

        if (details.contains("Connection refused") || details.contains("getsockopt")) {
            return ex.getMessage() + "（連線被拒絕：請確認 Ollama 服務可達。若 Spring Boot 在容器內，請把 SPRING_AI_OLLAMA_BASE_URL 設為 http://ai-server:11434；若在主機執行則用 http://localhost:11434）";
        }
        return ex.getMessage();
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<Map<String, Object>> handleValidation(MethodArgumentNotValidException ex) {
        String message = ex.getBindingResult().getFieldErrors().stream()
                .findFirst()
                .map(FieldError::getDefaultMessage)
                .orElse("請求參數驗證失敗");
        return ResponseEntity.badRequest().body(Map.of(
                "timestamp", Instant.now().toString(),
                "error", "INVALID_REQUEST",
                "message", message
        ));
    }
}
