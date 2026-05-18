# Coveo Headless Search Agent Reference

Source date: gathered May 8, 2026.

## Source Tutorial

Repository: `https://github.com/mmitiche/Headless-search-agent-tutorial`

Files in repo:

- `README.md`
- `app.js`
- `index.html`

The tutorial implementation is a small static HTML/JS demo. `app.js` imports these from Coveo's Headless ESM CDN:

```js
import {
  buildGeneratedAnswer,
  buildSearchBox,
  buildSearchEngine,
} from 'https://static.cloud.coveo.com/headless/v3/headless.esm.js';
```

It configures a Search engine with:

```js
buildSearchEngine({
  configuration: {
    accessToken: 'YOUR_API_KEY_HERE',
    environment: 'dev | prod',
    organizationId: 'YOUR_ORGANIZATION_ID_HERE',
    search: {
      pipeline: 'YOUR_PIPELINE_HERE',
      searchHub: 'YOUR_SEARCH_HUB_HERE',
    },
    analytics: {
      apiBaseUrl: 'https://analyticsdev.cloud.coveo.com/analytics/v1/',
      analyticsMode: 'legacy',
    },
  },
});
```

Then it creates:

```js
const searchBox = buildSearchBox(engine);
const generatedAnswer = buildGeneratedAnswer(engine, {
  agentId,
});
```

Important tutorial behavior:

- The initial query goes through `searchBox.updateText(...)` and `searchBox.submit()`.
- UI updates come from `searchBox.subscribe(render)` and `generatedAnswer.subscribe(render)`.
- Status checks use `generatedAnswer.state.isLoading`, `state.error`, `state.cannotAnswer`, and `state.answer`.
- Follow-ups are submitted with `generatedAnswer.askFollowUp(followUpQuestion)`.
- The latest follow-up answer is read from:

```js
const followUpAnswers = answerState.followUpAnswers?.followUpAnswers || [];
const latestFollowUpAnswer = followUpAnswers[followUpAnswers.length - 1];
```

## Official Docs Facts

Headless usage overview:
`https://docs.coveo.com/en/headless/latest/reference/documents/usage/index.html`

- Headless has two main building blocks: the engine, which manages state and communicates with Coveo Platform, and controllers, which dispatch actions from UI interactions.
- For Search, use `buildSearchEngine` from `@coveo/headless`.
- Official docs currently show install version `@coveo/headless@3.50.1` and recommend pinning the dependency.
- Official docs currently state Headless requires Node.js 20.
- Controller builders take the engine as the first argument.
- Controller `subscribe(listener)` returns an unsubscribe function.

Search module reference:
`https://docs.coveo.com/en/headless/latest/reference/modules/Search.html`

- Search exports engine, controllers, actions, and utilities for a search experience.
- The GeneratedAnswer controller group includes:
  - `GeneratedAnswer`
  - `GeneratedAnswerState`
  - `GeneratedAnswerWithFollowUps`
  - `GeneratedAnswerWithFollowUpsState`
  - `buildGeneratedAnswer`

`buildGeneratedAnswer`:
`https://docs.coveo.com/en/headless/latest/reference/functions/Search.buildGeneratedAnswer.html`

Signature:

```ts
buildGeneratedAnswer(
  engine: SearchEngine,
  props?: GeneratedAnswerProps
): GeneratedAnswer | GeneratedAnswerWithFollowUps
```

It creates a GeneratedAnswer controller instance.

`GeneratedAnswerProps`:
`https://docs.coveo.com/en/headless/latest/reference/interfaces/Search.GeneratedAnswerProps.html`

Documented props:

```ts
interface GeneratedAnswerProps {
  agentId?: string;
  answerConfigurationId?: string;
  fieldsToIncludeInCitations?: string[];
  initialState?: {
    expanded?: boolean;
    isEnabled?: boolean;
    isVisible?: boolean;
    responseFormat?: GeneratedResponseFormat;
  };
}
```

Documented meanings:

- `agentId`: identifies the agent used for generating the answer.
- `answerConfigurationId`: answer configuration ID for Coveo answer management.
- `fieldsToIncludeInCitations`: indexed fields to include in returned citations.
- `initialState.expanded`: initial expanded state.
- `initialState.isEnabled`: enabled state on load.
- `initialState.isVisible`: visibility state on load.
- `initialState.responseFormat`: initial formatting options.

`GeneratedAnswerWithFollowUps`:
`https://docs.coveo.com/en/headless/latest/reference/interfaces/Search.GeneratedAnswerWithFollowUps.html`

Documented shape and methods:

```ts
interface GeneratedAnswerWithFollowUps {
  state: GeneratedAnswerWithFollowUpsState;
  askFollowUp(question: string): void;
  closeFeedbackModal(): void;
  collapse(): void;
  disable(): void;
  dislike(answerId?: string): void;
  enable(): void;
  expand(): void;
  hide(): void;
  like(answerId?: string): void;
  logCitationClick(citationId: string, answerId?: string): void;
  logCitationHover(citationId: string, citationHoverTimeMs: number, answerId?: string): void;
  logCopyToClipboard(answerId?: string): void;
  openFeedbackModal(): void;
  retry(): void;
  sendFeedback(feedback: GeneratedAnswerFeedback): void;
  show(): void;
  subscribe(listener: () => void): Unsubscribe;
}
```

Notes:

- `askFollowUp(question)` asks a follow-up question.
- Citation click, hover, copy, like, and dislike methods accept an optional `answerId`; docs say the optional answer ID defaults to the first answer.

`GeneratedAnswerWithFollowUpsState`:
`https://docs.coveo.com/en/headless/latest/reference/interfaces/Search.GeneratedAnswerWithFollowUpsState.html`

Documented fields include:

```ts
answer?: string;
answerApiQueryParams?: AnswerApiQueryParams;
answerConfigurationId?: string;
answerContentFormat?: "text/plain" | "text/markdown";
answerGenerationMode: "automatic" | "manual";
answerId?: string;
cannotAnswer: boolean;
citations: GeneratedAnswerCitation[];
disliked: boolean;
error?: {
  code?: number;
  isRetryable?: boolean;
  message?: string;
  isConversationNotFoundError?(): boolean;
  isFollowupNotSupportedError?(): boolean;
  isMaxDurationExceededError?(): boolean;
  isSseInternalError?(): boolean;
  isSseModelNotAvailableError?(): boolean;
  isSseTurnLimitReachedError?(): boolean;
};
expanded: boolean;
feedbackModalOpen: boolean;
feedbackSubmitted: boolean;
fieldsToIncludeInCitations: string[];
followUpAnswers: FollowUpAnswersState;
generationSteps: GenerationStep[];
id: string;
isAnswerGenerated: boolean;
isEnabled: boolean;
isLoading: boolean;
isStreaming: boolean;
isVisible: boolean;
liked: boolean;
responseFormat: GeneratedResponseFormat;
```

`GeneratedAnswerCitation`:
`https://docs.coveo.com/en/headless/latest/reference/interfaces/Search.GeneratedAnswerCitation.html`

Documented fields:

```ts
interface GeneratedAnswerCitation {
  clickUri?: string;
  fields?: Raw;
  filetype?: string;
  id: string;
  permanentid: string;
  source: string;
  text?: string;
  title: string;
  uri: string;
}
```

## Follow-Up State Shape

The tutorial README includes these type shapes for follow-up state:

```ts
export interface FollowUpAnswersState {
  /** The unique identifier of the follow-up answers conversation. */
  conversationId: string;
  /** The token proving the client originated the follow-up conversation. */
  conversationToken: string;
  /** Determines if the follow-up answer feature is enabled. */
  isEnabled: boolean;
  /** The follow-up answers. */
  followUpAnswers: FollowUpAnswer[];
}
```

```ts
export interface FollowUpAnswer extends GeneratedAnswerBase {
  /** The question prompted to generate this follow-up answer. */
  question: string;
  /** Indicates if this follow-up answer is currently active. */
  isActive: boolean;
}
```

Implication: each follow-up answer can carry its own generated answer fields, citations, error, answer ID, question, and active state.

## React Implementation Pattern

Use stable controller instances and subscribe in effects:

```tsx
import {
  buildGeneratedAnswer,
  buildSearchBox,
  buildSearchEngine,
} from '@coveo/headless';
import {useEffect, useMemo, useState} from 'react';

export function HeadlessSearchAgent({agentId, config}) {
  const engine = useMemo(
    () => buildSearchEngine({configuration: config}),
    [config]
  );
  const searchBox = useMemo(() => buildSearchBox(engine), [engine]);
  const generatedAnswer = useMemo(
    () => buildGeneratedAnswer(engine, {agentId}),
    [engine, agentId]
  );

  const [searchBoxState, setSearchBoxState] = useState(searchBox.state);
  const [answerState, setAnswerState] = useState(generatedAnswer.state);

  useEffect(() => {
    const unsubSearchBox = searchBox.subscribe(() => setSearchBoxState(searchBox.state));
    const unsubGeneratedAnswer = generatedAnswer.subscribe(() => setAnswerState(generatedAnswer.state));
    return () => {
      unsubSearchBox();
      unsubGeneratedAnswer();
    };
  }, [searchBox, generatedAnswer]);

  const submit = (query: string) => {
    searchBox.updateText(query);
    searchBox.submit();
  };

  const askFollowUp = (question: string) => {
    if ('askFollowUp' in generatedAnswer) {
      generatedAnswer.askFollowUp(question);
    }
  };

  // Render answerState.answer, answerState.citations,
  // answerState.followUpAnswers.followUpAnswers, loading/error/cannotAnswer.
}
```

Do not treat this as copy-paste complete; wire it into the local app's state and styling.

## `robotics-new-ui` Findings

Local path: `D:\Projects\robotics-new-ui` (`/mnt/d/Projects/robotics-new-ui` in WSL).

Package:

- `apps/storefront/package.json` pins `@coveo/headless` to `3.49.1`.

Primary Headless files:

- `apps/storefront/lib/use-content-agent.ts`
- `apps/storefront/components/content-search-workspace.tsx`
- `apps/storefront/components/generated-answer-body.tsx`
- `apps/storefront/lib/coveo/public-search-config.ts`
- `apps/storefront/lib/content-workspace.ts`
- Entry pages:
  - `apps/storefront/app/knowledge/page.tsx`
  - `apps/storefront/app/support/page.tsx`

### Hook Pattern

`use-content-agent.ts` is the cleanest local reference for a direct Headless Search Agent.

It imports:

```ts
buildGeneratedAnswer,
buildSearchBox,
buildSearchEngine,
loadAdvancedSearchQueryActions,
loadPipelineActions,
loadSearchHubActions
```

It creates the engine asynchronously after fetching a search token from `/api/coveo/token`:

```ts
const token = await fetchCoveoSearchToken();
const engine = buildSearchEngine({
  configuration: createSearchEngineConfiguration({ token, locale: input.locale })
});
```

Then it applies query context:

```ts
engine.dispatch(loadSearchHubActions(engine).setSearchHub(getSupportSearchHub()));
engine.dispatch(loadPipelineActions(engine).setPipeline(CONTENT_WEBSITES_PIPELINE));
engine.dispatch(
  loadAdvancedSearchQueryActions(engine).registerAdvancedSearchQueries({
    aq: buildContentScopeFilter(input.kind)
  })
);
```

Controller setup:

```ts
const searchBoxController = buildSearchBox(engine, {
  options: {
    numberOfSuggestions: 6,
    highlightOptions: {
      exactMatchDelimiters: { open: "<mark>", close: "</mark>" }
    }
  }
});

const generatedAnswerController = buildGeneratedAnswer(engine, {
  agentId: input.agentId,
  fieldsToIncludeInCitations: ["clickableuri", "source", "permanentid", "product_sku", "product_skus"]
}) as GeneratedAnswerWithFollowUps;
```

State handling:

- Store controllers in refs.
- Store `SearchBoxState | null` and `GeneratedAnswerState | GeneratedAnswerWithFollowUpsState | null` in React state.
- Subscribe to both controllers and unsubscribe in cleanup.
- Use an `isCancelled` flag so async initialization does not set state after unmount.
- Track `lastSubmittedQueryRef` so an `initialQuery` from the URL only submits once.

Commands exposed by the hook:

- `updateText(value)` updates search box text, or clears the box if the value is blank.
- `submitQuery(query)` trims, updates search box text, and calls `searchBox.submit()`.
- `submitSuggestion(value)` calls `searchBox.selectSuggestion(trimmedValue)`.
- `askFollowUp(question)` trims and calls `generatedAnswerController.askFollowUp(trimmedQuestion)` if available, falling back to `submitQuery(trimmedQuestion)`.
- `logCitationClick(citation, answerId?)` calls `generatedAnswerController.logCitationClick(citation.id, answerId)` when possible.

Follow-up normalization:

```ts
answerState.followUpAnswers.followUpAnswers.map((followUp) => ({
  question: followUp.question,
  answer: followUp.answer ?? "",
  answerContentFormat: followUp.answerContentFormat,
  answerId: followUp.answerId,
  citations: followUp.citations ?? [],
  cannotAnswer: followUp.cannotAnswer ?? false,
  isActive: followUp.isActive,
  isLoading: followUp.isLoading ?? false,
  isStreaming: followUp.isStreaming ?? false,
  generationSteps: followUp.generationSteps ?? []
}))
```

### Engine Config Pattern

`public-search-config.ts` builds a `SearchEngineConfiguration` from public env and a short-lived token:

```ts
{
  organizationId: COVEO_ORG_ID,
  accessToken: input.token,
  renewAccessToken: fetchCoveoSearchToken,
  analytics: {
    enabled: true,
    analyticsMode: "legacy",
    trackingId: COVEO_TRACKING_ID,
    originContext: "Search",
    documentLocation: typeof window === "undefined" ? SITE_URL : window.location.href
  },
  search: {
    searchHub: COVEO_SEARCH_HUB_SUPPORT,
    pipeline: CONTENT_WEBSITES_PIPELINE,
    locale: input.locale,
    timezone: Intl.DateTimeFormat().resolvedOptions().timeZone
  }
}
```

Do not hardcode tokens in client code. Robotics fetches a token from a server route and provides `renewAccessToken`.

### Conversation Turn Model

`content-search-workspace.tsx` converts Headless state into a UI-specific turn model:

```ts
type ConversationTurn = {
  key: string;
  question: string;
  answer: string;
  answerContentFormat?: "text/plain" | "text/markdown";
  answerId?: string;
  citations: GeneratedAnswerCitation[];
  cannotAnswer: boolean;
  isPending: boolean;
  activityLabel?: string;
};
```

It derives:

- `rootTurnKey = root:${trimmedActiveQuery}`
- `answerText = answerState?.answer?.trim() ?? ""`
- `agentIsLoading = !isReady || answerState?.isLoading || answerState?.isStreaming`
- `activeFollowUpAnswer = followUpAnswers.find((followUp) => followUp.isActive) ?? null`

It keeps:

- `committedTurns`: completed root and completed follow-up turns.
- `pendingFollowUpQuestion`: the question submitted while waiting for a follow-up record/answer.
- `conversationTurns`: a memoized combination of committed turns plus a pending/active turn.
- `activeConversationTurn`: the last turn in the sequence.
- `archivedConversationTurns`: all earlier turns.

Important behavior:

- On a new root query, clear `committedTurns` and `pendingFollowUpQuestion`.
- When the root answer finishes (`!isLoading && !isStreaming` and answer/cannotAnswer exists), commit it.
- When follow-up answers finish, rebuild committed turns as `[rootTurn, ...completedFollowUpTurns]`.
- While a follow-up is pending but Headless has not yet exposed an active follow-up answer, render a local pending turn keyed as `pending:${question}`.
- Once Headless exposes an active follow-up answer, render that as the active turn and derive its `activityLabel` from `generationSteps`.
- Clear `pendingFollowUpQuestion` after the matching follow-up completes or when no longer loading/streaming.

This pattern is safer than mutating one chat array directly because it keeps transient loading UI separate from completed history.

### Chained Thread Display

Robotics renders the generated answer inside an "Agent answer" card with a "Conversation" section.

Thread layout:

- A vertical timeline line.
- Archived turn marker(s).
- Active turn marker, pulsing when pending.
- Each turn has a question row followed by answer content.
- The latest turn is expanded.
- If there is one archived turn, it shows as one collapsible question row.
- If there are multiple archived turns, a "Show previous questions" button reveals the archived question list; each archived turn can be expanded independently.

This matches the requested behavior: each answer stays below its question, but previous question/response pairs are minimized after follow-ups so the active follow-up answer is the focus.

### Thinking Behavior

Robotics uses a `ThinkingIndicator` component:

- local animation frame increments every 260 ms
- label suffix cycles through periods
- a small spinner/pulse element conveys activity

Pending conditions:

- root turn pending when `agentIsLoading && !pendingFollowUpQuestion && !answerText && !answerState?.cannotAnswer`
- follow-up turn pending when no answer text and `cannotAnswer` is false
- activity label comes from `generationSteps.map((step) => step.name)` and maps common step names:
  - `searching` -> `Searching`
  - `answering` -> `Drafting answer`
  - `retrieving` -> `Retrieving sources`
  - `thinking` -> `Thinking`
  - otherwise title-case the last step name

Use official `generationSteps` from Headless, not backend-specific step names like `Response_Generation`.

### Answer Rendering

`generated-answer-body.tsx` renders according to `answerContentFormat`:

- `text/markdown`: use `react-markdown` with `remark-gfm`.
- otherwise split plain text into paragraphs on blank lines and render normal paragraphs.

This keeps generated markdown tables, lists, and links usable while avoiding markdown interpretation for plain text answers.

### Citations

Robotics renders citations as pill links:

- link target: `citation.clickUri ?? citation.uri`
- label: `citation.title || citation.source || "Referenced source"`
- click handler calls `logCitationClick(citation, answerId)`
- pass `answerId` for follow-up citation clicks so analytics ties to the correct answer when available

### Copy and Feedback Actions

Robotics implements an `AnswerCopyButton`:

- disabled/no-op for empty answer text
- uses `navigator.clipboard.writeText(answerText)`
- shows a success state for 2 seconds

Robotics does not currently call Headless `logCopyToClipboard`, `like`, or `dislike`.

When adding these controls in this repo:

- After a successful copy, call `generatedAnswer.logCopyToClipboard(turn.answerId)` when the controller is available.
- Like button: call `generatedAnswer.like(turn.answerId)`.
- Dislike button: call `generatedAnswer.dislike(turn.answerId)`.
- Use `answerState.liked/disliked` for the root answer when rendering root feedback state.
- For follow-up answers, first inspect the installed Headless types to confirm whether each `FollowUpAnswer` exposes liked/disliked state; do not invent per-follow-up flags if absent.
- Keep controls as compact icon buttons adjacent to copy, not as large text buttons.

### Query Suggestions

Robotics uses `buildSearchBox` suggestions and fallback defaults:

- `numberOfSuggestions: 6`
- highlight delimiters are `<mark>` and `</mark>`
- UI sanitizes/escapes raw suggestions before using `dangerouslySetInnerHTML`
- selection calls `searchBox.selectSuggestion(value)`

### Integration Pages

`knowledge/page.tsx` and `support/page.tsx` pass:

- `agentId` from public env (`coveoDocumentationSearchAgentId` or `coveoSupportSearchAgentId`)
- initial URL query/facets/sort/page
- initial search results loaded server-side
- locale/user context

For `aws-coveo-workshop-stackset`, the analogous implementation should connect to existing env/config conventions instead of copying Robotics env names blindly.

## `barca-help` Findings

Local path: `D:\Projects\barca-help` (`/mnt/d/Projects/barca-help` in WSL).

Package:

- `package.json` pins `@coveo/headless` to `3.49.3`.

Engine pattern:

- `helpers/Engine.ts` imports `buildSearchEngine`, `buildContext`, `loadFacetSetActions`, `loadSearchActions`, and `loadSearchAnalyticsActions`.
- It reads `NEXT_PUBLIC_SEARCH_API_KEY`.
- It uses organization ID `barcagroupproductionkwvdy6lp`.
- `buildConfig` injects logged-in context through `preprocessRequest`.
- Analytics config uses `analyticsMode: 'next'`, `trackingId: 'help'`, and current browser URL for `documentLocation` and `originLevel3`.
- `setCustomContext()` sets `{ website: 'help' }`.
- `searchEngine` is built with `searchHub: 'Search'`.

Atomic generated-answer reference:

- `components/SearchInterface.tsx` uses:

```tsx
<AtomicGeneratedAnswer collapsible={true} agentId="4ed2c4cd-ac76-4625-88c5-fb5a3d702208" />
```

That confirms the Barca help production UI has an agent ID wired for generated answers, but this is Atomic, not a custom Headless controller.

Custom search-agent UI:

- Route: `app/search-agent-coveo/page.tsx`
- Main components:
  - `components/search-agent-coveo/inputs/SearchBox.tsx`
  - `components/search-agent-coveo/inputs/InputBox.tsx`
  - `components/search-agent-coveo/thread/ConversationThread.tsx`
  - `components/search-agent-coveo/thread/AssistantMessage.tsx`
  - shared source/citation UI under `components/search-agent-shared/`

Important distinction:

- `/search-agent-coveo` does not use `buildGeneratedAnswer` directly.
- It stores conversation messages in `ConversationContext`.
- It detects the latest user message, then POSTs a `Conversation` payload to `/api/chat?app=...`.
- It parses an SSE-style response line-by-line (`data:`), builds a `steps` array, and renders answer/source/reasoning tabs from custom step names such as `Response_Generation`, `final_response`, `Orchestrator`, `Response_Evaluation`, and `Clarification_Check`.
- Follow-up suggestions in this UI come from `step.data.prompt_suggestions`, not from Headless generated-answer follow-up state.

Reusable UI ideas from `barca-help`:

- Start screen with centered input and query suggestions.
- Conversation state with `{role: 'user' | 'assistant', content, steps?, error?}`.
- Thread view with user bubbles, assistant answer cards, copy button, tabs for answer/sources/reasoning, and bottom follow-up input.
- Markdown rendering via `react-markdown` and `remark-gfm`.
- Source card pattern for title, excerpt/text, and link.

Do not copy as Headless facts:

- `steps`, `Response_Generation`, `final_response`, `prompt_suggestions`, and `Orchestrator` are app/backend-specific shapes.
- A Headless Search Agent should render `GeneratedAnswerWithFollowUpsState` instead.

## This Repo Findings

Current repo: `aws-coveo-workshop-stackset`.

Frontend:

- Server: `frontend/server.js`, Express.
- Client: `frontend/client`, React + Vite + styled-components.
- `frontend/client/package.json` does not currently include `@coveo/headless`.
- Current direct Coveo mode calls backend endpoints through `frontend/client/src/services/api.js`:
  - `/api/search`
  - `/api/passages`
  - `/api/answer`
  - `/api/chat`

Existing chat:

- `frontend/client/src/components/ChatBot.jsx` is a floating backend-driven chat.
- It uses `chatAPI(message, sessionId, backendMode, memoryId, endSession)`.
- Coveo mode is single-turn in the current app; Bedrock Agent and Coveo MCP have session IDs.

Implementation implication:

- For a true Headless Search Agent in this repo, add a new client component rather than overloading the existing backend `ChatBot` unless the user explicitly asks to replace it.
- Map Headless state directly:
  - user query from local input/searchBox state
  - assistant answer from `answerState.answer`
  - loading from `answerState.isLoading || answerState.isStreaming`
  - citations from `answerState.citations`
  - follow-up history from `answerState.followUpAnswers.followUpAnswers`
  - errors from `answerState.error`
  - no-answer from `answerState.cannotAnswer`

## Minimal Rendering Contract

Render these states:

- Initial idle state: no answer yet.
- Loading/streaming: show generating indicator.
- Error: show `state.error.message` if present.
- Cannot answer: show no-answer message.
- Main answer: markdown if `state.answerContentFormat === 'text/markdown'`, otherwise plain text is acceptable.
- Citations: render title, source, text snippet, and link from `clickUri || uri`.
- Follow-ups: render each item with its `question`, `answer`, active/loading/error state if present, and its citations.
- Feedback/analytics controls:
  - Use `like(answerId?)`, `dislike(answerId?)`, `logCopyToClipboard(answerId?)`.
  - Use `logCitationClick(citationId, answerId?)` on source link click.
  - Use `logCitationHover(citationId, durationMs, answerId?)` only if hover timing is actually tracked.

## Checklist Before Finishing

- Package pinned, not `latest`.
- Engine config comes from existing env/config conventions.
- No Coveo tokens hardcoded in committed source.
- Subscriptions cleaned up.
- Follow-up calls guarded/narrowed for TypeScript union.
- `barca-help` custom backend step fields are not treated as Headless state.
- Manual or automated test covers initial answer and one follow-up.
