# Lab 4: Real-World Use Cases

This page explores real-world applications and use cases for each integration pattern.

## 💼 Use Case 1: FAQ Bot

**Best Backend**: Coveo Direct API (Lab 1)

### Scenario

A financial services company wants to provide instant answers to common customer questions on their website.

### Requirements

- ✅ Fast response times (<1 second)
- ✅ High volume of queries
- ✅ Simple question-answer format
- ✅ No conversation context needed

### Implementation

<div class="lab-card">
  <h4>Architecture</h4>
  <p><strong>Pattern</strong>: Direct Coveo API integration</p>
  <p><strong>Components</strong>: UI → API Gateway → Lambda → Coveo API</p>
  <p><strong>Response Time</strong>: ~200ms</p>
</div>

### Example Questions

<div class="query-example">
What is FDIC insurance?
</div>

<div class="query-example">
What are your business hours?
</div>

<div class="query-example">
How do I reset my password?
</div>

<div class="query-example">
What are current mortgage rates?
</div>

### Benefits

- ⚡ **Speed**: Sub-second responses
- 📈 **Scale**: Handles millions of queries
- 🔧 **Simple**: Easy to implement and maintain

### Metrics

| Metric | Target | Actual |
|--------|--------|--------|
| **Response Time** | <1s | ~200ms |
| **Accuracy** | >90% | ~95% |
| **Deflection Rate** | 30% | 35% |

---

## 💬 Use Case 2: Customer Support Chat

**Best Backend**: Bedrock Agent (Lab 2)

### Scenario

A bank wants to provide conversational support for customers with account questions and issues.

### Requirements

- ✅ Multi-turn conversations
- ✅ Context retention within session
- ✅ Natural language understanding
- ✅ Grounded responses with sources
- ✅ Reasonable response times (2-5s)

### Implementation

<div class="lab-card">
  <h4>Architecture</h4>
  <p><strong>Pattern</strong>: Bedrock Agent with Coveo tool</p>
  <p><strong>Components</strong>: UI → Lambda → Bedrock Agent → Tool → Coveo API</p>
  <p><strong>Response Time</strong>: ~2-3s</p>
</div>

### Example Conversation

**Turn 1**:
<div class="query-example">
I found errors in my credit report
</div>

**Turn 2**:
<div class="query-example">
How do I dispute them?
</div>

**Turn 3**:
<div class="query-example">
What's the timeline for resolution?
</div>

**Turn 4**:
<div class="query-example">
Can you create a checklist for me?
</div>

### Benefits

- 💬 **Conversational**: Natural multi-turn interactions
- 🧠 **Memory**: Maintains context within session
- 🎯 **Grounded**: Responses based on authoritative sources
- 📊 **Observable**: Traces show decision-making

### Metrics

| Metric | Target | Actual |
|--------|--------|--------|
| **Response Time** | <5s | ~2-3s |
| **Deflection Rate** | 40% | 45% |
| **User Satisfaction** | >4.0/5 | 4.3/5 |
| **Resolution Rate** | 60% | 65% |

---

## 🎓 Use Case 3: Financial Advisory

**Best Backend**: AgentCore + MCP (Lab 3)

### Scenario

A wealth management firm wants to provide personalized financial advice with long-term client relationships.

### Requirements

- ✅ Multi-turn conversations
- ✅ Cross-session memory
- ✅ Multiple tool orchestration
- ✅ Comprehensive analysis
- ✅ Long-term relationship building

### Implementation

<div class="lab-card">
  <h4>Architecture</h4>
  <p><strong>Pattern</strong>: AgentCore Runtime with MCP Server</p>
  <p><strong>Components</strong>: UI → Lambda → Agent Runtime → MCP Server → Multiple Tools → Coveo APIs</p>
  <p><strong>Response Time</strong>: ~3-5s</p>
</div>

### Example Multi-Session Journey

**Session 1: Initial Consultation**
```
Turn 1: "I want to plan for retirement"
Turn 2: "I'm 45 years old with $200k saved"
Turn 3: "I prefer moderate risk"
Turn 4: "What should I do?"
```

**Session 2: Follow-up (Next Week)**
```
Turn 1: "What did we discuss last time?"
Turn 2: "I've decided to be more aggressive"
Turn 3: "Show me updated recommendations"
```

**Session 3: Progress Review (Next Month)**
```
Turn 1: "How am I doing on my retirement plan?"
Turn 2: "Should I adjust anything?"
Turn 3: "What about tax implications?"
```

### Benefits

- 🔧 **Multi-Tool**: Comprehensive analysis using multiple tools
- 🧠 **Cross-Session**: Remembers across visits
- 📊 **Observable**: Detailed logs and traces
- 🎯 **Personalized**: Tailored to individual needs

### Metrics

| Metric | Target | Actual |
|--------|--------|--------|
| **Response Time** | <8s | ~3-5s |
| **Client Satisfaction** | >4.5/5 | 4.7/5 |
| **Engagement Rate** | 70% | 75% |
| **Retention Rate** | 80% | 85% |

---

## 📊 Use Case Comparison

### Quick Reference

| Use Case | Backend | Memory | Tools | Response Time | Best For |
|----------|---------|--------|-------|---------------|----------|
| **FAQ Bot** | Coveo | None | N/A | ~200ms | High volume, simple queries |
| **Support Chat** | Bedrock Agent | Cross-session | 1 | ~2-3s | Support conversations |
| **Advisory** | AgentCore MCP | Cross-session | 3+ | ~3-5s | Consultations, relationships |
| **Knowledge Portal** | Coveo | None | N/A | ~200ms | Search and discovery |
| **Troubleshooting** | Bedrock Agent | Cross-session | 1 | ~2-3s | Guided problem solving |
| **Research Assistant** | AgentCore MCP | Cross-session | 3+ | ~3-5s | Complex research |

---

## 🏢 Industry-Specific Use Cases

### Financial Services

<div class="lab-card">
  <h4>🏦 Retail Banking</h4>
  <p><strong>Backend</strong>: Bedrock Agent</p>
  <p><strong>Use Case</strong>: Account support, transaction inquiries, product information</p>
  <p><strong>Why</strong>: Multi-turn conversations with cross-session memory for ongoing support</p>
</div>

<div class="lab-card">
  <h4>💼 Wealth Management</h4>
  <p><strong>Backend</strong>: AgentCore + MCP</p>
  <p><strong>Use Case</strong>: Investment advisory, portfolio management, financial planning</p>
  <p><strong>Why</strong>: Cross-session memory for long-term client relationships</p>
</div>

<div class="lab-card">
  <h4>📚 Financial Education</h4>
  <p><strong>Backend</strong>: Coveo Direct</p>
  <p><strong>Use Case</strong>: Financial literacy content, educational resources</p>
  <p><strong>Why</strong>: Fast access to educational content without conversation needs</p>
</div>

---

### Healthcare

<div class="lab-card">
  <h4>🏥 Patient Portal</h4>
  <p><strong>Backend</strong>: Coveo Direct</p>
  <p><strong>Use Case</strong>: Medical information lookup, appointment scheduling</p>
  <p><strong>Why</strong>: Quick access to information without complex conversations</p>
</div>

<div class="lab-card">
  <h4>💊 Symptom Checker</h4>
  <p><strong>Backend</strong>: Bedrock Agent</p>
  <p><strong>Use Case</strong>: Interactive symptom assessment with follow-up questions</p>
  <p><strong>Why</strong>: Multi-turn conversation for comprehensive assessment</p>
</div>

---

### E-Commerce

<div class="lab-card">
  <h4>🛍️ Product Search</h4>
  <p><strong>Backend</strong>: Coveo Direct</p>
  <p><strong>Use Case</strong>: Product discovery, filtering, recommendations</p>
  <p><strong>Why</strong>: Fast search with faceted navigation</p>
</div>

<div class="lab-card">
  <h4>🤝 Shopping Assistant</h4>
  <p><strong>Backend</strong>: Bedrock Agent</p>
  <p><strong>Use Case</strong>: Guided shopping, product comparisons, recommendations</p>
  <p><strong>Why</strong>: Conversational product discovery with context</p>
</div>

<div class="lab-card">
  <h4>👤 Personal Shopper</h4>
  <p><strong>Backend</strong>: AgentCore + MCP</p>
  <p><strong>Use Case</strong>: Long-term style preferences, seasonal recommendations</p>
  <p><strong>Why</strong>: Cross-session memory for personalized experience</p>
</div>

---

## 💡 Implementation Considerations

### Performance Considerations

| Backend | Latency | Throughput | Scalability |
|---------|---------|------------|-------------|
| **Coveo** | Lowest | Highest | Excellent |
| **Bedrock Agent** | Medium | High | Very Good |
| **AgentCore MCP** | Higher | Medium | Good |

### Complexity Considerations

| Backend | Setup | Maintenance | Extensibility |
|---------|-------|-------------|---------------|
| **Coveo** | Simple | Easy | Limited |
| **Bedrock Agent** | Moderate | Moderate | Good |
| **AgentCore MCP** | Complex | Moderate | Excellent |

---

## 🚀 Getting Started with Your Use Case

### Step 1: Identify Requirements

Ask yourself:

- Do users need multi-turn conversations?
- Is cross-session memory valuable?
- How complex are the queries?
- What's the expected volume?

### Step 2: Choose Backend

Use the decision framework:

- **Simple FAQ** → Coveo Direct
- **Support Chat** → Bedrock Agent
- **Consultation** → AgentCore + MCP

### Step 3: Prototype

Start with the workshop code:

- Clone the repository
- Configure with your Coveo organization
- Deploy to AWS
- Test with your content

### Step 4: Optimize

Based on testing:

- Adjust memory settings
- Tune system prompts
- Add custom tools

---

## 📈 Case Deflection Value

**Example Metrics**:

- Deflection rate: 40%
- Monthly support volume: 10,000 tickets
- Deflected tickets: 4,000 per month

### Implementation Timeline

| Phase | Coveo Direct API | Coveo with Bedrock Agent | Bedrock AgentCore with Coveo MCP |
|-------|------------------|--------------------------|----------------------------------|
| **Setup** | 1 week | 2 weeks | 3 weeks |
| **Maintenance** | Low | Medium | Medium |

---

## 💡 Best Practices by Use Case

### For FAQ Bots (Coveo Direct)

1. **Optimize for Speed**: Cache common queries
2. **Rich Content**: Ensure comprehensive knowledge base
3. **Clear Sources**: Always show authoritative citations
4. **Fallback**: Provide escalation path to human support

### For Support Chat (Bedrock Agent)

1. **Clear Instructions**: Well-defined system prompts
2. **Memory Management**: Appropriate session timeouts
3. **Tool Design**: Single, focused tool for grounding
4. **Escalation**: Know when to transfer to human

### For Advisory (AgentCore + MCP)

1. **Multiple Tools**: Provide diverse capabilities
2. **Cross-Session Memory**: Enable long-term relationships
3. **Observability**: Monitor tool usage and performance
4. **Personalization**: Leverage memory for tailored advice

---

## 🎯 Next Steps for Your Implementation

### 1. Define Your Use Case

- What problem are you solving?
- Who are your users?
- What's the expected volume?
- What's your budget?

### 2. Choose Your Backend

- Use the decision framework
- Consider your requirements
- Evaluate trade-offs
- Start with simplest solution

### 3. Prototype

- Use workshop code as starting point
- Configure with your content
- Test with real users
- Gather feedback

### 4. Iterate

- Optimize based on usage
- Add features as needed
- Monitor performance
- Improve continuously

---

## 📚 Additional Resources

### Coveo Resources

- [Coveo Platform Overview](https://docs.coveo.com/)
- [API Documentation](https://docs.coveo.com/en/13/api-reference/search-api)
- [Best Practices](https://docs.coveo.com/en/1461/)

### Workshop Resources

- [Architecture Diagrams](../resources/diagrams.md)
- [Code Repository](../resources/code.md)
- [Additional Reading](../resources/reading.md)

### AWS Resources

- [Bedrock Agents Best Practices](https://docs.aws.amazon.com/bedrock/latest/userguide/agents-best-practices.html)
- [AgentCore Documentation](https://docs.aws.amazon.com/bedrock/latest/userguide/agentcore.html)
- [Cost Optimization Guide](https://aws.amazon.com/bedrock/pricing/)



---

## 🎉 Workshop Complete!

Congratulations on completing all 4 labs! You now have:

- ✅ Hands-on experience with three integration patterns
- ✅ Understanding of when to use each approach
- ✅ Knowledge of memory and conversation capabilities
- ✅ Real-world use case examples
- ✅ Implementation guidance for your own projects

<div style="background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 2rem; border-radius: 8px; text-align: center; margin: 2rem 0;">
  <h3 style="color: white; margin-top: 0;">Ready to Build Your Solution?</h3>
  <p style="font-size: 1.1rem;">Use the workshop code as your starting point</p>
  <p>Questions? Contact your instructor or explore the resources section.</p>
</div>

---

## 📞 Support and Next Steps

### Get Help

- **Workshop Questions**: Ask your instructor
- **Technical Issues**: Check troubleshooting guides
- **Implementation Help**: Contact Coveo or AWS support

### Continue Learning

- Explore the code repository
- Review architecture diagrams
- Read additional documentation
- Join community forums

### Stay Connected

- Subscribe to Coveo blog
- Join user communities
- Attend future workshops

---

Thank you for participating in the Coveo + AWS Bedrock Workshop!
