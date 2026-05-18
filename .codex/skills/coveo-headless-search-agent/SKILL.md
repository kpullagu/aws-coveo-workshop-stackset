---
name: coveo-headless-search-agent
description: Build or modify a Coveo Headless Search Agent UI using @coveo/headless buildSearchEngine, buildSearchBox, buildGeneratedAnswer with agentId, generated answer state, citations, and follow-up answers. Use when implementing a search-agent experience in aws-coveo-workshop-stackset or adapting the barca-help search-agent UI patterns without inventing undocumented Headless behavior.
---

# Coveo Headless Search Agent

Use this skill when implementing a Coveo Search Agent with Headless generated answers and follow-ups.

Before editing code, read [references/headless-search-agent.md](references/headless-search-agent.md). It contains the verified facts from:

- `https://github.com/mmitiche/Headless-search-agent-tutorial`
- Coveo Headless official docs linked by that tutorial
- local `D:\Projects\barca-help` implementation notes
- local `D:\Projects\robotics-new-ui` Headless implementation notes
- this repo's current frontend shape

## Implementation Workflow

1. Confirm the target UI layer.
   - In this repo, the Vite client lives under `frontend/client/src`.
   - The existing backend-driven chat path uses `/api/chat`; a Headless Search Agent should use client-side Headless controllers unless the user explicitly asks for a backend proxy.

2. Add Headless only where it is actually used.
   - Use `@coveo/headless`.
   - Pin the package version. Do not use `latest`.
   - Official docs currently state Headless requires Node.js 20; this repo declares Node `>=24.0.0`, which satisfies that runtime requirement.

3. Build the Headless engine from real Coveo config.
   - Required: `accessToken`, `organizationId`.
   - Usually required for workshop parity: `search.pipeline` and `search.searchHub`.
   - Add analytics config only from known project requirements; do not copy `analyticsdev` unless the environment is actually dev.

4. Create both controllers.
   - `buildSearchBox(engine)` owns query text and initial submission.
   - `buildGeneratedAnswer(engine, { agentId })` owns generated answer state and follow-up methods.
   - In TypeScript, `buildGeneratedAnswer` is typed as `GeneratedAnswer | GeneratedAnswerWithFollowUps`; narrow with `'askFollowUp' in generatedAnswer` before calling follow-up methods unless the local type setup proves a stronger type.

5. Subscribe and render from controller state.
   - Subscribe to both `searchBox` and `generatedAnswer`.
   - Always unsubscribe in React cleanup.
   - Render loading, error, `cannotAnswer`, answer text, citations, and `followUpAnswers.followUpAnswers`.

6. Preserve local UX lessons from `barca-help`.
   - Reuse the chat/thread layout idea: user message, assistant message, sources/citations, copy affordance, follow-up input.
   - Do not copy `barca-help` `/search-agent-coveo` network flow as Headless. That route streams custom `/api/chat` steps and is not the direct Headless generated-answer controller.

7. Preserve the verified `robotics-new-ui` Headless pattern when building a rich agent UI.
   - Use a hook/service layer for engine/controller lifecycle and a view component for conversation rendering.
   - Keep completed turns separate from the active pending turn.
   - Render a chained timeline: question row, answer body, citations, copy/feedback actions, then the follow-up input.
   - Collapse archived turns after follow-ups. Keep the latest turn expanded, and expose previous turns through expandable question rows.
   - Show thinking state from `isLoading`, `isStreaming`, and `generationSteps`; do not invent backend step names.

8. Verify with real behavior.
   - Initial query: enter text, submit through SearchBox, confirm answer state changes.
   - Follow-up: call `askFollowUp(question)` after an initial answer and confirm the latest item appears in `state.followUpAnswers.followUpAnswers`.
   - Error/no-answer: confirm `state.error` and `state.cannotAnswer` render useful UI.

## Do Not Invent

- Do not invent undocumented `GeneratedResponseFormat` fields. Only set `initialState.responseFormat` after checking the installed package typings or current official docs.
- Do not assume follow-up suggestions exist. The official state provides follow-up answer records; suggestions are separate from `barca-help` backend step data.
- Do not mix Atomic and Headless patterns in one component unless the user asks for Atomic. Atomic's `<AtomicGeneratedAnswer agentId="...">` is a valid reference point but not the Headless implementation.
- Do not claim `robotics-new-ui` renders like/dislike buttons. It renders copy and citation click logging; like/dislike are official Headless methods that should be added deliberately when requested.
