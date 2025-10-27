import React, { useState, useRef, useEffect } from 'react';
import styled from 'styled-components';
import { motion, AnimatePresence } from 'framer-motion';
import { FiMessageCircle, FiX, FiSend, FiUser, FiCpu, FiBookOpen, FiChevronDown, FiChevronUp } from 'react-icons/fi';
import ReactMarkdown from 'react-markdown';
import { Resizable } from 're-resizable';
import { chatAPI } from '../services/api';

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

const ChatButton = styled(motion.button)`
  position: fixed;
  bottom: 24px;
  right: 24px;
  width: 60px;
  height: 60px;
  border-radius: 50%;
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  border: none;
  color: white;
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  box-shadow: 0 8px 25px rgba(102, 126, 234, 0.3);
  z-index: 1000;
  transition: all 0.3s ease;

  &:hover {
    transform: translateY(-2px);
    box-shadow: 0 12px 35px rgba(102, 126, 234, 0.4);
  }
`;

const ChatWindowWrapper = styled.div`
  position: fixed;
  bottom: 100px;
  right: 24px;
  z-index: 1000;
  
  @media (max-width: 768px) {
    width: calc(100vw - 48px);
    height: calc(100vh - 150px);
    right: 24px;
    left: 24px;
  }
`;

const ChatWindow = styled(motion.div)`
  width: 100%;
  height: 100%;
  background: white;
  border-radius: 16px;
  box-shadow: 0 20px 60px rgba(0, 0, 0, 0.2);
  display: flex;
  flex-direction: column;
  overflow: hidden;
`;

const ChatHeader = styled.div`
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  color: white;
  padding: 16px 20px;
  display: flex;
  align-items: center;
  justify-content: space-between;
`;

const ChatTitle = styled.h3`
  font-size: 16px;
  font-weight: 600;
  display: flex;
  align-items: center;
  gap: 8px;
`;

const CloseButton = styled.button`
  background: none;
  border: none;
  color: white;
  cursor: pointer;
  padding: 4px;
  border-radius: 4px;
  display: flex;
  align-items: center;
  justify-content: center;
  transition: background-color 0.2s ease;

  &:hover {
    background: rgba(255, 255, 255, 0.2);
  }
`;

const ChatMessages = styled.div`
  flex: 1;
  padding: 16px;
  overflow-y: auto;
  display: flex;
  flex-direction: column;
  gap: 12px;
  background: #f8f9fa;
`;

const Message = styled(motion.div)`
  display: flex;
  align-items: flex-start;
  gap: 8px;
  max-width: 85%;
  align-self: ${props => props.isUser ? 'flex-end' : 'flex-start'};
`;

const MessageAvatar = styled.div`
  width: 32px;
  height: 32px;
  border-radius: 50%;
  background: ${props => props.isUser ? '#667eea' : '#e5e7eb'};
  color: ${props => props.isUser ? 'white' : '#666'};
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
`;

const MessageBubble = styled.div`
  background: ${props => props.isUser ? '#667eea' : 'white'};
  color: ${props => props.isUser ? 'white' : '#333'};
  padding: 12px 16px;
  border-radius: 16px;
  border-bottom-${props => props.isUser ? 'right' : 'left'}-radius: 4px;
  font-size: 14px;
  line-height: 1.4;
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.1);
  word-wrap: break-word;
  max-width: 100%;
`;

const FormattedMessage = styled.div`
  line-height: 1.6;
  color: #2c3e50;
  
  /* Headings with hierarchy */
  h1, h2, h3, h4, h5, h6 {
    color: #1a202c;
    font-weight: 600;
    margin-top: 16px;
    margin-bottom: 8px;
    line-height: 1.3;
  }

  h1 {
    font-size: 1.5em;
    border-bottom: 2px solid #667eea;
    padding-bottom: 6px;
  }

  h2 {
    font-size: 1.3em;
    border-bottom: 1px solid #e2e8f0;
    padding-bottom: 4px;
  }

  h3 {
    font-size: 1.15em;
    color: #667eea;
  }

  h4 {
    font-size: 1.05em;
  }

  h5, h6 {
    font-size: 1em;
  }

  /* Paragraphs */
  p {
    margin: 8px 0;
    line-height: 1.6;
  }

  /* Lists */
  ul, ol {
    margin: 12px 0;
    padding-left: 24px;
  }

  li {
    margin-bottom: 6px;
    line-height: 1.5;
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
    border-radius: 3px;
    padding: 2px 5px;
    font-family: 'Monaco', 'Menlo', 'Ubuntu Mono', monospace;
    font-size: 0.9em;
    color: #e53e3e;
  }

  pre {
    background: #2d3748;
    color: #f7fafc;
    border-radius: 6px;
    padding: 12px;
    overflow-x: auto;
    margin: 12px 0;
    
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
    padding-left: 12px;
    margin: 12px 0;
    color: #4a5568;
    font-style: italic;
    background: #f7fafc;
    padding: 10px 12px;
    border-radius: 0 6px 6px 0;
  }

  /* Superscript (citations) */
  sup {
    font-size: 0.75em;
    color: #667eea;
    font-weight: 600;
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
    margin: 16px 0;
  }

  /* Tables */
  table {
    width: 100%;
    border-collapse: collapse;
    margin: 12px 0;
    font-size: 0.9em;
  }

  th, td {
    border: 1px solid #e2e8f0;
    padding: 8px;
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

const CitationsContainer = styled.div`
  margin-top: 12px;
  padding-top: 12px;
  border-top: 1px solid #e1e5e9;
`;

const CitationsHeader = styled.div`
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 8px;
`;

const CitationsTitle = styled.h4`
  font-size: 12px;
  font-weight: 600;
  color: #666;
  margin: 0;
  display: flex;
  align-items: center;
  gap: 4px;
`;

const ExpandButton = styled.button`
  background: none;
  border: none;
  color: #667eea;
  cursor: pointer;
  font-size: 11px;
  padding: 2px 6px;
  border-radius: 4px;
  transition: background-color 0.2s ease;

  &:hover {
    background: #f0f0f0;
  }
`;

const CitationsList = styled.div`
  display: flex;
  flex-direction: column;
  gap: 6px;
`;

const CitationItem = styled.div`
  background: #f8f9fa;
  padding: 8px 10px;
  border-radius: 6px;
  border-left: 3px solid #667eea;
`;

const CitationTitle = styled.div`
  font-size: 12px;
  font-weight: 500;
  color: #333;
  margin-bottom: 2px;
`;

const CitationMeta = styled.div`
  font-size: 10px;
  color: #666;
  display: flex;
  align-items: center;
  gap: 8px;
`;

const ProjectBadge = styled.span`
  background: ${props => getProjectColor(props.project)};
  color: white;
  padding: 2px 6px;
  border-radius: 4px;
  font-size: 9px;
  font-weight: 500;
  text-transform: uppercase;
`;

const MessageContent = styled.div`
  /* Content is now handled by manual truncation in the component */
`;

const ChatInput = styled.div`
  padding: 16px;
  border-top: 1px solid #e1e5e9;
  background: white;
`;

const InputContainer = styled.div`
  display: flex;
  gap: 8px;
  align-items: flex-end;
`;

const MessageInput = styled.textarea`
  flex: 1;
  border: 1px solid #e1e5e9;
  border-radius: 12px;
  padding: 12px 16px;
  font-size: 14px;
  resize: none;
  outline: none;
  min-height: 20px;
  max-height: 100px;
  font-family: inherit;
  transition: border-color 0.2s ease;

  &:focus {
    border-color: #667eea;
  }

  &::placeholder {
    color: #999;
  }
`;

const SendButton = styled(motion.button)`
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  border: none;
  border-radius: 50%;
  width: 40px;
  height: 40px;
  color: white;
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  transition: all 0.2s ease;

  &:hover {
    transform: scale(1.05);
  }

  &:disabled {
    opacity: 0.5;
    cursor: not-allowed;
    transform: none;
  }
`;

const TypingIndicator = styled(motion.div)`
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 12px 16px;
  background: white;
  border-radius: 16px;
  border-bottom-left-radius: 4px;
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.1);
  align-self: flex-start;
  max-width: 85%;
`;

const TypingDots = styled.div`
  display: flex;
  gap: 4px;
  
  span {
    width: 6px;
    height: 6px;
    background: #999;
    border-radius: 50%;
    animation: typing 1.4s infinite ease-in-out;
    
    &:nth-child(1) { animation-delay: -0.32s; }
    &:nth-child(2) { animation-delay: -0.16s; }
  }
  
  @keyframes typing {
    0%, 80%, 100% {
      transform: scale(0);
      opacity: 0.5;
    }
    40% {
      transform: scale(1);
      opacity: 1;
    }
  }
`;

const BackendIndicator = styled.div`
  font-size: 11px;
  color: #666;
  text-align: center;
  padding: 8px;
  background: #f0f0f0;
  border-top: 1px solid #e1e5e9;
`;

const ChatBot = ({ isOpen, onToggle, backendMode, sessionId }) => {
  const [messages, setMessages] = useState([
    {
      id: 1,
      text: "Hi! I'm your AI assistant. Ask me anything about the content in our knowledge base.",
      isUser: false,
      timestamp: new Date()
    }
  ]);
  const [inputValue, setInputValue] = useState('');
  const [isTyping, setIsTyping] = useState(false);
  const [currentSessionId, setCurrentSessionId] = useState(sessionId);
  const [expandedMessages, setExpandedMessages] = useState(new Set());
  const [expandedCitations, setExpandedCitations] = useState(new Set());
  const [chatSize, setChatSize] = useState(() => {
    const saved = localStorage.getItem('chatbot-size');
    return saved ? JSON.parse(saved) : { width: 450, height: 650 };
  });
  const messagesEndRef = useRef(null);
  const inputRef = useRef(null);

  const scrollToBottom = () => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  };

  useEffect(() => {
    scrollToBottom();
  }, [messages, isTyping]);

  useEffect(() => {
    if (isOpen && inputRef.current) {
      inputRef.current.focus();
    }
  }, [isOpen]);

  // Update currentSessionId when sessionId prop changes (backend switch)
  useEffect(() => {
    setCurrentSessionId(sessionId);
  }, [sessionId]);

  const handleSendMessage = async () => {
    if (!inputValue.trim() || isTyping) return;

    const userMessage = {
      id: Date.now(),
      text: inputValue.trim(),
      isUser: true,
      timestamp: new Date()
    };

    setMessages(prev => [...prev, userMessage]);
    setInputValue('');
    setIsTyping(true);

    try {
      const response = await chatAPI(
        userMessage.text,
        backendMode === 'coveo' ? null : currentSessionId,
        backendMode
      );

      // Update session ID if provided (for multi-turn conversations)
      if (response.sessionId && backendMode !== 'coveo') {
        setCurrentSessionId(response.sessionId);
      }

      const botText = response.response || response.answer || response.answerText || 'I apologize, but I could not generate a response.';

      // Extract sources from various possible response structures
      let sources = [];
      
      // Debug logging for response structure
      console.log('🔍 Chat API response structure:', {
        response: response,
        hasSources: !!response.sources,
        hasCitations: !!response.citations,
        hasResults: !!(response.results && response.results.length > 0),
        responseKeys: Object.keys(response || {}),
        citationsStructure: response.citations ? response.citations.map(c => Object.keys(c)) : []
      });
      
      if (response.sources) {
        sources = response.sources;
      } else if (response.citations) {
        sources = response.citations.map(citation => ({
          title: citation.title,
          url: citation.uri || citation.clickUri || citation.clickableuri,
          project: citation.project
        }));
      } else if (response.results && response.results.length > 0) {
        // Extract sources from search results if available
        sources = response.results.slice(0, 5).map(result => ({
          title: result.title,
          url: result.clickUri,
          project: result.raw?.project
        }));
      }

      const botMessage = {
        id: Date.now() + 1,
        text: botText,
        isUser: false,
        timestamp: new Date(),
        sources: sources,
        totalResults: response.totalResults || sources.length || 0
      };

      setMessages(prev => [...prev, botMessage]);
    } catch (error) {
      console.error('Chat error:', error);
      const errorMessage = {
        id: Date.now() + 1,
        text: 'I apologize, but I encountered an error. Please try again.',
        isUser: false,
        timestamp: new Date()
      };
      setMessages(prev => [...prev, errorMessage]);
    } finally {
      setIsTyping(false);
    }
  };

  const handleKeyPress = (e) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      handleSendMessage();
    }
  };

  const toggleMessageExpansion = (messageId) => {
    setExpandedMessages(prev => {
      const newSet = new Set(prev);
      if (newSet.has(messageId)) {
        newSet.delete(messageId);
      } else {
        newSet.add(messageId);
      }
      return newSet;
    });
  };

  const toggleCitationsExpansion = (messageId) => {
    setExpandedCitations(prev => {
      const newSet = new Set(prev);
      if (newSet.has(messageId)) {
        newSet.delete(messageId);
      } else {
        newSet.add(messageId);
      }
      return newSet;
    });
  };

  const getBackendDisplayName = () => {
    const names = {
      coveo: 'Coveo AI',
      bedrockAgent: 'Bedrock Agent',
      coveoMCP: 'Coveo MCP'
    };
    return names[backendMode] || backendMode;
  };

  const handleResize = (e, direction, ref, delta) => {
    const newSize = {
      width: ref.offsetWidth,
      height: ref.offsetHeight
    };
    setChatSize(newSize);
    localStorage.setItem('chatbot-size', JSON.stringify(newSize));
  };

  return (
    <>
      <ChatButton
        onClick={onToggle}
        whileHover={{ scale: 1.1 }}
        whileTap={{ scale: 0.9 }}
        animate={{ rotate: isOpen ? 180 : 0 }}
      >
        {isOpen ? <FiX size={24} /> : <FiMessageCircle size={24} />}
      </ChatButton>

      <AnimatePresence>
        {isOpen && (
          <ChatWindowWrapper>
            <Resizable
              size={chatSize}
              onResizeStop={handleResize}
              minWidth={350}
              minHeight={400}
              maxWidth={800}
              maxHeight={900}
              enable={{
                top: true,
                right: false,
                bottom: false,
                left: true,
                topRight: false,
                bottomRight: false,
                bottomLeft: false,
                topLeft: true
              }}
            >
              <ChatWindow
                initial={{ opacity: 0, scale: 0.8, y: 20 }}
                animate={{ opacity: 1, scale: 1, y: 0 }}
                exit={{ opacity: 0, scale: 0.8, y: 20 }}
                transition={{ duration: 0.3, ease: 'easeOut' }}
              >
                <ChatHeader>
                  <ChatTitle>
                    <FiCpu size={16} />
                    AI Assistant
                  </ChatTitle>
                  <CloseButton onClick={onToggle}>
                    <FiX size={16} />
                  </CloseButton>
                </ChatHeader>

            <ChatMessages>
              {messages.map((message) => {
                const isExpanded = expandedMessages.has(message.id);
                const areCitationsExpanded = expandedCitations.has(message.id);
                const hasLongContent = message.text && message.text.length > 400;
                const hasCitations = message.sources && message.sources.length > 0;

                return (
                  <Message
                    key={message.id}
                    isUser={message.isUser}
                    initial={{ opacity: 0, y: 10 }}
                    animate={{ opacity: 1, y: 0 }}
                    transition={{ duration: 0.3 }}
                  >
                    <MessageAvatar isUser={message.isUser}>
                      {message.isUser ? <FiUser size={16} /> : <FiCpu size={16} />}
                    </MessageAvatar>
                    <MessageBubble isUser={message.isUser}>
                      {message.isUser ? (
                        message.text
                      ) : (
                        <>
                          <MessageContent isExpanded={isExpanded}>
                            <FormattedMessage>
                              <ReactMarkdown>
                                {isExpanded ? message.text : (hasLongContent ? message.text.substring(0, 400) + '...' : message.text)}
                              </ReactMarkdown>
                            </FormattedMessage>
                          </MessageContent>
                          
                          {hasLongContent && !message.isUser && (
                            <ExpandButton 
                              onClick={() => toggleMessageExpansion(message.id)}
                              style={{ marginTop: '8px', display: 'flex', alignItems: 'center', gap: '4px' }}
                            >
                              {isExpanded ? (
                                <>Show Less <FiChevronUp size={12} /></>
                              ) : (
                                <>Show More <FiChevronDown size={12} /></>
                              )}
                            </ExpandButton>
                          )}

                          {hasCitations && (
                            <CitationsContainer>
                              <CitationsHeader>
                                <CitationsTitle>
                                  <FiBookOpen size={12} />
                                  Sources ({message.sources.length})
                                </CitationsTitle>
                                <ExpandButton onClick={() => toggleCitationsExpansion(message.id)}>
                                  {areCitationsExpanded ? (
                                    <>Hide <FiChevronUp size={10} /></>
                                  ) : (
                                    <>Show <FiChevronDown size={10} /></>
                                  )}
                                </ExpandButton>
                              </CitationsHeader>
                              
                              {areCitationsExpanded && (
                                <CitationsList>
                                  {message.sources.map((source, index) => (
                                    <CitationItem key={index}>
                                      <CitationTitle>{source.title}</CitationTitle>
                                      <CitationMeta>
                                        {source.project && (
                                          <ProjectBadge project={source.project}>
                                            {source.project}
                                          </ProjectBadge>
                                        )}
                                        {source.url && (
                                          <a 
                                            href={source.url} 
                                            target="_blank" 
                                            rel="noopener noreferrer"
                                            style={{ fontSize: '10px', color: '#667eea' }}
                                          >
                                            View Source
                                          </a>
                                        )}
                                      </CitationMeta>
                                    </CitationItem>
                                  ))}
                                </CitationsList>
                              )}
                            </CitationsContainer>
                          )}
                        </>
                      )}
                    </MessageBubble>
                  </Message>
                );
              })}

              {isTyping && (
                <Message isUser={false}>
                  <MessageAvatar isUser={false}>
                    <FiCpu size={16} />
                  </MessageAvatar>
                  <TypingIndicator
                    initial={{ opacity: 0, y: 10 }}
                    animate={{ opacity: 1, y: 0 }}
                    exit={{ opacity: 0, y: -10 }}
                  >
                    <TypingDots>
                      <span></span>
                      <span></span>
                      <span></span>
                    </TypingDots>
                  </TypingIndicator>
                </Message>
              )}
              <div ref={messagesEndRef} />
            </ChatMessages>

            <ChatInput>
              <InputContainer>
                <MessageInput
                  ref={inputRef}
                  value={inputValue}
                  onChange={(e) => setInputValue(e.target.value)}
                  onKeyPress={handleKeyPress}
                  placeholder="Ask me anything..."
                  rows={1}
                  disabled={isTyping}
                />
                <SendButton
                  onClick={handleSendMessage}
                  disabled={!inputValue.trim() || isTyping}
                  whileHover={{ scale: 1.05 }}
                  whileTap={{ scale: 0.95 }}
                >
                  <FiSend size={16} />
                </SendButton>
              </InputContainer>
            </ChatInput>

                <BackendIndicator>
                  Powered by {getBackendDisplayName()}
                  {backendMode !== 'coveo' && ` • Session: ${currentSessionId?.slice(-8)}`}
                </BackendIndicator>
              </ChatWindow>
            </Resizable>
          </ChatWindowWrapper>
        )}
      </AnimatePresence>
    </>
  );
};

export default ChatBot;