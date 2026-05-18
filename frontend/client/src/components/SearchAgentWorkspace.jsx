import { useEffect, useMemo, useRef, useState } from 'react';
import styled from 'styled-components';
import { motion } from 'framer-motion';
import ReactMarkdown from 'react-markdown';
import {
  FiCheck,
  FiChevronDown,
  FiCopy,
  FiExternalLink,
  FiSend,
  FiThumbsDown,
  FiThumbsUp
} from 'react-icons/fi';
import { useCoveoSearchAgent } from '../hooks/useCoveoSearchAgent';

const Workspace = styled.div`
  display: grid;
  gap: 24px;
  width: 100%;
`;

const Panel = styled.section`
  background: rgba(255, 255, 255, 0.95);
  backdrop-filter: blur(20px);
  border-radius: 16px;
  padding: 24px;
  box-shadow: 0 8px 32px rgba(0, 0, 0, 0.1);
`;

const Eyebrow = styled.div`
  color: #667eea;
  font-size: 12px;
  font-weight: 700;
  letter-spacing: 0.16em;
  text-transform: uppercase;
`;

const Title = styled.h2`
  color: #222;
  font-size: 28px;
  line-height: 1.2;
  margin-top: 8px;
`;

const Description = styled.p`
  color: #5f6673;
  line-height: 1.6;
  margin-top: 8px;
`;

const SearchForm = styled.form`
  display: grid;
  gap: 12px;
  grid-template-columns: minmax(0, 1fr) auto;
  margin-top: 20px;
`;

const Input = styled.input`
  border: 1px solid #dfe4ea;
  border-radius: 12px;
  color: #222;
  font-size: 16px;
  outline: none;
  padding: 14px 16px;

  &:focus {
    border-color: #667eea;
    box-shadow: 0 0 0 4px rgba(102, 126, 234, 0.12);
  }
`;

const Button = styled(motion.button)`
  align-items: center;
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  border: none;
  border-radius: 12px;
  color: white;
  cursor: pointer;
  display: inline-flex;
  font-weight: 700;
  gap: 8px;
  justify-content: center;
  min-height: 48px;
  padding: 0 18px;

  &:disabled {
    cursor: not-allowed;
    opacity: 0.55;
  }
`;

const Alert = styled.div`
  background: #fff5f5;
  border: 1px solid rgba(220, 38, 38, 0.18);
  border-radius: 12px;
  color: #7f1d1d;
  line-height: 1.5;
  padding: 14px 16px;
`;

const ConversationDivider = styled.hr`
  border: none;
  border-top: 1px solid rgba(31, 39, 71, 0.1);
  margin: 24px 0 20px 0;
`;

const ConversationHeader = styled.div`
  margin-bottom: 16px;
`;

const ConversationPanel = styled(Panel)`
  display: grid;
  gap: 18px;
`;

const Timeline = styled.div`
  display: grid;
  gap: 14px;
  position: relative;

  &:before {
    background: linear-gradient(180deg, rgba(102, 126, 234, 0.18), rgba(118, 75, 162, 0.1));
    bottom: 12px;
    content: '';
    left: 13px;
    position: absolute;
    top: 12px;
    width: 2px;
  }
`;

const Turn = styled.div`
  display: grid;
  gap: 10px;
  grid-template-columns: 28px minmax(0, 1fr);
  position: relative;
`;

const Marker = styled.span`
  align-items: center;
  background: white;
  border: 1px solid ${props => props.$pending ? 'rgba(102, 126, 234, 0.42)' : 'rgba(31, 39, 71, 0.16)'};
  border-radius: 50%;
  display: inline-flex;
  height: 28px;
  justify-content: center;
  margin-top: 2px;
  width: 28px;

  &:after {
    animation: ${props => props.$pending ? 'pulse 1.4s ease-in-out infinite' : 'none'};
    background: ${props => props.$pending ? '#667eea' : '#98a1b2'};
    border-radius: 50%;
    content: '';
    height: 8px;
    width: 8px;
  }
`;

const TurnCard = styled.div`
  background: white;
  border: 1px solid rgba(31, 39, 71, 0.08);
  border-radius: 16px;
  box-shadow: ${props => props.$active ? '0 12px 30px rgba(28, 35, 71, 0.08)' : 'none'};
  min-width: 0;
  overflow: hidden;
`;

const QuestionButton = styled.button`
  align-items: center;
  background: none;
  border: none;
  color: #1f2747;
  cursor: ${props => props.$collapsible ? 'pointer' : 'default'};
  display: flex;
  font-size: 15px;
  font-weight: 700;
  gap: 10px;
  justify-content: space-between;
  line-height: 1.5;
  padding: 14px 16px;
  text-align: left;
  width: 100%;

  span {
    flex: 1;
    min-width: 0;
    overflow-wrap: anywhere;
    word-break: break-word;
  }

  &:hover {
    background: ${props => props.$collapsible ? '#f7f8fb' : 'transparent'};
  }
`;

const AnswerArea = styled.div`
  border-top: 1px solid rgba(31, 39, 71, 0.08);
  display: grid;
  gap: 14px;
  min-width: 0;
  padding: 16px;
`;

const AnswerBody = styled.div`
  color: #263043;
  display: grid;
  gap: 12px;
  line-height: 1.7;
  min-width: 0;

  p, li, a, blockquote {
    overflow-wrap: anywhere;
    word-break: break-word;
  }

  pre, code {
    max-width: 100%;
    overflow-wrap: anywhere;
    word-break: break-word;
  }

  pre {
    white-space: pre-wrap;
  }

  p, ul, ol {
    margin: 0;
  }

  ul, ol {
    padding-left: 22px;
  }

  a {
    color: #667eea;
    font-weight: 600;
  }
`;

const Actions = styled.div`
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
  justify-content: flex-end;
`;

const IconButton = styled.button`
  align-items: center;
  background: ${props => props.$active ? 'rgba(102, 126, 234, 0.1)' : 'white'};
  border: 1px solid ${props => props.$active ? 'rgba(102, 126, 234, 0.28)' : 'rgba(31, 39, 71, 0.12)'};
  border-radius: 50%;
  color: ${props => props.$active ? '#667eea' : '#5f6673'};
  cursor: pointer;
  display: inline-flex;
  height: 36px;
  justify-content: center;
  width: 36px;

  &:hover {
    border-color: rgba(102, 126, 234, 0.38);
    color: #667eea;
  }
`;

const Citations = styled.div`
  background: #f7f8fb;
  border-radius: 14px;
  display: grid;
  gap: 10px;
  padding: 12px;
`;

const CitationList = styled.div`
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
`;

const Citation = styled.a`
  align-items: center;
  background: white;
  border: 1px solid rgba(31, 39, 71, 0.1);
  border-radius: 999px;
  color: #263043;
  display: inline-flex;
  font-size: 13px;
  font-weight: 600;
  gap: 6px;
  max-width: 100%;
  padding: 8px 12px;
  text-decoration: none;

  span {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  &:hover {
    border-color: #667eea;
    color: #667eea;
  }
`;

const FollowUpForm = styled.form`
  display: grid;
  gap: 12px;
  grid-template-columns: minmax(0, 1fr) auto;
`;

const Thinking = styled.div`
  align-items: center;
  color: #5f6673;
  display: inline-flex;
  font-weight: 700;
  gap: 8px;

  &:after {
    animation: spin 1s linear infinite;
    border: 2px solid rgba(102, 126, 234, 0.2);
    border-top-color: #667eea;
    border-radius: 50%;
    content: '';
    height: 16px;
    width: 16px;
  }
`;

function renderAnswerText(turn) {
  if (!turn.answer.trim()) {
    if (turn.cannotAnswer) {
      return 'The Search Agent could not produce a concise answer for this turn. Review the citations or try a more specific question.';
    }
    return '';
  }
  return turn.answer;
}

function GeneratedAnswerText({ turn }) {
  const text = renderAnswerText(turn);
  if (!text) return null;

  if (turn.answerContentFormat === 'text/markdown') {
    return (
      <AnswerBody>
        <ReactMarkdown>{text}</ReactMarkdown>
      </AnswerBody>
    );
  }

  return (
    <AnswerBody>
      {text.split(/\n{2,}/).map((paragraph, index) => (
        <p key={`${paragraph.slice(0, 24)}-${index}`}>{paragraph}</p>
      ))}
    </AnswerBody>
  );
}

function CopyButton({ answerId, answerText, onCopy }) {
  const [copied, setCopied] = useState(false);

  const handleCopy = async () => {
    if (!answerText.trim()) return;
    await navigator.clipboard.writeText(answerText);
    onCopy(answerId);
    setCopied(true);
    window.setTimeout(() => setCopied(false), 1800);
  };

  return (
    <IconButton $active={copied} aria-label="Copy answer" onClick={handleCopy} title={copied ? 'Copied' : 'Copy'} type="button">
      {copied ? <FiCheck /> : <FiCopy />}
    </IconButton>
  );
}

function AnswerActions({ turn, logCopyToClipboard, likeAnswer, dislikeAnswer }) {
  if (turn.isPending || !turn.answer) return null;

  return (
    <Actions>
      <CopyButton answerId={turn.answerId} answerText={turn.answer} onCopy={logCopyToClipboard} />
      <IconButton aria-label="Like answer" onClick={() => likeAnswer(turn.answerId)} title="Like" type="button">
        <FiThumbsUp />
      </IconButton>
      <IconButton aria-label="Dislike answer" onClick={() => dislikeAnswer(turn.answerId)} title="Dislike" type="button">
        <FiThumbsDown />
      </IconButton>
    </Actions>
  );
}

function AnswerCitations({ turn, logCitationClick }) {
  if (!turn.citations.length) return null;

  return (
    <Citations>
      <Eyebrow>Citations</Eyebrow>
      <CitationList>
        {turn.citations.map((citation) => (
          <Citation
            href={citation.clickUri || citation.uri}
            key={citation.id || `${citation.title}-${citation.uri}`}
            onClick={() => logCitationClick(citation, turn.answerId)}
            rel="noopener noreferrer"
            target="_blank"
            title={citation.title || citation.source || 'Referenced source'}
          >
            <span>{citation.title || citation.source || 'Referenced source'}</span>
            <FiExternalLink />
          </Citation>
        ))}
      </CitationList>
    </Citations>
  );
}

function resolveStepLabel(steps = []) {
  const name = steps.at(-1)?.name?.toLowerCase?.();
  if (name === 'searching') return 'Searching';
  if (name === 'retrieving') return 'Retrieving sources';
  if (name === 'answering') return 'Drafting answer';
  return name ? name.replace(/[_-]/g, ' ') : 'Thinking';
}

function buildTurns({ submittedQuery, answerState, followUpAnswers, pendingFollowUpQuestion }) {
  const turns = [];
  const rootAnswer = answerState?.answer || '';
  const rootError = answerState?.error?.message || '';

  if (submittedQuery) {
    turns.push({
      key: `root:${submittedQuery}`,
      question: submittedQuery,
      answer: rootAnswer,
      answerId: answerState?.answerId,
      answerContentFormat: answerState?.answerContentFormat,
      citations: answerState?.citations || [],
      cannotAnswer: Boolean(answerState?.cannotAnswer),
      errorMessage: rootError,
      isPending: Boolean((answerState?.isLoading || answerState?.isStreaming) && !rootAnswer && !answerState?.cannotAnswer),
      activityLabel: resolveStepLabel(answerState?.generationSteps)
    });
  }

  for (const followUp of followUpAnswers) {
    turns.push({
      key: `follow-up:${followUp.answerId || followUp.question}`,
      question: followUp.question,
      answer: followUp.answer || '',
      answerId: followUp.answerId,
      answerContentFormat: followUp.answerContentFormat,
      citations: followUp.citations || [],
      cannotAnswer: Boolean(followUp.cannotAnswer),
      errorMessage: followUp.error?.message || '',
      isPending: Boolean((followUp.isLoading || followUp.isStreaming) && !followUp.answer && !followUp.cannotAnswer && !followUp.error),
      activityLabel: resolveStepLabel(followUp.generationSteps)
    });
  }

  if (pendingFollowUpQuestion && !turns.some((turn) => turn.question === pendingFollowUpQuestion)) {
    turns.push({
      key: `pending:${pendingFollowUpQuestion}`,
      question: pendingFollowUpQuestion,
      answer: '',
      citations: [],
      cannotAnswer: false,
      isPending: true,
      activityLabel: 'Thinking'
    });
  }

  return turns;
}

export default function SearchAgentWorkspace({ initialQuery, onSearch }) {
  const [queryInput, setQueryInput] = useState(initialQuery || '');
  const [followUpInput, setFollowUpInput] = useState('');
  const [pendingFollowUpQuestion, setPendingFollowUpQuestion] = useState('');
  const [followUpError, setFollowUpError] = useState('');
  const [expandedArchived, setExpandedArchived] = useState({});
  const [showArchivedTurns, setShowArchivedTurns] = useState(false);
  const lastInitialQueryRef = useRef('');

  const {
    isReady,
    initializationError,
    answerState,
    submittedQuery,
    followUpAnswers,
    updateText,
    submitQuery,
    askFollowUp,
    logCitationClick,
    logCopyToClipboard,
    likeAnswer,
    dislikeAnswer
  } = useCoveoSearchAgent();

  useEffect(() => {
    const trimmed = (initialQuery || '').trim();
    if (!trimmed || trimmed === lastInitialQueryRef.current || !isReady) return;
    lastInitialQueryRef.current = trimmed;
    setQueryInput(trimmed);
    setPendingFollowUpQuestion('');
    setFollowUpError('');
    setExpandedArchived({});
    setShowArchivedTurns(false);
    submitQuery(trimmed);
  }, [initialQuery, isReady, submitQuery]);

  useEffect(() => {
    if (!pendingFollowUpQuestion) return;
    const matchingFollowUp = followUpAnswers.find((followUp) => followUp.question === pendingFollowUpQuestion);
    if (matchingFollowUp && (matchingFollowUp.answer || matchingFollowUp.cannotAnswer || matchingFollowUp.error)) {
      setPendingFollowUpQuestion('');
    }
  }, [followUpAnswers, pendingFollowUpQuestion]);

  const turns = useMemo(
    () => buildTurns({ submittedQuery, answerState, followUpAnswers, pendingFollowUpQuestion }),
    [answerState, followUpAnswers, pendingFollowUpQuestion, submittedQuery]
  );
  const activeTurn = turns.at(-1);
  const archivedTurns = turns.slice(0, -1);
  const shouldGroupArchivedTurns = turns.length > 2;
  const hasRootAnswer = Boolean(answerState?.answer || answerState?.cannotAnswer);

  const handleSearchSubmit = (event) => {
    event.preventDefault();
    const trimmed = queryInput.trim();
    if (!trimmed) return;
    setPendingFollowUpQuestion('');
    setFollowUpError('');
    setExpandedArchived({});
    setShowArchivedTurns(false);
    lastInitialQueryRef.current = trimmed;
    submitQuery(trimmed);
    onSearch?.(trimmed, {});
  };

  const handleFollowUpSubmit = (event) => {
    event.preventDefault();
    const trimmed = followUpInput.trim();
    if (!trimmed) return;
    setFollowUpInput('');
    try {
      const submitted = askFollowUp(trimmed);
      if (submitted) {
        setPendingFollowUpQuestion(trimmed);
        setFollowUpError('');
      } else {
        setFollowUpError('Follow-up answers are not enabled for this Search Agent response. Start a new Search Agent question instead.');
      }
    } catch (error) {
      console.error('Search Agent follow-up failed:', error);
      setPendingFollowUpQuestion('');
      setFollowUpError(error instanceof Error ? error.message : 'Unable to submit the follow-up question.');
    }
  };

  return (
    <Workspace>
      <Panel>
        <Eyebrow>Coveo Search Agent</Eyebrow>
        <Title>Native conversational answers grounded in Coveo</Title>
        <Description>
          Ask a question and continue with follow-ups. This mode uses Coveo Headless and the Search Agent directly, without an AWS agent runtime or external memory layer.
        </Description>
        {initializationError ? <Alert>{initializationError}</Alert> : null}
        <SearchForm onSubmit={handleSearchSubmit}>
          <Input
            onChange={(event) => {
              setQueryInput(event.target.value);
              updateText(event.target.value);
            }}
            placeholder="Ask a financial knowledge question"
            value={queryInput}
          />
          <Button disabled={!isReady || !queryInput.trim()} type="submit" whileHover={{ scale: 1.02 }} whileTap={{ scale: 0.98 }}>
            <FiSend /> Ask
          </Button>
        </SearchForm>

        {turns.length ? (
          <>
            <ConversationDivider />
            <ConversationHeader>
              <Eyebrow>Generated answer and follow-ups</Eyebrow>
            </ConversationHeader>
            <Timeline>
            {archivedTurns.length ? (
              shouldGroupArchivedTurns ? (
                <Turn>
                  <Marker />
                  <TurnCard>
                    <QuestionButton $collapsible onClick={() => setShowArchivedTurns((current) => !current)} type="button">
                      <span>{showArchivedTurns ? 'Hide previous questions' : `Show ${archivedTurns.length} previous questions`}</span>
                      <FiChevronDown style={{ transform: showArchivedTurns ? 'rotate(180deg)' : 'rotate(0deg)' }} />
                    </QuestionButton>
                    {showArchivedTurns ? (
                      <AnswerArea>
                        <Timeline>
                          {archivedTurns.map((turn) => {
                            const expanded = Boolean(expandedArchived[turn.key]);
                            return (
                              <Turn key={turn.key}>
                                <Marker />
                                <TurnCard>
                                  <QuestionButton
                                    $collapsible
                                    onClick={() => setExpandedArchived((current) => ({ ...current, [turn.key]: !current[turn.key] }))}
                                    type="button"
                                  >
                                    <span>{turn.question}</span>
                                    <FiChevronDown style={{ transform: expanded ? 'rotate(180deg)' : 'rotate(0deg)' }} />
                                  </QuestionButton>
                                  {expanded ? (
                                    <AnswerArea>
                                      <GeneratedAnswerText turn={turn} />
                                      {turn.errorMessage ? <Alert>{turn.errorMessage}</Alert> : null}
                                      <AnswerActions
                                        dislikeAnswer={dislikeAnswer}
                                        likeAnswer={likeAnswer}
                                        logCopyToClipboard={logCopyToClipboard}
                                        turn={turn}
                                      />
                                      <AnswerCitations logCitationClick={logCitationClick} turn={turn} />
                                    </AnswerArea>
                                  ) : null}
                                </TurnCard>
                              </Turn>
                            );
                          })}
                        </Timeline>
                      </AnswerArea>
                    ) : null}
                  </TurnCard>
                </Turn>
              ) : (
                archivedTurns.map((turn) => {
                  const expanded = Boolean(expandedArchived[turn.key]);
                  return (
                    <Turn key={turn.key}>
                      <Marker />
                      <TurnCard>
                        <QuestionButton
                          $collapsible
                          onClick={() => setExpandedArchived((current) => ({ ...current, [turn.key]: !current[turn.key] }))}
                          type="button"
                        >
                          <span>{turn.question}</span>
                          <FiChevronDown style={{ transform: expanded ? 'rotate(180deg)' : 'rotate(0deg)' }} />
                        </QuestionButton>
                        {expanded ? (
                          <AnswerArea>
                            <GeneratedAnswerText turn={turn} />
                            {turn.errorMessage ? <Alert>{turn.errorMessage}</Alert> : null}
                            <AnswerActions
                              dislikeAnswer={dislikeAnswer}
                              likeAnswer={likeAnswer}
                              logCopyToClipboard={logCopyToClipboard}
                              turn={turn}
                            />
                            <AnswerCitations logCitationClick={logCitationClick} turn={turn} />
                          </AnswerArea>
                        ) : null}
                      </TurnCard>
                    </Turn>
                  );
                })
              )
            ) : null}

            {activeTurn ? (
              <Turn>
                <Marker $pending={activeTurn.isPending} />
                <TurnCard $active>
                  <QuestionButton type="button">
                    <span>{activeTurn.question}</span>
                  </QuestionButton>
                  <AnswerArea>
                    {activeTurn.isPending ? <Thinking>{activeTurn.activityLabel || 'Thinking'}</Thinking> : <GeneratedAnswerText turn={activeTurn} />}
                    {activeTurn.errorMessage ? <Alert>{activeTurn.errorMessage}</Alert> : null}
                    <AnswerActions
                      dislikeAnswer={dislikeAnswer}
                      likeAnswer={likeAnswer}
                      logCopyToClipboard={logCopyToClipboard}
                      turn={activeTurn}
                    />
                    <AnswerCitations logCitationClick={logCitationClick} turn={activeTurn} />
                  </AnswerArea>
                </TurnCard>
              </Turn>
            ) : null}
          </Timeline>

          {hasRootAnswer ? (
            <>
              {followUpError ? <Alert>{followUpError}</Alert> : null}
              <FollowUpForm onSubmit={handleFollowUpSubmit}>
                <Input
                  onChange={(event) => setFollowUpInput(event.target.value)}
                  placeholder="Ask a follow-up question"
                  value={followUpInput}
                />
                <Button disabled={!followUpInput.trim()} type="submit" whileHover={{ scale: 1.02 }} whileTap={{ scale: 0.98 }}>
                  Ask follow-up
                </Button>
              </FollowUpForm>
            </>
          ) : null}
          </>
        ) : null}
      </Panel>
    </Workspace>
  );
}
