import React, { useState, useEffect } from 'react';
import styled from 'styled-components';
import { motion, AnimatePresence } from 'framer-motion';
import SearchHeader from './components/SearchHeader';
import Sidebar from './components/Sidebar';
import SearchResults from './components/SearchResults';
import ChatBot from './components/ChatBot';
import AuthProvider, { useAuth } from './components/AuthProvider';
import LoginButton from './components/LoginButton';
import { searchAPI, passageAPI, answerAPI, testAPI } from './services/api';
import { v4 as uuidv4 } from 'uuid';

const AppContainer = styled.div`
  min-height: 100vh;
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  display: flex;
  flex-direction: column;
`;



const LoginScreen = styled.div`
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  min-height: 80vh;
  text-align: center;
  color: white;
  padding: 40px;
`;

const LoginTitle = styled.h1`
  font-size: 3rem;
  margin-bottom: 1rem;
  font-weight: 300;
  text-shadow: 0 2px 4px rgba(0, 0, 0, 0.3);
`;

const LoginSubtitle = styled.p`
  font-size: 1.2rem;
  margin-bottom: 2rem;
  opacity: 0.9;
  max-width: 600px;
`;

const LoginButtonStyled = styled.button`
  background: rgba(255, 255, 255, 0.2);
  border: 2px solid rgba(255, 255, 255, 0.3);
  color: white;
  padding: 16px 32px;
  font-size: 1.1rem;
  border-radius: 8px;
  cursor: pointer;
  transition: all 0.3s ease;
  backdrop-filter: blur(10px);

  &:hover {
    background: rgba(255, 255, 255, 0.3);
    border-color: rgba(255, 255, 255, 0.5);
    transform: translateY(-2px);
  }
`;

const MainContent = styled.div`
  display: flex;
  flex: 1;
  max-width: 1400px;
  margin: 0 auto;
  width: 100%;
  gap: 24px;
  padding: 32px 24px 24px 24px;
`;

const ContentArea = styled.div`
  flex: 1;
  display: flex;
  flex-direction: column;
  gap: 24px;
`;

const LoadingOverlay = styled(motion.div)`
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  background: rgba(0, 0, 0, 0.5);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 1000;
`;

const LoadingSpinner = styled(motion.div)`
  width: 60px;
  height: 60px;
  border: 4px solid rgba(255, 255, 255, 0.3);
  border-top: 4px solid #fff;
  border-radius: 50%;
  animation: spin 1s linear infinite;

  @keyframes spin {
    0% { transform: rotate(0deg); }
    100% { transform: rotate(360deg); }
  }
`;

// Authenticated App Component
function AuthenticatedApp() {
  const [searchQuery, setSearchQuery] = useState('');
  const [searchResults, setSearchResults] = useState(null);
  const [passages, setPassages] = useState(null);
  const [answer, setAnswer] = useState(null);
  const [facets, setFacets] = useState({});
  const [backendMode, setBackendMode] = useState('coveo');
  const [loading, setLoading] = useState(false);
  const [initialLoading, setInitialLoading] = useState(true);
  const [sessionId] = useState(uuidv4());
  const [isChatOpen, setIsChatOpen] = useState(false);
  const [loadingMore, setLoadingMore] = useState(false);

  console.log('🔄 AuthenticatedApp component rendered, initialLoading:', initialLoading, 'searchResults:', !!searchResults);

  // Load initial data on component mount (only when authenticated)
  // Also clear all results when backend mode changes
  useEffect(() => {
    const loadInitialData = async () => {
      console.log('🚀 Loading initial data for authenticated user...');
      setInitialLoading(true);
      
      // Clear all existing results when backend changes
      setAnswer(null);
      setPassages(null);
      setSearchQuery('');
      
      try {
        // Load initial data with empty query to get all results and facets
        console.log('📤 Calling searchAPI with empty query...');
        const response = await searchAPI('', {}, backendMode, 20, 0);
        console.log('📥 Initial data response:', response);
        console.log('📊 Facets:', response.facets?.length || 0);
        console.log('📄 Results:', response.results?.length || 0);
        setSearchResults(response);
        console.log('✅ Initial data loaded successfully');
      } catch (error) {
        console.error('❌ Failed to load initial data:', error);
      } finally {
        setInitialLoading(false);
      }
    };

    loadInitialData();
  }, [backendMode]);



  const handleSearch = async (query, selectedFacets = {}) => {
    if (!query.trim()) {
      // If empty query, load initial data
      const response = await searchAPI('', selectedFacets, backendMode, 20, 0);
      setSearchResults(response);
      setSearchQuery('');
      setAnswer(null);
      setPassages(null);
      return;
    }

    setLoading(true);
    setSearchQuery(query);
    setFacets(selectedFacets);

    try {
      // Sequential API calls for proper section display
      console.log('🔍 Starting search for:', query);
      
      // 1. Get search results first (always needed)
      const searchResponse = await searchAPI(query, selectedFacets, backendMode, 20, 0);
      
      // If no results, get facets from a broader search to keep them visible
      if (searchResponse.results.length === 0 && searchResponse.facets.length === 0) {
        console.log('⚠️ No results found, getting facets from broader search...');
        try {
          const facetResponse = await searchAPI('', {}, backendMode, 1, 0);
          searchResponse.facets = facetResponse.facets || [];
        } catch (error) {
          console.error('Failed to get fallback facets:', error);
        }
      }
      
      setSearchResults(searchResponse);
      console.log('✅ Search results loaded');

      // 2. Get answer (for answer section)
      try {
        const answerResponse = await answerAPI(query, backendMode);
        console.log('🔍 Answer API response:', {
          hasAnswer: !!(answerResponse.answer || answerResponse.answerText || answerResponse.response),
          answerLength: (answerResponse.answer || answerResponse.answerText || answerResponse.response || '').length,
          hasCitations: !!(answerResponse.citations && answerResponse.citations.length > 0),
          citationsCount: answerResponse.citations?.length || 0
        });
        
        // Set answer if we have valid content, otherwise set empty object to trigger fallback
        if (answerResponse && (answerResponse.answer || answerResponse.answerText || answerResponse.response)) {
          setAnswer(answerResponse);
          console.log('✅ Answer loaded successfully');
        } else {
          console.warn('⚠️ Answer API returned empty response, will show fallback message');
          setAnswer({}); // Empty object to trigger fallback message in UI
        }
      } catch (error) {
        console.error('Answer failed:', error);
        setAnswer({}); // Empty object to trigger fallback message in UI
      }

      // 3. Get passages (for passages section)
      try {
        const passageResponse = await passageAPI(query, backendMode);
        setPassages(passageResponse);
        console.log('✅ Passages loaded');
      } catch (error) {
        console.error('Passage retrieval failed:', error);
        setPassages(null);
      }

    } catch (error) {
      console.error('Search error:', error);
      setAnswer({ answer: 'I encountered an error while searching. Please try again.' });
    } finally {
      setLoading(false);
    }
  };

  const handleFacetChange = (field, value, isSelected) => {
    const newFacets = { ...facets };
    
    if (!newFacets[field]) {
      newFacets[field] = [];
    }
    
    if (isSelected) {
      if (!newFacets[field].includes(value)) {
        newFacets[field].push(value);
      }
    } else {
      newFacets[field] = newFacets[field].filter(v => v !== value);
      if (newFacets[field].length === 0) {
        delete newFacets[field];
      }
    }
    
    setFacets(newFacets);
    
    // Apply filters to current search or initial data
    if (searchQuery) {
      handleSearch(searchQuery, newFacets);
    } else {
      // Filter initial data
      handleSearch('', newFacets);
    }
  };

  const clearSearch = async () => {
    console.log('🧹 Clearing search and resetting to initial state...');
    setSearchQuery('');
    setPassages(null);
    setAnswer(null);
    setFacets({});
    
    // Load initial data with all facets and results
    try {
      const response = await searchAPI('', {}, backendMode, 20, 0);
      setSearchResults(response);
      console.log('✅ Reset to initial state with all data');
    } catch (error) {
      console.error('❌ Failed to reset to initial state:', error);
    }
  };

  const handleClearFilters = async () => {
    console.log('🧹 Clearing all filters...', 'Current facets:', facets);
    setFacets({});
    
    // Reload data without filters
    if (searchQuery) {
      console.log('🔄 Reloading search with cleared filters');
      handleSearch(searchQuery, {});
    } else {
      console.log('🔄 Reloading initial data with cleared filters');
      // Reload initial data without filters
      const response = await searchAPI('', {}, backendMode, 20, 0);
      setSearchResults(response);
    }
  };

  const handleLoadMore = async () => {
    if (!searchResults || loadingMore) return;

    setLoadingMore(true);
    try {
      const currentResultsCount = searchResults.results.length;
      const query = searchQuery || '';
      
      console.log(`📄 Loading more results... Current: ${currentResultsCount}`);
      
      const moreResults = await searchAPI(query, facets, backendMode, 20, currentResultsCount);
      
      // Append new results to existing ones
      setSearchResults(prev => ({
        ...prev,
        results: [...prev.results, ...moreResults.results]
      }));
      
      console.log(`✅ Loaded ${moreResults.results.length} more results`);
    } catch (error) {
      console.error('❌ Failed to load more results:', error);
    } finally {
      setLoadingMore(false);
    }
  };

  return (
    <>
      <SearchHeader
        onSearch={handleSearch}
        backendMode={backendMode}
        onBackendModeChange={setBackendMode}
        searchQuery={searchQuery}
        onClearSearch={clearSearch}
      />
      
      <MainContent>
        <Sidebar
          facets={searchResults?.facets || []}
          selectedFacets={facets}
          onFacetChange={handleFacetChange}
          onClearFilters={handleClearFilters}
          totalResults={searchResults?.totalCount || 0}
        />
        
        <ContentArea>
          <SearchResults
            query={searchQuery}
            answer={answer}
            passages={passages}
            searchResults={searchResults}
            backendMode={backendMode}
            onLoadMore={handleLoadMore}
            loadingMore={loadingMore}
          />
        </ContentArea>
      </MainContent>

      <ChatBot
        isOpen={isChatOpen}
        onToggle={() => setIsChatOpen(!isChatOpen)}
        backendMode={backendMode}
        sessionId={sessionId}
      />

      <AnimatePresence>
        {(loading || initialLoading) && (
          <LoadingOverlay
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
          >
            <LoadingSpinner />
          </LoadingOverlay>
        )}
      </AnimatePresence>
    </>
  );
}

// Main App Component with Authentication Check
function App() {
  return (
    <AuthProvider>
      <AppContainer>
        <AppContent />
      </AppContainer>
    </AuthProvider>
  );
}

// App Content Component that checks authentication
function AppContent() {
  const { isAuthenticated, loading, login } = useAuth();

  if (loading) {
    return (
      <LoadingOverlay>
        <LoadingSpinner />
      </LoadingOverlay>
    );
  }

  if (!isAuthenticated()) {
    return (
      <LoginScreen>
        <LoginTitle>Finance & Travel Knowledge Hub</LoginTitle>
        <LoginSubtitle>
          Coveo-powered answers from Wikipedia, Investor.gov, CFPB, CDC, and more. Please login to access the search interface and explore our three different backend modes: Coveo, BedrockAgent, and CoveoMCP.
        </LoginSubtitle>
        <LoginButtonStyled onClick={login}>
          Login to Continue
        </LoginButtonStyled>
      </LoginScreen>
    );
  }

  return <AuthenticatedApp />;
}

export default App;