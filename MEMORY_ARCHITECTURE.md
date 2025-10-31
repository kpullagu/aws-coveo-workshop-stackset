# Memory Architecture: Bedrock Agent vs AgentCore Runtime

## Overview

This document explains how conversational memory works in the workshop for both Bedrock Agent and AgentCore Runtime backends, including session management, cross-session memory, and the "End Chat & Save Memory" feature.

---

## Memory Configuration Comparison

| Aspect | Bedrock Agent | AgentCore Runtime |
|--------|---------------|-------------------|
| **Session Memory** | ✅ Session ID | ✅ Session ID |
| **Cross-Session Memory** | ✅ Memory ID (from Cognito `sub`) | ✅ Actor ID (from Cognito `sub`) |
| **Memory Storage** | AWS Bedrock Agent Memory | AgentCore Memory Service |
| **Memory Namespace** | `/memories/{memoryId}` | `/summaries/{actorId}/{sessionId}` |
| **Memory Duration** | 7 days (configurable) | 7 days (configurable) |
| **Memory Strategy** | Built-in summarization | Built-in summarization |

---

## Key Concepts

### 1. **Session ID**
- **Purpose**: Tracks a single conversation session
- **Scope**: Within-session continuity (same browser tab, no logout)
- **Lifecycle**: 
  - Created when chat starts
  - Persists in `localStorage` across page refreshes
  - Changes when "End Chat & Save Memory" is clicked
  - Changes when user logs out and logs back in
- **Storage**: 
  - Bedrock Agent: `localStorage.bedrock_session_id`
  - AgentCore: `localStorage.coveo_mcp_session_id`

### 2. **Memory ID (Bedrock Agent)**
- **Purpose**: Identifies the user across multiple sessions
- **Source**: Cognito JWT token `sub` claim (hashed)
- **Scope**: Cross-session memory (survives logout/login)
- **Priority**:
  1. Explicit `memoryId` from request body
  2. Cognito `sub` from JWT (most stable) ← **Used in workshop**
  3. Cognito `email` from JWT
  4. Fallback to "anonymous"
- **Hashing**: SHA-256 hash to normalize length and avoid PII leakage

### 3. **Actor ID (AgentCore Runtime)**
- **Purpose**: Identifies the user across multiple sessions (same as Memory ID)
- **Source**: Cognito JWT token `sub` claim
- **Scope**: Cross-session memory (survives logout/login)
- **Priority**:
  1. Cognito `sub` from JWT ← **Used in workshop**
  2. `userId` or `user_id` from request body
  3. Fallback to "anonymous"
- **No Hashing**: Uses raw Cognito `sub` value

---

## Memory Hierarchy

```
User (Cognito Identity)
├── Memory ID / Actor ID (Stable across all sessions)
│   ├── Session 1 (Monday morning)
│   │   ├── Turn 1: "What is a 401k?"
│   │   ├── Turn 2: "What are the contribution limits?"
│   │   └── Turn 3: "How do I increase my contribution?"
│   │
│   ├── Session 2 (Monday afternoon - after "End Chat")
│   │   ├── Turn 1: "What did we discuss earlier?" ← Recalls Session 1
│   │   └── Turn 2: "Tell me about Roth IRA"
│   │
│   └── Session 3 (Tuesday - after logout/login)
│       └── Turn 1: "What did we discuss yesterday?" ← Recalls Sessions 1 & 2
```

---

## How Memory Works

### **Same Session Memory** (Within a conversation)

**Scenario**: User asks multiple questions without closing chat or logging out

```javascript
// Frontend
sessionId: "abc-123" (stored in localStorage)

// Backend
Turn 1: "What is FDIC insurance?"
  → Agent uses sessionId="abc-123"
  → Stores conversation in memory

Turn 2: "How much does it cover?"
  → Agent uses SAME sessionId="abc-123"
  → Retrieves previous context
  → Understands "it" refers to FDIC insurance
```

**Key Points**:
- Session ID stays the same
- Memory ID/Actor ID stays the same
- Agent has full context of the conversation
- Works even after page refresh (sessionId in localStorage)

---

### **Cross-Session Memory** (After "End Chat & Save Memory")

**Scenario**: User clicks "End Chat & Save Memory" button

```javascript
// Frontend Action
1. Sends endSession=true to backend
2. Backend finalizes and summarizes the session
3. Frontend generates NEW sessionId
4. Updates localStorage with new sessionId

// Backend (Bedrock Agent)
{
  sessionId: "abc-123",      // Current session
  memoryId: "user-hash-xyz", // Same user
  endSession: true           // Finalize this session
}
→ Agent summarizes Session 1 and stores in memory

// Backend (AgentCore)
{
  session_id: "abc-123",     // Current session
  actor_id: "cognito-sub-xyz", // Same user
  end_session: true          // Finalize this session
}
→ AgentCore summarizes Session 1 and stores in memory

// Next Message (New Session)
{
  sessionId: "def-456",      // NEW session ID
  memoryId: "user-hash-xyz"  // SAME memory ID
}
→ Agent can recall summarized Session 1
```

**Key Points**:
- Session ID **changes** (new conversation)
- Memory ID/Actor ID **stays the same** (same user)
- Previous session is summarized and stored
- New session can recall previous sessions via Memory ID/Actor ID

---

### **Logout and Login Memory** (Cross-login sessions)

**Scenario**: User logs out and logs back in

```javascript
// Before Logout
sessionId: "abc-123"
memoryId: "user-hash-xyz" (from Cognito sub)

// User Logs Out
→ Frontend clears auth tokens (auth_token, access_token)
→ Frontend clears session IDs (bedrock_session_id, coveo_mcp_session_id)
→ All localStorage session data removed for security

// User Logs Back In
→ Frontend generates NEW sessionId: "ghi-789"
→ Backend extracts SAME memoryId: "user-hash-xyz" (from JWT)

// First Message After Login
{
  sessionId: "ghi-789",      // NEW session ID
  memoryId: "user-hash-xyz"  // SAME memory ID (from JWT)
}
→ Agent recalls ALL previous sessions for this user
```

**Key Points**:
- Session ID **changes** (new login = new session)
- Session IDs **cleared from localStorage** on logout (security)
- Memory ID/Actor ID **stays the same** (same Cognito user)
- Agent can recall conversations from before logout
- Memory persists across logins for 7 days

**Logout Implementation** (AuthProvider.js):
```javascript
const logout = () => {
  // Clear authentication tokens
  localStorage.removeItem('auth_token');
  localStorage.removeItem('access_token');
  
  // Clear session IDs for security (prevent session reuse)
  localStorage.removeItem('bedrock_session_id');
  localStorage.removeItem('coveo_mcp_session_id');
  
  setToken(null);
  setUser(null);
  
  // Redirect to Cognito logout
  window.location.href = logoutUrl;
};
```

**Security Benefits**:
- ✅ Session IDs cleared on logout
- ✅ New session IDs generated on next login
- ✅ Prevents session reuse on shared computers
- ✅ Maintains proper session isolation between users
- ✅ Cross-session memory still works via Memory ID/Actor ID (from JWT)

---

## "End Chat & Save Memory" Feature

### Purpose
Allows users to explicitly end a conversation and start fresh while preserving the ability to recall previous conversations.

### Behavior Comparison

| Aspect | Bedrock Agent | AgentCore Runtime |
|--------|---------------|-------------------|
| **Button Click** | Sends `endSession=true` | Sends `end_session=true` |
| **Backend Action** | Finalizes session, summarizes conversation | Finalizes session, summarizes conversation |
| **Session ID** | Changes (new UUID generated) | Changes (new UUID generated) |
| **Memory ID/Actor ID** | Stays the same | Stays the same |
| **Memory Storage** | Stored in Bedrock Agent Memory | Stored in AgentCore Memory |
| **Recall Ability** | Can recall via "What did we discuss?" | Can recall via "What did we discuss?" |

### Implementation

#### Frontend (ChatBot.js)
```javascript
const handleEndSession = async () => {
  // Send endSession=true to backend
  await chatAPI(
    "End session",
    currentSessionId,
    backendMode,
    null,
    true  // endSession = true
  );
  
  // Generate new session ID
  const newSessionId = uuidv4();
  setCurrentSessionId(newSessionId);
  
  // Update localStorage
  onSessionEnd(newSessionId);
};
```

#### Backend (Bedrock Agent)
```python
invoke_params = {
    'agentId': agent_id,
    'agentAliasId': alias_id,
    'sessionId': session_id,      # Current session
    'inputText': question,
    'memoryId': memory_id,         # User identity
    'endSession': end_session      # True = finalize
}
```

#### Backend (AgentCore)
```python
payload = {
    "text": prompt,
    "session_id": session_id,      # Current session
    "actor_id": actor_id,          # User identity
    "end_session": end_session     # True = finalize
}
```

---

## Session ID Creation Timeline

### Bedrock Agent

| Event | Session ID | Memory ID | Memory Access |
|-------|-----------|-----------|---------------|
| **First chat message** | Generated (stored in localStorage) | From JWT | No previous memory |
| **Page refresh** | Same (from localStorage) | From JWT | Same session continues |
| **"End Chat" clicked** | NEW (generated) | Same (from JWT) | Can recall previous session |
| **User logs out** | Cleared | N/A | N/A |
| **User logs back in** | NEW (generated) | Same (from JWT) | Can recall all previous sessions |

### AgentCore Runtime

| Event | Session ID | Actor ID | Memory Access |
|-------|-----------|----------|---------------|
| **First chat message** | Generated (stored in localStorage) | From JWT | No previous memory |
| **Page refresh** | Same (from localStorage) | From JWT | Same session continues |
| **"End Chat" clicked** | NEW (generated) | Same (from JWT) | Can recall previous session |
| **User logs out** | Cleared | N/A | N/A |
| **User logs back in** | NEW (generated) | Same (from JWT) | Can recall all previous sessions |

---

## Memory Persistence

### Bedrock Agent Memory
```
Storage Location: AWS Bedrock Agent Memory Service
Namespace: /memories/{memoryId}
Duration: 7 days (configurable in console)
Strategy: Automatic summarization
Access: Via memoryId (Cognito sub hash)
```

### AgentCore Memory
```
Storage Location: AgentCore Memory Service
Namespace: /summaries/{actorId}/{sessionId}
Duration: 7 days (configurable in template)
Strategy: Automatic summarization
Access: Via actor_id (Cognito sub)
```

---

## Key Differences: Memory ID vs Actor ID

| Aspect | Memory ID (Bedrock Agent) | Actor ID (AgentCore) |
|--------|---------------------------|----------------------|
| **Source** | Cognito JWT `sub` claim | Cognito JWT `sub` claim |
| **Hashing** | ✅ SHA-256 hashed | ❌ Raw value |
| **Purpose** | User identification | User identification |
| **Scope** | Cross-session | Cross-session |
| **PII Protection** | Yes (hashed) | No (raw sub) |
| **Length** | 64 chars (hash) | Variable (Cognito sub) |

---

## Example Conversation Flow

### Scenario: User has 3 conversations over 2 days

#### **Day 1, Morning (Session 1)**
```
User: "What is a 401k?"
Agent: [Retrieves passages, explains 401k]
  sessionId: "aaa-111"
  memoryId: "hash-xyz"

User: "What are the contribution limits?"
Agent: [Recalls previous context about 401k]
  sessionId: "aaa-111" (SAME)
  memoryId: "hash-xyz" (SAME)
```

#### **Day 1, Afternoon (User clicks "End Chat")**
```
Backend: Finalizes session "aaa-111", stores summary
Frontend: Generates new sessionId "bbb-222"

User: "What did we discuss earlier?"
Agent: "Earlier today, you asked about 401k retirement accounts..."
  sessionId: "bbb-222" (NEW)
  memoryId: "hash-xyz" (SAME)
  → Recalls Session 1 via memoryId
```

#### **Day 2 (User logs out, logs back in)**
```
Frontend: Generates new sessionId "ccc-333"
Backend: Extracts memoryId "hash-xyz" from JWT

User: "What did we discuss yesterday?"
Agent: "Yesterday, we discussed 401k accounts and contribution limits..."
  sessionId: "ccc-333" (NEW)
  memoryId: "hash-xyz" (SAME)
  → Recalls Sessions 1 & 2 via memoryId
```

---

## Summary

### **Session ID**
- Tracks a single conversation
- Changes on "End Chat" or logout
- Stored in localStorage (survives page refresh)
- Unique per conversation

### **Memory ID / Actor ID**
- Identifies the user across all sessions
- Derived from Cognito JWT `sub` claim
- Never changes for the same user
- Enables cross-session memory

### **"End Chat & Save Memory"**
- Finalizes current session
- Generates new session ID
- Preserves memory via Memory ID/Actor ID
- Allows starting fresh while retaining history

### **Logout/Login**
- Session ID changes (new session)
- Memory ID/Actor ID stays the same (same user)
- All previous conversations remain accessible
- Memory persists for 7 days

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                         Frontend                            │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ localStorage                                         │   │
│  │  - bedrock_session_id: "abc-123"                    │   │
│  │  - coveo_mcp_session_id: "def-456"                  │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                            │
                            │ JWT Token (contains Cognito sub)
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                    Backend Lambda                           │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ Extract from JWT:                                    │   │
│  │  - Cognito sub → memoryId (hashed) / actor_id       │   │
│  │                                                      │   │
│  │ From Request:                                        │   │
│  │  - sessionId (from localStorage)                    │   │
│  │  - endSession flag                                  │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│              Bedrock Agent / AgentCore                      │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ Memory Lookup:                                       │   │
│  │  - Current session: sessionId                        │   │
│  │  - Previous sessions: memoryId / actor_id           │   │
│  │                                                      │   │
│  │ If endSession=true:                                  │   │
│  │  - Summarize current session                        │   │
│  │  - Store in memory                                  │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

---

**Built with ❤️ for AWS and Coveo workshops**
