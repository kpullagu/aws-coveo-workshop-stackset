import React, { useState, useEffect } from 'react';
import styled from 'styled-components';
import { motion, AnimatePresence } from 'framer-motion';
import { FiX, FiExternalLink, FiCalendar, FiTag, FiMapPin } from 'react-icons/fi';
import { format } from 'date-fns';
import { htmlAPI } from '../services/api';

const ModalOverlay = styled(motion.div)`
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  background: rgba(0, 0, 0, 0.7);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 2000;
  padding: 20px;
`;

const ModalContent = styled(motion.div)`
  background: white;
  border-radius: 16px;
  max-width: 800px;
  max-height: 90vh;
  width: 100%;
  overflow: hidden;
  box-shadow: 0 20px 60px rgba(0, 0, 0, 0.3);
`;

const ModalHeader = styled.div`
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  padding: 24px;
  border-bottom: 1px solid #e1e5e9;
  background: #f8f9fa;
`;

const ModalTitle = styled.h2`
  font-size: 20px;
  font-weight: 600;
  color: #333;
  margin: 0;
  line-height: 1.3;
  flex: 1;
  margin-right: 16px;
`;

const CloseButton = styled.button`
  background: none;
  border: none;
  color: #666;
  cursor: pointer;
  padding: 8px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  transition: all 0.2s ease;

  &:hover {
    background: #e9ecef;
    color: #333;
  }
`;

const ModalBody = styled.div`
  padding: 24px;
  overflow-y: auto;
  max-height: calc(90vh - 140px);
`;

const MetaInfo = styled.div`
  display: flex;
  flex-wrap: wrap;
  gap: 12px;
  margin-bottom: 20px;
  padding-bottom: 16px;
  border-bottom: 1px solid #f0f0f0;
`;

const MetaItem = styled.div`
  display: flex;
  align-items: center;
  gap: 6px;
  font-size: 13px;
  color: #666;
  background: #f8f9fa;
  padding: 6px 10px;
  border-radius: 6px;
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

const ContentSection = styled.div`
  margin-bottom: 20px;
`;

const SectionTitle = styled.h3`
  font-size: 16px;
  font-weight: 600;
  color: #333;
  margin-bottom: 12px;
`;

const ContentText = styled.div`
  font-size: 14px;
  line-height: 1.6;
  color: #444;
  
  p {
    margin-bottom: 12px;
  }

  /* Style HTML content from data field */
  h1, h2, h3, h4, h5, h6 {
    color: #333;
    margin: 16px 0 8px 0;
    font-weight: 600;
  }

  h1 { font-size: 18px; }
  h2 { font-size: 16px; }
  h3 { font-size: 15px; }
  h4, h5, h6 { font-size: 14px; }

  ul, ol {
    margin: 8px 0;
    padding-left: 20px;
  }

  li {
    margin-bottom: 4px;
  }

  a {
    color: #667eea;
    text-decoration: none;
    
    &:hover {
      text-decoration: underline;
    }
  }

  blockquote {
    border-left: 3px solid #667eea;
    margin: 12px 0;
    padding-left: 12px;
    color: #666;
    font-style: italic;
  }

  code {
    background: #f5f5f5;
    padding: 2px 4px;
    border-radius: 3px;
    font-family: monospace;
    font-size: 13px;
  }

  pre {
    background: #f5f5f5;
    padding: 12px;
    border-radius: 6px;
    overflow-x: auto;
    margin: 12px 0;
  }

  table {
    border-collapse: collapse;
    width: 100%;
    margin: 12px 0;
  }

  th, td {
    border: 1px solid #ddd;
    padding: 8px;
    text-align: left;
  }

  th {
    background-color: #f8f9fa;
    font-weight: 600;
  }

  img {
    max-width: 100%;
    height: auto;
    border-radius: 4px;
    margin: 8px 0;
  }
`;

const LoadingContainer = styled.div`
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 40px;
  color: #666;
  gap: 12px;
`;

const LoadingSpinner = styled(motion.div)`
  width: 20px;
  height: 20px;
  border: 2px solid #e1e5e9;
  border-top: 2px solid #667eea;
  border-radius: 50%;
  animation: spin 1s linear infinite;

  @keyframes spin {
    0% { transform: rotate(0deg); }
    100% { transform: rotate(360deg); }
  }
`;

const Summary = styled.div`
  background: #f8f9fa;
  padding: 16px;
  border-radius: 8px;
  border-left: 4px solid #667eea;
  margin-bottom: 20px;
  font-size: 14px;
  line-height: 1.5;
  color: #555;
`;

const ViewOriginalButton = styled.a`
  display: inline-flex;
  align-items: center;
  gap: 8px;
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  color: white;
  padding: 10px 16px;
  border-radius: 8px;
  text-decoration: none;
  font-size: 14px;
  font-weight: 500;
  transition: all 0.3s ease;

  &:hover {
    transform: translateY(-1px);
    box-shadow: 0 4px 15px rgba(102, 126, 234, 0.3);
  }
`;

const SourceLinkContainer = styled.div`
  margin-top: 16px;
  padding-top: 16px;
  border-top: 1px solid #e1e5e9;
  display: flex;
  align-items: center;
  justify-content: space-between;
  flex-wrap: wrap;
  gap: 12px;
`;

const SourceInfo = styled.div`
  font-size: 12px;
  color: #666;
  display: flex;
  align-items: center;
  gap: 8px;
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

const QuickViewModal = ({ isOpen, onClose, result, passage, query }) => {
  const [htmlContent, setHtmlContent] = useState(null);
  const [isLoadingHtml, setIsLoadingHtml] = useState(false);
  const [htmlError, setHtmlError] = useState(null);
  
  const content = result || passage;

  // Fetch HTML content when modal opens for both search results and passages
  useEffect(() => {
    const itemToFetch = result || passage;
    // Try multiple possible uniqueId fields for different data structures
    // Prioritize direct fields first since uniqueId is in the results section
    const uniqueId = itemToFetch?.uniqueId || 
                     itemToFetch?.uniqueid ||
                     itemToFetch?.id ||
                     itemToFetch?.raw?.uniqueId ||
                     itemToFetch?.raw?.uniqueid ||
                     itemToFetch?.document?.uniqueId ||
                     itemToFetch?.document?.uniqueid ||
                     itemToFetch?.raw?.permanentid ||
                     itemToFetch?.permanentid ||
                     itemToFetch?.uri ||
                     itemToFetch?.clickUri;
    
    if (isOpen && itemToFetch && uniqueId) {
      setIsLoadingHtml(true);
      setHtmlError(null);
      setHtmlContent(null);
      
      console.log('✅ UniqueId found:', uniqueId, 'for item:', itemToFetch.title);
      console.log('🔍 Direct field check:', {
        'itemToFetch.uniqueId': itemToFetch.uniqueId,
        'itemToFetch.uniqueid': itemToFetch.uniqueid,
        'itemToFetch.id': itemToFetch.id
      });
      
      console.log('🔍 Fetching HTML content:', { 
        type: result ? 'search result' : 'passage',
        query: query || '(empty)', 
        uniqueId, 
        title: itemToFetch.title || itemToFetch.document?.title,
        itemStructure: Object.keys(itemToFetch),
        hasQuery: !!query,
        uniqueIdSource: itemToFetch?.uniqueId ? 'uniqueId' : 
                       itemToFetch?.uniqueid ? 'uniqueid' : 
                       itemToFetch?.id ? 'id' : 'other'
      });
      
      htmlAPI(query || '', uniqueId)
        .then((response) => {
          // Handle both direct HTML string and object with html property
          const htmlData = typeof response === 'string' ? response : response.html;
          setHtmlContent(htmlData);
        })
        .catch((error) => {
          console.error('❌ Failed to fetch HTML content:', {
            error: error,
            errorMessage: error.message,
            uniqueId: uniqueId,
            query: query || '(empty)',
            title: itemToFetch.title
          });
          setHtmlError(error.message);
          // Set a fallback message instead of just error
          setHtmlContent(null); // This will trigger the fallback content display
        })
        .finally(() => {
          setIsLoadingHtml(false);
        });
    } else if (!isOpen) {
      // Reset state when modal closes
      setHtmlContent(null);
      setHtmlError(null);
      setIsLoadingHtml(false);
    } else if (isOpen && itemToFetch && !uniqueId) {
      console.warn('⚠️ No uniqueId found for item:', {
        item: itemToFetch,
        itemKeys: Object.keys(itemToFetch),
        rawKeys: itemToFetch.raw ? Object.keys(itemToFetch.raw) : 'no raw',
        documentKeys: itemToFetch.document ? Object.keys(itemToFetch.document) : 'no document',
        checkedFields: {
          uniqueId: itemToFetch?.uniqueId,
          'document.uniqueid': itemToFetch?.document?.uniqueid,
          'document.uniqueId': itemToFetch?.document?.uniqueId,
          id: itemToFetch?.id,
          uniqueid: itemToFetch?.uniqueid,
          'raw.uniqueid': itemToFetch?.raw?.uniqueid,
          'raw.uniqueId': itemToFetch?.raw?.uniqueId,
          'raw.permanentid': itemToFetch?.raw?.permanentid,
          permanentid: itemToFetch?.permanentid,
          uri: itemToFetch?.uri,
          clickUri: itemToFetch?.clickUri
        }
      });
    } else if (isOpen && !itemToFetch) {
      console.warn('⚠️ No item to fetch');
    }
  }, [isOpen, result, passage, query]);

  if (!content) return null;

  const handleOverlayClick = (e) => {
    if (e.target === e.currentTarget) {
      onClose();
    }
  };

  return (
    <AnimatePresence>
      {isOpen && (
        <ModalOverlay
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
          onClick={handleOverlayClick}
        >
          <ModalContent
            initial={{ opacity: 0, scale: 0.9, y: 20 }}
            animate={{ opacity: 1, scale: 1, y: 0 }}
            exit={{ opacity: 0, scale: 0.9, y: 20 }}
            transition={{ duration: 0.3, ease: 'easeOut' }}
          >
            <ModalHeader>
              <ModalTitle>{content.title || content.name || 'Content View'}</ModalTitle>
              <CloseButton onClick={onClose}>
                <FiX size={20} />
              </CloseButton>
            </ModalHeader>

            <ModalBody>
              <MetaInfo>
                {(content.raw?.project || content.project) && (
                  <ProjectBadge project={content.raw?.project || content.project}>
                    {content.raw?.project || content.project}
                  </ProjectBadge>
                )}
                {(content.raw?.date || content.date) && (
                  <MetaItem>
                    <FiCalendar size={12} />
                    {formatDate(content.raw?.date || content.date)}
                  </MetaItem>
                )}
                {(content.raw?.documenttype || content.documenttype) && (
                  <MetaItem>
                    <FiTag size={12} />
                    {(content.raw?.documenttype || content.documenttype).replace(/_/g, ' ')}
                  </MetaItem>
                )}
                {((content.raw?.geo_lat && content.raw?.geo_lon) || (content.geo_lat && content.geo_lon)) && (
                  <MetaItem>
                    <FiMapPin size={12} />
                    Location Available
                  </MetaItem>
                )}
              </MetaInfo>

              {(content.raw?.summary || content.summary) && (
                <Summary>
                  <strong>Summary:</strong> {content.raw?.summary || content.summary}
                </Summary>
              )}

              <ContentSection>
                <SectionTitle>{passage ? 'Passage Content' : 'Content'}</SectionTitle>
                <ContentText>
                  {isLoadingHtml ? (
                    <LoadingContainer>
                      <LoadingSpinner />
                      Loading full content...
                    </LoadingContainer>
                  ) : htmlError ? (
                    <div>
                      <p style={{ color: '#e74c3c', marginBottom: '12px' }}>
                        Failed to load full content: {htmlError}
                      </p>
                      {/* Fallback to original content */}
                      {passage ? (
                        <p>{content.content || content.text || content.excerpt || 'No content available'}</p>
                      ) : (
                        <div dangerouslySetInnerHTML={{ 
                          __html: content.raw?.data || content.data || content.excerpt || content.content || content.text || 'No content available' 
                        }} />
                      )}
                    </div>
                  ) : htmlContent ? (
                    <div dangerouslySetInnerHTML={{ __html: htmlContent }} />
                  ) : (
                    // Fallback to original content if no HTML content
                    passage ? (
                      <p>{content.content || content.text || content.excerpt || 'No content available'}</p>
                    ) : (
                      <div dangerouslySetInnerHTML={{ 
                        __html: content.raw?.data || content.data || content.excerpt || content.content || content.text || 'No content available' 
                      }} />
                    )
                  )}
                </ContentText>
              </ContentSection>

              <SourceLinkContainer>
                <SourceInfo>
                  {passage ? (
                    <>
                      <span>📄 Passages from: {content.title || content.document?.title || 'Unknown Source'}</span>
                      {(content.project || content.document?.project) && (
                        <>
                          <span>•</span>
                          <ProjectBadge project={content.project || content.document?.project}>
                            {content.project || content.document?.project}
                          </ProjectBadge>
                        </>
                      )}
                    </>
                  ) : (
                    <>
                      <span>📄 Source: {content.title}</span>
                      {(content.raw?.project || content.project) && (
                        <>
                          <span>•</span>
                          <ProjectBadge project={content.raw?.project || content.project}>
                            {content.raw?.project || content.project}
                          </ProjectBadge>
                        </>
                      )}
                    </>
                  )}
                </SourceInfo>
                {(content.clickUri || content.uri || content.url || content.document?.clickableuri) && (
                  <ViewOriginalButton 
                    href={content.clickUri || content.uri || content.url || content.document?.clickableuri} 
                    target="_blank" 
                    rel="noopener noreferrer"
                  >
                    <FiExternalLink size={16} />
                    View Original {passage ? 'Source' : 'Article'}
                  </ViewOriginalButton>
                )}
              </SourceLinkContainer>
            </ModalBody>
          </ModalContent>
        </ModalOverlay>
      )}
    </AnimatePresence>
  );
};

export default QuickViewModal;