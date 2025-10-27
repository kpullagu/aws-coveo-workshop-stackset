import { useState } from 'react';
import styled from 'styled-components';
import { motion } from 'framer-motion';
import { FiExternalLink, FiMapPin, FiCalendar, FiTag, FiImage, FiEye, FiChevronDown, FiChevronUp } from 'react-icons/fi';
import ReactMarkdown from 'react-markdown';
import { format } from 'date-fns';
import QuickViewModal from './QuickViewModal';

const ResultsContainer = styled.div`
  display: flex;
  flex-direction: column;
  gap: 24px;
`;

const Section = styled(motion.section)`
  background: rgba(255, 255, 255, 0.95);
  backdrop-filter: blur(20px);
  border-radius: 16px;
  padding: 24px;
  box-shadow: 0 8px 32px rgba(0, 0, 0, 0.1);
`;

const SectionHeader = styled.div`
  display: flex;
  align-items: center;
  gap: 12px;
  margin-bottom: 20px;
  padding-bottom: 16px;
  border-bottom: 1px solid #e1e5e9;
`;

const SectionTitle = styled.h2`
  font-size: 20px;
  font-weight: 600;
  color: #333;
`;

const SectionBadge = styled.span`
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  color: white;
  padding: 4px 12px;
  border-radius: 12px;
  font-size: 12px;
  font-weight: 500;
  text-transform: uppercase;
  letter-spacing: 0.5px;
`;

const AnswerContent = styled.div`
  font-size: 16px;
  line-height: 1.6;
  color: #333;
  
  p {
    margin-bottom: 16px;
  }
  
  strong {
    color: #667eea;
  }
`;

const AnswerText = styled.div`
  margin-bottom: 16px;
  line-height: 1.8;
  color: #2c3e50;
  
  /* Headings */
  h1, h2, h3, h4, h5, h6 {
    color: #1a202c;
    font-weight: 600;
    margin-top: 24px;
    margin-bottom: 12px;
    line-height: 1.3;
  }
  
  h1 {
    font-size: 2em;
    border-bottom: 2px solid #667eea;
    padding-bottom: 8px;
  }
  
  h2 {
    font-size: 1.5em;
    border-bottom: 1px solid #e2e8f0;
    padding-bottom: 6px;
  }
  
  h3 {
    font-size: 1.25em;
    color: #667eea;
  }
  
  h4 {
    font-size: 1.1em;
  }
  
  /* Paragraphs */
  p {
    margin-bottom: 16px;
    line-height: 1.8;
  }
  
  /* Lists */
  ul, ol {
    margin: 16px 0;
    padding-left: 32px;
  }
  
  li {
    margin-bottom: 8px;
    line-height: 1.6;
  }
  
  ul li {
    list-style-type: disc;
  }
  
  ol li {
    list-style-type: decimal;
  }
  
  /* Links */
  a {
    color: #667eea;
    text-decoration: none;
    font-weight: 500;
    border-bottom: 1px solid transparent;
    transition: all 0.2s ease;
    
    &:hover {
      border-bottom-color: #667eea;
      color: #764ba2;
    }
  }
  
  /* Code */
  code {
    background: #f7fafc;
    border: 1px solid #e2e8f0;
    border-radius: 4px;
    padding: 2px 6px;
    font-family: 'Monaco', 'Menlo', 'Ubuntu Mono', monospace;
    font-size: 0.9em;
    color: #e53e3e;
  }
  
  pre {
    background: #2d3748;
    color: #f7fafc;
    border-radius: 8px;
    padding: 16px;
    overflow-x: auto;
    margin: 16px 0;
    
    code {
      background: transparent;
      border: none;
      color: #f7fafc;
      padding: 0;
    }
  }
  
  /* Blockquotes */
  blockquote {
    border-left: 4px solid #667eea;
    padding-left: 16px;
    margin: 16px 0;
    color: #4a5568;
    font-style: italic;
    background: #f7fafc;
    padding: 12px 16px;
    border-radius: 0 8px 8px 0;
  }
  
  /* Strong/Bold */
  strong {
    font-weight: 600;
    color: #1a202c;
  }
  
  /* Emphasis/Italic */
  em {
    font-style: italic;
    color: #4a5568;
  }
  
  /* Horizontal Rule */
  hr {
    border: none;
    border-top: 2px solid #e2e8f0;
    margin: 24px 0;
  }
  
  /* Tables */
  table {
    width: 100%;
    border-collapse: collapse;
    margin: 16px 0;
  }
  
  th, td {
    border: 1px solid #e2e8f0;
    padding: 12px;
    text-align: left;
  }
  
  th {
    background: #f7fafc;
    font-weight: 600;
    color: #1a202c;
  }
  
  tr:nth-child(even) {
    background: #f7fafc;
  }
`;

const FallbackMessage = styled.div`
  background: #f8f9fa;
  border: 1px solid #e9ecef;
  border-radius: 8px;
  padding: 20px;
  text-align: center;
  color: #6c757d;
  font-style: italic;
  line-height: 1.6;
  
  .query-highlight {
    color: #667eea;
    font-weight: 500;
    font-style: normal;
  }
`;

const ShowMoreButton = styled(motion.button)`
  background: none;
  border: 1px solid #667eea;
  color: #667eea;
  cursor: pointer;
  font-size: 14px;
  font-weight: 500;
  padding: 8px 16px;
  border-radius: 6px;
  display: flex;
  align-items: center;
  gap: 6px;
  margin-top: 8px;
  transition: all 0.2s ease;
  
  &:hover {
    background: #667eea;
    color: white;
    transform: translateY(-1px);
  }
`;

const Citations = styled.div`
  margin-top: 16px;
  padding-top: 16px;
  border-top: 1px solid #e1e5e9;
`;

const CitationsTitle = styled.h4`
  font-size: 14px;
  font-weight: 600;
  color: #333;
  margin-bottom: 12px;
`;

const CitationItem = styled.div`
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 8px 12px;
  background: #f8f9fa;
  border-radius: 6px;
  margin-bottom: 8px;
  font-size: 13px;
  
  a {
    color: #667eea;
    text-decoration: none;
    
    &:hover {
      text-decoration: underline;
    }
  }
`;

const PassageGrid = styled.div`
  display: grid;
  gap: 16px;
`;

const PassageCard = styled(motion.div)`
  background: #f8f9fa;
  border-radius: 12px;
  padding: 20px;
  border-left: 4px solid #667eea;
  transition: all 0.3s ease;

  &:hover {
    background: #f1f3f4;
    transform: translateY(-2px);
    box-shadow: 0 4px 20px rgba(0, 0, 0, 0.1);
  }
`;

const PassageText = styled.p`
  font-size: 15px;
  line-height: 1.6;
  color: #333;
  margin-bottom: 12px;
  display: -webkit-box;
  -webkit-line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
  text-overflow: ellipsis;
`;

const PassageSource = styled.div`
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
  font-size: 13px;
  color: #666;
`;

const PassageSourceInfo = styled.div`
  display: flex;
  align-items: center;
  gap: 8px;
`;

const PassageActions = styled.div`
  display: flex;
  gap: 8px;
`;

const PassageQuickView = styled.button`
  background: none;
  border: 1px solid #667eea;
  color: #667eea;
  padding: 4px 8px;
  border-radius: 4px;
  font-size: 11px;
  cursor: pointer;
  transition: all 0.2s ease;

  &:hover {
    background: #667eea;
    color: white;
  }
`;

const PassageCitationLink = styled.a`
  background: none;
  border: 1px solid #28a745;
  color: #28a745;
  padding: 4px 8px;
  border-radius: 4px;
  font-size: 11px;
  text-decoration: none;
  display: inline-flex;
  align-items: center;
  transition: all 0.2s ease;

  &:hover {
    background: #28a745;
    color: white;
  }
`;

const ResultsGrid = styled.div`
  display: grid;
  gap: 20px;
`;

const ResultCard = styled(motion.div)`
  background: white;
  border-radius: 12px;
  padding: 24px;
  border: 1px solid #e1e5e9;
  transition: all 0.3s ease;

  &:hover {
    border-color: #667eea;
    box-shadow: 0 8px 25px rgba(102, 126, 234, 0.15);
    transform: translateY(-2px);
  }
`;

const ResultHeader = styled.div`
  display: flex;
  align-items: flex-start;
  gap: 16px;
  margin-bottom: 16px;
`;

const ResultImage = styled.img`
  width: 80px;
  height: 80px;
  object-fit: cover;
  border-radius: 8px;
  flex-shrink: 0;
`;

const ResultContent = styled.div`
  flex: 1;
`;

const ResultTitle = styled.h3`
  font-size: 18px;
  font-weight: 600;
  color: #333;
  margin-bottom: 8px;
  line-height: 1.3;
  
  a {
    color: inherit;
    text-decoration: none;
    
    &:hover {
      color: #667eea;
    }
  }
`;

const ResultSummary = styled.p`
  font-size: 14px;
  color: #666;
  line-height: 1.5;
  margin-bottom: 12px;
`;

const ContentPreview = styled.div`
  font-size: 13px;
  color: #555;
  line-height: 1.4;
  margin-bottom: 12px;
  display: -webkit-box;
  -webkit-line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
  text-overflow: ellipsis;
  background: #f8f9fa;
  padding: 8px 12px;
  border-radius: 6px;
  border-left: 3px solid #667eea;
`;

const ResultMeta = styled.div`
  display: flex;
  flex-wrap: wrap;
  gap: 12px;
  margin-bottom: 12px;
`;

const MetaItem = styled.div`
  display: flex;
  align-items: center;
  gap: 4px;
  font-size: 12px;
  color: #666;
  background: #f8f9fa;
  padding: 4px 8px;
  border-radius: 6px;
`;

const ResultFooter = styled.div`
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding-top: 12px;
  border-top: 1px solid #f0f0f0;
`;

const ProjectBadge = styled.span`
  background: ${props => getProjectColor(props.project)};
  color: white;
  padding: 4px 8px;
  border-radius: 6px;
  font-size: 11px;
  font-weight: 500;
  text-transform: uppercase;
`;

const ViewButton = styled.a`
  display: flex;
  align-items: center;
  gap: 6px;
  color: #667eea;
  text-decoration: none;
  font-size: 13px;
  font-weight: 500;
  transition: color 0.2s ease;

  &:hover {
    color: #764ba2;
  }
`;

const QuickViewButton = styled.button`
  display: flex;
  align-items: center;
  gap: 6px;
  background: none;
  border: 1px solid #667eea;
  color: #667eea;
  padding: 6px 12px;
  border-radius: 6px;
  font-size: 12px;
  font-weight: 500;
  cursor: pointer;
  transition: all 0.2s ease;

  &:hover {
    background: #667eea;
    color: white;
  }
`;

const EmptyState = styled.div`
  text-align: center;
  padding: 60px 20px;
  color: #666;
`;

const EmptyStateTitle = styled.h3`
  font-size: 24px;
  font-weight: 600;
  color: #333;
  margin-bottom: 12px;
`;

const EmptyStateText = styled.p`
  font-size: 16px;
  line-height: 1.5;
`;

const LoadMoreContainer = styled.div`
  display: flex;
  justify-content: center;
  padding: 24px;
`;

const LoadMoreButton = styled(motion.button)`
  padding: 12px 24px;
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  color: white;
  border: none;
  border-radius: 8px;
  font-size: 14px;
  font-weight: 500;
  cursor: pointer;
  display: flex;
  align-items: center;
  gap: 8px;
  transition: all 0.3s ease;

  &:hover {
    transform: translateY(-1px);
    box-shadow: 0 4px 15px rgba(102, 126, 234, 0.3);
  }

  &:disabled {
    opacity: 0.6;
    cursor: not-allowed;
    transform: none;
  }
`;

const LoadingSpinner = styled.div`
  width: 16px;
  height: 16px;
  border: 2px solid rgba(255, 255, 255, 0.3);
  border-top: 2px solid white;
  border-radius: 50%;
  animation: spin 1s linear infinite;

  @keyframes spin {
    0% { transform: rotate(0deg); }
    100% { transform: rotate(360deg); }
  }
`;

const getProjectColor = (project) => {
  const colors = {
    wikipedia: '#0066cc',
    wikibooks: '#ff6600',
    wikinews: '#cc0000',
    wikiquote: '#9966cc',
    wikidata: '#006699'
  };
  return colors[project] || '#667eea';
};

const formatDate = (dateString) => {
  if (!dateString) return null;
  try {
    return format(new Date(dateString), 'MMM d, yyyy');
  } catch {
    return null;
  }
};

const SearchResults = ({ query, answer, passages, searchResults, backendMode, onLoadMore, loadingMore, loading }) => {
  const [quickViewResult, setQuickViewResult] = useState(null);
  const [quickViewPassage, setQuickViewPassage] = useState(null);
  const [showFullAnswer, setShowFullAnswer] = useState(false);
  const hasSearchQuery = query && query.trim() !== '';

  // Debug logging for answer structure
  if (answer) {
    console.log('🔍 Answer structure:', {
      hasAnswer: !!answer.answer,
      hasAnswerText: !!answer.answerText,
      hasResponse: !!answer.response,
      answerLength: (answer.answer || answer.answerText || answer.response || '').length,
      hasCitations: !!(answer.citations && answer.citations.length > 0)
    });
  }

  const handleQuickView = (result) => {
    console.log('🔍 QuickView clicked for result:', {
      title: result.title,
      resultKeys: Object.keys(result),
      rawKeys: result.raw ? Object.keys(result.raw) : 'no raw',
      allPossibleIds: {
        uniqueId: result.uniqueId,
        'raw.uniqueId': result.raw?.uniqueId,
        'raw.uniqueid': result.raw?.uniqueid,
        'raw.permanentid': result.raw?.permanentid,
        permanentid: result.permanentid,
        id: result.id,
        uniqueid: result.uniqueid,
        uri: result.uri,
        clickUri: result.clickUri
      },
      fullResult: result
    });
    setQuickViewResult(result);
  };

  const closeQuickView = () => {
    setQuickViewResult(null);
    setQuickViewPassage(null);
  };

  const handlePassageQuickView = (passage) => {
    setQuickViewPassage(passage);
  };

  const toggleShowMore = () => {
    setShowFullAnswer(!showFullAnswer);
  };

  const truncateText = (text, maxLength = 400) => {
    if (!text || text.length <= maxLength) return text;
    // Find the last complete sentence or word boundary near the limit
    const truncated = text.substring(0, maxLength);
    const lastSentence = truncated.lastIndexOf('.');
    const lastSpace = truncated.lastIndexOf(' ');

    // Use sentence boundary if it's within reasonable range, otherwise use word boundary
    const cutPoint = lastSentence > maxLength - 100 ? lastSentence + 1 :
      lastSpace > maxLength - 50 ? lastSpace : maxLength;

    return text.substring(0, cutPoint).trim() + '...';
  };

  if (!searchResults) {
    return (
      <ResultsContainer>
        <Section
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.6 }}
        >
          <EmptyState>
            <EmptyStateTitle>Welcome to Coveo Workshop Knowledge Explorer</EmptyStateTitle>
            <EmptyStateText>
              AI-powered financial knowledge from Wikipedia, Investor.gov, IRS, NCUA, FinCEN, CFPB, FDIC, FRB, OCC, MyMoney, and FTC.
              <br />
              Get AI-powered answers, relevant passages, and comprehensive results.
            </EmptyStateText>
          </EmptyState>
        </Section>
      </ResultsContainer>
    );
  }

  return (
    <ResultsContainer>
      {/* AI Answer Section - Show when there's a search query */}
      {hasSearchQuery && !loading && (
        answer && (answer.answer || answer.answerText || answer.response) ? (
          <Section
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.6 }}
          >
            <SectionHeader>
              <SectionTitle>AI Answer</SectionTitle>
              <SectionBadge>{backendMode}</SectionBadge>
            </SectionHeader>
            <AnswerContent>
              <AnswerText>
                <ReactMarkdown>
                  {(() => {
                    const fullAnswerText = answer.answer || answer.answerText || answer.response || '';
                    return showFullAnswer ? fullAnswerText : truncateText(fullAnswerText, 400);
                  })()}
                </ReactMarkdown>
              </AnswerText>

              {(() => {
                const fullAnswerText = answer.answer || answer.answerText || answer.response || '';
                return fullAnswerText && fullAnswerText.length > 400;
              })() && (
                  <ShowMoreButton
                    onClick={toggleShowMore}
                    whileHover={{ scale: 1.02 }}
                    whileTap={{ scale: 0.98 }}
                  >
                    {showFullAnswer ? (
                      <>
                        <FiChevronUp size={16} />
                        Show Less
                      </>
                    ) : (
                      <>
                        <FiChevronDown size={16} />
                        Show More
                      </>
                    )}
                  </ShowMoreButton>
                )}

              {(answer.citations && answer.citations.length > 0) && (
                <Citations>
                  <CitationsTitle>Sources:</CitationsTitle>
                  {answer.citations.map((citation, index) => (
                    <CitationItem key={index}>
                      <span>{index + 1}.</span>
                      <a href={citation.uri || citation.clickableuri || citation.clickUri} target="_blank" rel="noopener noreferrer">
                        {citation.title}
                      </a>
                      {citation.project && (
                        <ProjectBadge project={citation.project}>
                          {citation.project}
                        </ProjectBadge>
                      )}
                    </CitationItem>
                  ))}
                </Citations>
              )}

              {/* Fallback: Show sources from search results if no direct citations */}
              {(!answer.citations || answer.citations.length === 0) && searchResults && searchResults.results && searchResults.results.length > 0 && (
                <Citations>
                  <CitationsTitle>Related Sources:</CitationsTitle>
                  {searchResults.results.slice(0, 3).map((result, index) => (
                    <CitationItem key={index}>
                      <span>{index + 1}.</span>
                      <a href={result.clickUri} target="_blank" rel="noopener noreferrer">
                        {result.title}
                      </a>
                      {result.raw?.project && (
                        <ProjectBadge project={result.raw.project}>
                          {result.raw.project}
                        </ProjectBadge>
                      )}
                    </CitationItem>
                  ))}
                </Citations>
              )}
            </AnswerContent>
          </Section>
        ) : (
          // Fallback when no answer is available
          <Section
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.6 }}
          >
            <SectionHeader>
              <SectionTitle>AI Answer</SectionTitle>
              <SectionBadge>{backendMode}</SectionBadge>
            </SectionHeader>
            <AnswerContent>
              <FallbackMessage>
                I don't have enough information to generate a comprehensive answer for your query <span className="query-highlight">"{query}"</span>.
                Please check the search results and relevant passages below for detailed information.
              </FallbackMessage>
            </AnswerContent>
          </Section>
        )
      )}

      {/* Relevant Passages Section - Only show when there's a search query */}
      {hasSearchQuery && passages && (passages.passages || passages.results || passages.items) &&
        (passages.passages?.length > 0 || passages.results?.length > 0 || passages.items?.length > 0) && (
          <Section
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.6, delay: 0.1 }}
          >
            <SectionHeader>
              <SectionTitle>Relevant Passages</SectionTitle>
              <SectionBadge>Top {Math.min((passages.passages || passages.results || passages.items || []).length, 5)}</SectionBadge>
            </SectionHeader>
            <PassageGrid>
              {(passages.passages || passages.results || passages.items || []).slice(0, 5).map((passage, index) => (
                <PassageCard
                  key={index}
                  initial={{ opacity: 0, x: -20 }}
                  animate={{ opacity: 1, x: 0 }}
                  transition={{ duration: 0.4, delay: index * 0.1 }}
                >
                  <PassageText>{passage.content || passage.text || passage.excerpt || 'No content available'}</PassageText>
                  <PassageSource>
                    <PassageSourceInfo>
                      <FiExternalLink size={12} />
                      <span>Passages from: {passage.title || passage.document?.title || passage.name || 'Untitled'}</span>
                      {(passage.project || passage.document?.project) && (
                        <>
                          <span>•</span>
                          <ProjectBadge project={passage.project || passage.document?.project}>
                            {passage.project || passage.document?.project}
                          </ProjectBadge>
                        </>
                      )}
                    </PassageSourceInfo>
                    <PassageActions>
                      <PassageQuickView onClick={() => handlePassageQuickView(passage)}>
                        <FiEye size={10} style={{ marginRight: '4px' }} />
                        Quick View
                      </PassageQuickView>
                      {(passage.clickUri || passage.clickableuri || passage.uri || passage.document?.clickableuri) && (
                        <PassageCitationLink
                          href={passage.clickUri || passage.clickableuri || passage.uri || passage.document?.clickableuri}
                          target="_blank"
                          rel="noopener noreferrer"
                        >
                          <FiExternalLink size={10} style={{ marginRight: '4px' }} />
                          Source
                        </PassageCitationLink>
                      )}
                    </PassageActions>
                  </PassageSource>
                </PassageCard>
              ))}
            </PassageGrid>
          </Section>
        )}

      {/* Search Results Section - Always show when we have results */}
      {searchResults && searchResults.results && searchResults.results.length > 0 && (
        <Section
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.6, delay: hasSearchQuery ? 0.2 : 0 }}
        >
          <SectionHeader>
            <SectionTitle>
              {hasSearchQuery ? 'Search Results' : 'Browse All Content'}
            </SectionTitle>
            <SectionBadge>
              {searchResults.totalCount?.toLocaleString()} found
            </SectionBadge>
          </SectionHeader>
          <ResultsGrid>
            {searchResults.results.map((result, index) => (
              <ResultCard
                key={result.uniqueId || index}
                initial={{ opacity: 0, y: 20 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ duration: 0.4, delay: index * 0.05 }}
                whileHover={{ scale: 1.01 }}
              >
                <ResultHeader>
                  {result.raw.images && result.raw.images.length > 0 && (
                    <ResultImage
                      src={result.raw.images[0]}
                      alt={result.title}
                      onError={(e) => { e.target.style.display = 'none'; }}
                    />
                  )}
                  <ResultContent>
                    <ResultTitle>
                      <a href={result.clickUri} target="_blank" rel="noopener noreferrer">
                        {result.title}
                      </a>
                    </ResultTitle>
                    {result.raw.summary && (
                      <ResultSummary>{result.raw.summary}</ResultSummary>
                    )}
                    {(result.raw.data || result.excerpt) && (
                      <ContentPreview>
                        {(() => {
                          const content = result.raw.data || result.excerpt || '';
                          // Strip HTML tags and get first 200 characters
                          const cleanContent = content.replace(/<[^>]*>/g, '').trim();
                          return cleanContent.length > 200 ? cleanContent.substring(0, 200) + '...' : cleanContent;
                        })()}
                      </ContentPreview>
                    )}
                    <ResultMeta>
                      {result.raw.date && (
                        <MetaItem>
                          <FiCalendar size={12} />
                          {formatDate(result.raw.date)}
                        </MetaItem>
                      )}
                      {result.raw.documenttype && (
                        <MetaItem>
                          <FiTag size={12} />
                          {result.raw.documenttype.replace(/_/g, ' ')}
                        </MetaItem>
                      )}
                      {result.raw.geo_lat && result.raw.geo_lon && (
                        <MetaItem>
                          <FiMapPin size={12} />
                          Location
                        </MetaItem>
                      )}
                      {result.raw.has_image === '1' && (
                        <MetaItem>
                          <FiImage size={12} />
                          Has Images
                        </MetaItem>
                      )}
                    </ResultMeta>
                  </ResultContent>
                </ResultHeader>
                <ResultFooter>
                  {result.raw.project && (
                    <ProjectBadge project={result.raw.project}>
                      {result.raw.project}
                    </ProjectBadge>
                  )}
                  <div style={{ display: 'flex', gap: '8px' }}>
                    <QuickViewButton onClick={() => handleQuickView(result)}>
                      <FiEye size={12} />
                      Quick View
                    </QuickViewButton>
                    <ViewButton href={result.clickUri} target="_blank" rel="noopener noreferrer">
                      View Article <FiExternalLink size={12} />
                    </ViewButton>
                  </div>
                </ResultFooter>
              </ResultCard>
            ))}
          </ResultsGrid>

          {/* Load More Button */}
          {searchResults.results.length < searchResults.totalCount && (
            <LoadMoreContainer>
              <LoadMoreButton
                onClick={onLoadMore}
                disabled={loadingMore}
                whileHover={{ scale: loadingMore ? 1 : 1.02 }}
                whileTap={{ scale: loadingMore ? 1 : 0.98 }}
              >
                {loadingMore ? (
                  <>
                    <LoadingSpinner />
                    Loading...
                  </>
                ) : (
                  <>
                    Load More ({searchResults.totalCount - searchResults.results.length} remaining)
                  </>
                )}
              </LoadMoreButton>
            </LoadMoreContainer>
          )}
        </Section>
      )}

      {/* No Results State */}
      {searchResults && searchResults.results && searchResults.results.length === 0 && (
        <Section
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.6 }}
        >
          <EmptyState>
            <EmptyStateTitle>No results found</EmptyStateTitle>
            <EmptyStateText>
              Try adjusting your search terms or removing some filters.
            </EmptyStateText>
          </EmptyState>
        </Section>
      )}

      <QuickViewModal
        isOpen={!!(quickViewResult || quickViewPassage)}
        onClose={closeQuickView}
        result={quickViewResult}
        passage={quickViewPassage}
        query={query}
      />
    </ResultsContainer>
  );
};

export default SearchResults;