# Lab 3 Instructor Guide

## Preflight

Before the workshop:

- Confirm `COVEO_SEARCH_AGENT_ID` is set.
- Confirm `COVEO_ORG_ID`, `COVEO_SEARCH_API_KEY`, `COVEO_SEARCH_HUB`, and `COVEO_SEARCH_PIPELINE` are set.
- Open the workshop UI and select **Coveo Search Agent**.
- Run one initial question and one follow-up.
- Confirm citations render.
- Confirm copy, like, and dislike buttons do not throw errors.

## Demo Script

1. Remind attendees that Lab 2 used AWS AgentCore.
2. Explain that Lab 3 removes AWS agent orchestration.
3. Open the Coveo Console and show the Search Agent configuration.
4. Test an initial question and a follow-up in Coveo Console.
5. Open the workshop UI.
6. Select **Coveo Search Agent**.
7. Run the same question and follow-up.
8. Point out:
   - Headless controller state
   - generated answer
   - citations
   - follow-up answer chain
   - no AgentCore session or memory controls

## Fallback

If the Search Agent cannot answer:

1. Verify the Search Agent ID.
2. Verify the query pipeline and search hub.
3. Verify the browser token has search and generated-answer permissions.
4. Use the Coveo Console test surface to confirm whether the issue is configuration or UI.

If follow-ups do not work:

1. Confirm the generated-answer controller exposes `askFollowUp`.
2. Confirm the first answer completed before asking a follow-up.
3. Check browser console errors.

## Timing

Target timing:

- Console review: 5 minutes
- Console test: 5 minutes
- UI test: 10 minutes
- discussion/comparison with AgentCore: 5 minutes
