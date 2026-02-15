FROM ollama/ollama:latest

# 預設需要的模型，啟動時會自動檢查/下載。
ENV BOOTSTRAP_MODELS="llama3 mistral"

COPY infra/ai-server/entrypoint.sh /entrypoint.sh
# WSL/Windows 可能帶入 CRLF，轉為 LF 避免 "No such file or directory" 啟動錯誤。
RUN sed -i 's/\r$//' /entrypoint.sh && chmod +x /entrypoint.sh

EXPOSE 11434
ENTRYPOINT ["sh", "/entrypoint.sh"]
