import React, { useState, useRef, useEffect } from 'react';
import styled from 'styled-components';
import { motion } from 'framer-motion';
import { FiSearch, FiX, FiChevronDown } from 'react-icons/fi';
import { suggestAPI } from '../services/api';
import LoginButton from './LoginButton';

const HeaderContainer = styled.header`
  background: rgba(255, 255, 255, 0.95);
  backdrop-filter: blur(20px);
  border-bottom: 1px solid rgba(255, 255, 255, 0.2);
  padding: 20px 24px;
  position: sticky;
  top: 0;
  z-index: 100;
`;

const HeaderContent = styled.div`
  max-width: 1400px;
  margin: 0 auto;
  display: flex;
  align-items: center;
  gap: 16px;
  justify-content: space-between;
`;

const RightSection = styled.div`
  display: flex;
  align-items: center;
  gap: 16px;
`;

const Logo = styled.div`
  font-size: 24px;
  font-weight: 700;
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;
  background-clip: text;
  white-space: nowrap;
`;

const SearchContainer = styled.div`
  flex: 1;
  position: relative;
  max-width: 600px;
`;

const SearchInputWrapper = styled.div`
  position: relative;
  display: flex;
  align-items: center;
  background: white;
  border: 2px solid transparent;
  border-radius: 12px;
  box-shadow: 0 4px 20px rgba(0, 0, 0, 0.1);
  transition: all 0.3s ease;

  &:focus-within {
    border-color: #667eea;
    box-shadow: 0 4px 20px rgba(102, 126, 234, 0.2);
  }
`;

const SearchInput = styled.input`
  flex: 1;
  padding: 16px 20px;
  border: none;
  outline: none;
  font-size: 16px;
  background: transparent;
  color: #333;

  &::placeholder {
    color: #999;
  }
`;

const SearchButton = styled(motion.button)`
  padding: 16px 20px;
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  border: none;
  border-radius: 0 10px 10px 0;
  color: white;
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  transition: all 0.3s ease;

  &:hover {
    transform: translateY(-1px);
    box-shadow: 0 4px 15px rgba(102, 126, 234, 0.3);
  }
`;

const ClearButton = styled(motion.button)`
  position: absolute;
  right: 60px;
  top: 50%;
  transform: translateY(-50%);
  background: none;
  border: none;
  color: #999;
  cursor: pointer;
  padding: 8px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  height: 32px;
  width: 32px;

  &:hover {
    background: #f5f5f5;
    color: #666;
  }
`;

const BackendSelector = styled.div`
  position: relative;
`;

const BackendButton = styled(motion.button)`
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 12px 16px;
  background: white;
  border: 2px solid #e1e5e9;
  border-radius: 8px;
  color: #333;
  cursor: pointer;
  font-weight: 500;
  transition: all 0.3s ease;

  &:hover {
    border-color: #667eea;
    box-shadow: 0 2px 10px rgba(102, 126, 234, 0.1);
  }
`;

const BackendDropdown = styled(motion.div)`
  position: absolute;
  top: 100%;
  right: 0;
  margin-top: 8px;
  background: white;
  border: 1px solid #e1e5e9;
  border-radius: 8px;
  box-shadow: 0 8px 25px rgba(0, 0, 0, 0.15);
  overflow: hidden;
  min-width: 180px;
  z-index: 1000;
`;

const BackendOption = styled.div`
  padding: 12px 16px;
  cursor: pointer;
  transition: background-color 0.2s ease;
  font-weight: 500;

  &:hover {
    background: #f8f9fa;
  }

  &.active {
    background: #667eea;
    color: white;
  }
`;

const SuggestionsContainer = styled(motion.div)`
  position: absolute;
  top: 100%;
  left: 0;
  right: 0;
  background: white;
  border: 1px solid #e1e5e9;
  border-radius: 0 0 12px 12px;
  box-shadow: 0 8px 25px rgba(0, 0, 0, 0.15);
  max-height: 300px;
  overflow-y: auto;
  z-index: 1000;
`;

const SuggestionItem = styled.div`
  padding: 12px 20px;
  cursor: pointer;
  transition: background-color 0.2s ease;
  border-bottom: 1px solid #f5f5f5;

  &:hover {
    background: #f8f9fa;
  }

  &:last-child {
    border-bottom: none;
  }
`;

const backendOptions = [
  { value: 'coveo', label: 'Coveo' },
  { value: 'bedrockAgent', label: 'Bedrock Agent' },
  { value: 'coveoMCP', label: 'Coveo MCP' }
];

const SearchHeader = ({ onSearch, backendMode, onBackendModeChange, searchQuery, onClearSearch }) => {
  const [query, setQuery] = useState(searchQuery || '');
  const [showBackendDropdown, setShowBackendDropdown] = useState(false);
  const [suggestions, setSuggestions] = useState([]);
  const [showSuggestions, setShowSuggestions] = useState(false);
  const [suggestionTimeout, setSuggestionTimeout] = useState(null);
  const inputRef = useRef(null);

  useEffect(() => {
    setQuery(searchQuery || '');
  }, [searchQuery]);

  const handleSubmit = (e) => {
    e.preventDefault();
    if (query.trim()) {
      onSearch(query.trim());
      setShowSuggestions(false);
    }
  };

  const handleInputChange = (e) => {
    const value = e.target.value;
    setQuery(value);

    // Clear existing timeout
    if (suggestionTimeout) {
      clearTimeout(suggestionTimeout);
    }

    // Set new timeout for suggestions
    if (value.trim().length > 2) {
      const timeout = setTimeout(async () => {
        try {
          const response = await suggestAPI(value.trim());
          setSuggestions(response.completions || []);
          setShowSuggestions(true);
        } catch (error) {
          console.error('Suggestion error:', error);
        }
      }, 300);
      setSuggestionTimeout(timeout);
    } else {
      setShowSuggestions(false);
    }
  };

  const handleSuggestionClick = (suggestion) => {
    setQuery(suggestion.expression);
    setShowSuggestions(false);
    onSearch(suggestion.expression);
  };

  const handleClear = () => {
    setQuery('');
    setShowSuggestions(false);
    onClearSearch();
    inputRef.current?.focus();
  };

  const handleBackendChange = (mode) => {
    onBackendModeChange(mode);
    setShowBackendDropdown(false);
  };

  const currentBackend = backendOptions.find(option => option.value === backendMode);

  return (
    <HeaderContainer>
      <HeaderContent>
        <Logo>Finance & Travel Knowledge Hub</Logo>

        <SearchContainer>
          <form onSubmit={handleSubmit}>
            <SearchInputWrapper>
              <SearchInput
                ref={inputRef}
                type="text"
                placeholder="Search Wikipedia, Wikivoyage, Wikibooks, and more..."
                value={query}
                onChange={handleInputChange}
                onFocus={() => query.length > 2 && setShowSuggestions(true)}
                onBlur={() => setTimeout(() => setShowSuggestions(false), 200)}
              />

              {query && (
                <ClearButton
                  type="button"
                  onClick={handleClear}
                  whileHover={{ scale: 1.1 }}
                  whileTap={{ scale: 0.9 }}
                >
                  <FiX size={16} />
                </ClearButton>
              )}

              <SearchButton
                type="submit"
                whileHover={{ scale: 1.02 }}
                whileTap={{ scale: 0.98 }}
              >
                <FiSearch size={20} />
              </SearchButton>
            </SearchInputWrapper>
          </form>

          {showSuggestions && suggestions.length > 0 && (
            <SuggestionsContainer
              initial={{ opacity: 0, y: -10 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -10 }}
            >
              {suggestions.slice(0, 5).map((suggestion, index) => (
                <SuggestionItem
                  key={index}
                  onClick={() => handleSuggestionClick(suggestion)}
                >
                  {suggestion.expression}
                </SuggestionItem>
              ))}
            </SuggestionsContainer>
          )}
        </SearchContainer>

        <RightSection>
          <BackendSelector>
            <BackendButton
              onClick={() => setShowBackendDropdown(!showBackendDropdown)}
              whileHover={{ scale: 1.02 }}
              whileTap={{ scale: 0.98 }}
            >
              {currentBackend?.label}
              <FiChevronDown size={16} />
            </BackendButton>

            {showBackendDropdown && (
              <BackendDropdown
                initial={{ opacity: 0, y: -10 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0, y: -10 }}
              >
                {backendOptions.map((option) => (
                  <BackendOption
                    key={option.value}
                    className={option.value === backendMode ? 'active' : ''}
                    onClick={() => handleBackendChange(option.value)}
                  >
                    {option.label}
                  </BackendOption>
                ))}
              </BackendDropdown>
            )}
          </BackendSelector>

          <LoginButton />
        </RightSection>
      </HeaderContent>
    </HeaderContainer>
  );
};

export default SearchHeader;