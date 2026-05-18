import {
  buildGeneratedAnswer,
  buildSearchBox,
  buildSearchEngine
} from '@coveo/headless';
import { useCallback, useEffect, useRef, useState } from 'react';

const loadRuntimeConfig = async () => {
  const response = await fetch('/api/config');
  if (!response.ok) {
    throw new Error(`Unable to load workshop configuration (${response.status}).`);
  }
  return response.json();
};

const buildConfiguration = (runtimeConfig) => {
  const coveoConfig = runtimeConfig?.coveo || {};
  const organizationId = coveoConfig.orgId;
  const accessToken = coveoConfig.searchApiKey;
  const searchHub = coveoConfig.searchHub;
  const pipeline = coveoConfig.searchPipeline;
  const environment = coveoConfig.environment || 'prod';

  if (!organizationId || !accessToken) {
    throw new Error('Missing COVEO_ORG_ID or COVEO_SEARCH_API_KEY for Coveo Search Agent mode.');
  }

  return {
    accessToken,
    organizationId,
    environment,
    search: {
      ...(pipeline ? { pipeline } : {}),
      ...(searchHub ? { searchHub } : {})
    },
    analytics: {
      analyticsMode: 'legacy',
      ...(typeof window !== 'undefined' ? { documentLocation: window.location.href } : {})
    }
  };
};

const getFollowUpAnswers = (answerState) => {
  return answerState?.followUpAnswers?.followUpAnswers || [];
};

export function useCoveoSearchAgent() {
  const searchBoxRef = useRef(null);
  const generatedAnswerRef = useRef(null);
  const [isReady, setIsReady] = useState(false);
  const [initializationError, setInitializationError] = useState(null);
  const [searchBoxState, setSearchBoxState] = useState(null);
  const [answerState, setAnswerState] = useState(null);
  const [submittedQuery, setSubmittedQuery] = useState('');
  const [runtimeConfig, setRuntimeConfig] = useState(null);

  useEffect(() => {
    let cancelled = false;

    async function fetchConfig() {
      try {
        const config = await loadRuntimeConfig();
        if (!cancelled) {
          setRuntimeConfig(config);
        }
      } catch (error) {
        if (!cancelled) {
          setInitializationError(error instanceof Error ? error.message : 'Unable to load workshop configuration.');
          setIsReady(false);
        }
      }
    }

    fetchConfig();

    return () => {
      cancelled = true;
    };
  }, []);

  useEffect(() => {
    if (!runtimeConfig) return undefined;

    const coveoConfig = runtimeConfig.coveo || {};
    const agentId = coveoConfig.searchAgentId;

    if (!agentId) {
      setInitializationError('Missing COVEO_SEARCH_AGENT_ID for Coveo Search Agent mode.');
      setIsReady(false);
      return undefined;
    }

    let engine;
    try {
      engine = buildSearchEngine({ configuration: buildConfiguration(runtimeConfig) });
    } catch (error) {
      setInitializationError(error instanceof Error ? error.message : 'Unable to initialize Coveo Search Agent.');
      setIsReady(false);
      return undefined;
    }

    const searchBox = buildSearchBox(engine, {
      options: {
        numberOfSuggestions: 6,
        highlightOptions: {
          exactMatchDelimiters: {
            open: '<mark>',
            close: '</mark>'
          }
        }
      }
    });
    const generatedAnswer = buildGeneratedAnswer(engine, {
      agentId,
      fieldsToIncludeInCitations: ['clickableuri', 'source', 'permanentid', 'project', 'documenttype', 'filetype']
    });

    searchBoxRef.current = searchBox;
    generatedAnswerRef.current = generatedAnswer;
    setSearchBoxState(searchBox.state);
    setAnswerState(generatedAnswer.state);
    setInitializationError(null);
    setIsReady(true);

    const unsubscribeSearchBox = searchBox.subscribe(() => setSearchBoxState(searchBox.state));
    const unsubscribeGeneratedAnswer = generatedAnswer.subscribe(() => setAnswerState(generatedAnswer.state));

    return () => {
      unsubscribeSearchBox();
      unsubscribeGeneratedAnswer();
      searchBoxRef.current = null;
      generatedAnswerRef.current = null;
      setIsReady(false);
    };
  }, [runtimeConfig]);

  const updateText = useCallback((value) => {
    const searchBox = searchBoxRef.current;
    if (!searchBox) return;

    if (!value.trim()) {
      searchBox.clear();
      return;
    }

    searchBox.updateText(value);
  }, []);

  const submitQuery = useCallback((query) => {
    const trimmedQuery = query.trim();
    const searchBox = searchBoxRef.current;
    if (!trimmedQuery || !searchBox) return;

    setSubmittedQuery(trimmedQuery);
    searchBox.updateText(trimmedQuery);
    searchBox.submit();
  }, []);

  const askFollowUp = useCallback((question) => {
    const trimmedQuestion = question.trim();
    const generatedAnswer = generatedAnswerRef.current;
    if (!trimmedQuestion || !generatedAnswer) return false;

    if (typeof generatedAnswer.askFollowUp === 'function') {
      const followUpState = generatedAnswer.state?.followUpAnswers;
      if (!followUpState?.isEnabled || !followUpState?.conversationId || !followUpState?.conversationToken) {
        return false;
      }
      void generatedAnswer.askFollowUp(trimmedQuestion);
      return true;
    }

    return false;
  }, []);

  const logCitationClick = useCallback((citation, answerId) => {
    const generatedAnswer = generatedAnswerRef.current;
    if (!generatedAnswer || !citation?.id || typeof generatedAnswer.logCitationClick !== 'function') return;
    generatedAnswer.logCitationClick(citation.id, answerId);
  }, []);

  const logCopyToClipboard = useCallback((answerId) => {
    const generatedAnswer = generatedAnswerRef.current;
    if (!generatedAnswer || typeof generatedAnswer.logCopyToClipboard !== 'function') return;
    generatedAnswer.logCopyToClipboard(answerId);
  }, []);

  const likeAnswer = useCallback((answerId) => {
    const generatedAnswer = generatedAnswerRef.current;
    if (!generatedAnswer || typeof generatedAnswer.like !== 'function') return;
    generatedAnswer.like(answerId);
  }, []);

  const dislikeAnswer = useCallback((answerId) => {
    const generatedAnswer = generatedAnswerRef.current;
    if (!generatedAnswer || typeof generatedAnswer.dislike !== 'function') return;
    generatedAnswer.dislike(answerId);
  }, []);

  return {
    isReady,
    initializationError,
    searchBoxState,
    answerState,
    submittedQuery,
    suggestions: searchBoxState?.suggestions || [],
    followUpAnswers: getFollowUpAnswers(answerState),
    updateText,
    submitQuery,
    askFollowUp,
    logCitationClick,
    logCopyToClipboard,
    likeAnswer,
    dislikeAnswer
  };
}
