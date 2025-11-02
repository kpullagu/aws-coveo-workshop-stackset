# Architecture Diagrams

This page compiles all architecture diagrams from the workshop for quick reference.

## Overall Workshop Architecture

### Three Integration Patterns

```mermaid
graph TB
    subgraph "Pattern 1: Direct API"
        UI1[Search UI] --> Lambda1[Proxy Lambdas]
        Lambda1 --> Coveo1[Coveo APIs]
    end
    
    subgraph "Pattern 2: Bedrock Agent"
        UI2[Search UI] --> Agent[Bedrock Agent]
        Agent --> Tool[Passage Tool]
        Tool --> Coveo2[Coveo APIs]
    end
    
    subgraph "Pattern 3: AgentCore + MCP"
        UI3[Search UI] --> Runtime[AgentCore Runtime]
        Runtime --> MCP[MCP Server]
        MCP --> Coveo3[Coveo APIs]
    end
    
    style UI1 fill:#e8f5e9
    style UI2 fill:#fff3e0
    style UI3 fill:#f3e5f5
```

## Lab 1: Direct Coveo Integration

### High-Level Architecture

```mermaid
graph TB
    UI[Search UI] --> API[API Gateway]
    API --> L1[Search Lambda]
    API --> L2[Passages Lambda]
    API --> L3[Answer Lambda]
    
    L1 --> Coveo[Coveo Platform]
    L2 --> Coveo
    L3 --> Coveo
    
    style UI fill:#e1f5fe
    style Coveo fill:#e8f5e8
```

## Lab 2: Bedrock Agent + Coveo 

### Agent Architecture

```mermaid
graph TB
    UI[Search UI] --> Lambda[Agent Chat Lambda]
    Lambda --> Agent[Bedrock Agent]
    Agent --> Tool[Coveo Passage Tool Lambda]
    Tool --> Coveo[Coveo APIs]
    Agent --> Memory[Agent Memory]
    
    style Agent fill:#fff3e0
    style Memory fill:#f3e5f5
```

## Lab 3: AgentCore with Coveo MCP

### AgentCore Architecture

```mermaid
graph TB
    UI[Search UI] --> Runtime[AgentCore Runtime]
    Runtime --> MCP[Coveo MCP Server]
    MCP --> Search[search_coveo]
    MCP --> Passages[passage_retrieval]
    MCP --> Answer[answer_question]
    
    Search --> Coveo[Coveo APIs]
    Passages --> Coveo
    Answer --> Coveo
    
    Runtime --> Memory[AgentCore Memory]
    
    style Runtime fill:#f3e5f5
    style MCP fill:#fff3e0
```

## Lab 4: Chatbot Comparison

### Memory Comparison

```mermaid
graph TB
    subgraph "Coveo - No Memory"
        C1[Turn 1] -.-> C2[Turn 2]
        C2 -.-> C3[Turn 3]
    end
    
    subgraph "Bedrock Agent - Cross-Session Memory"
        B1[Session 1] --> BM[Cross-Session Memory<br/>Memory ID]
        B2[Session 2] --> BM
        B3[Session 3] --> BM
        BM --> B1
        BM --> B2
        BM --> B3
    end
    
    subgraph "Coveo MCP - Cross-Session Memory"
        M1[Session 1] --> CM[Cross-Session Memory<br/>Memory ID]
        M2[Session 2] --> CM
        M3[Session 3] --> CM
        CM --> M1
        CM --> M2
        CM --> M3
    end
    
    style C1 fill:#e8f5e9
    style B1 fill:#fff3e0
    style M1 fill:#f3e5f5
```

## Deployment Architecture

### AWS Infrastructure

```mermaid
graph TB
    subgraph "Frontend"
        AppRunner[App Runner<br/>Search UI]
    end
    
    subgraph "API Layer"
        API[API Gateway]
        Lambda1[Proxy Lambdas]
        Lambda2[Agent Chat Lambda]
        Lambda3[Tool Lambda]
    end
    
    subgraph "AI Services"
        Agent[Bedrock Agent]
        Runtime[AgentCore Runtime]
        MCP[MCP Server]
    end
    
    subgraph "External"
        Coveo[Coveo Platform]
    end
    
    AppRunner --> API
    API --> Lambda1
    API --> Lambda2
    Lambda2 --> Agent
    Lambda2 --> Runtime
    Agent --> Lambda3
    Runtime --> MCP
    
    Lambda1 --> Coveo
    Lambda3 --> Coveo
    MCP --> Coveo
    
    style AppRunner fill:#e1f5fe
    style Agent fill:#fff3e0
    style Runtime fill:#f3e5f5
```

---

For detailed diagrams specific to each lab, refer to the individual lab architecture pages.
