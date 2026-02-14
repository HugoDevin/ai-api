package com.example.aiapi.controller;

import com.example.aiapi.dto.AnalyzeRequest;
import com.example.aiapi.dto.AnalysisResult;
import com.example.aiapi.service.MultiAgentAnalysisService;
import jakarta.validation.Valid;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1")
public class AnalysisController {

    private final MultiAgentAnalysisService analysisService;

    public AnalysisController(MultiAgentAnalysisService analysisService) {
        this.analysisService = analysisService;
    }

    @PostMapping("/analyze")
    public ResponseEntity<AnalysisResult> analyze(@Valid @RequestBody AnalyzeRequest request) {
        AnalysisResult result = analysisService.analyze(request.proposal());
        return ResponseEntity.ok(result);
    }
}
