package com.example.aiapi.exception;

public class AnalysisFailedException extends RuntimeException {

    public AnalysisFailedException(String message, Throwable cause) {
        super(message, cause);
    }
}
