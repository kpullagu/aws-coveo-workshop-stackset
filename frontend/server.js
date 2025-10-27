const express = require('express');
const cors = require('cors');
const axios = require('axios');
const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '../.env') }); // Load from root directory
const helmet = require('helmet');
const compression = require('compression');
const { v4: uuidv4 } = require('uuid');
const jwt = require('jsonwebtoken');
const jwksClient = require('jwks-rsa');

const app = express();
const PORT = process.env.PORT || 3003;

// Middleware
app.use(helmet({
  contentSecurityPolicy: false // Allow inline styles for development
}));
app.use(compression());
app.use(cors());
app.use(express.json());
app.use(express.static(path.join(__dirname, 'client/build')));

// Coveo Configuration - All from .env file
const COVEO_CONFIG = {
  ORG_ID: process.env.COVEO_ORG_ID,
  SEARCH_API_KEY: process.env.COVEO_SEARCH_API_KEY,
  PLATFORM_URL: process.env.COVEO_PLATFORM_URL,
  SEARCH_PIPELINE: process.env.COVEO_SEARCH_PIPELINE,
  RESULTS_PER_PAGE: parseInt(process.env.COVEO_RESULTS_PER_PAGE) || 20,
  SEARCH_HUB: process.env.COVEO_SEARCH_HUB,
  ANSWER_CONFIG_ID: process.env.COVEO_ANSWER_CONFIG_ID
};

// Debug configuration on startup
console.log('🔧 Environment Variables Debug:');
console.log('NODE_ENV:', process.env.NODE_ENV);
console.log('API_GATEWAY_URL:', process.env.API_GATEWAY_URL);
console.log('AWS_REGION:', process.env.AWS_REGION);
console.log('');
console.log('🔧 Coveo Configuration:');
console.log('ORG_ID:', COVEO_CONFIG.ORG_ID);
console.log('SEARCH_API_KEY:', COVEO_CONFIG.SEARCH_API_KEY ? `${COVEO_CONFIG.SEARCH_API_KEY.substring(0, 10)}...` : 'NOT SET');
console.log('PLATFORM_URL:', COVEO_CONFIG.PLATFORM_URL);
console.log('SEARCH_PIPELINE:', COVEO_CONFIG.SEARCH_PIPELINE);
console.log('SEARCH_HUB:', COVEO_CONFIG.SEARCH_HUB);
console.log('ANSWER_CONFIG_ID:', COVEO_CONFIG.ANSWER_CONFIG_ID);

if (!COVEO_CONFIG.ORG_ID || !COVEO_CONFIG.SEARCH_API_KEY) {
  console.error('❌ Missing required Coveo configuration!');
  console.error('Please check your .env file has COVEO_ORG_ID and COVEO_SEARCH_API_KEY');
}

// Validate required configuration
const requiredVars = ['ORG_ID', 'SEARCH_API_KEY', 'PLATFORM_URL', 'SEARCH_PIPELINE', 'SEARCH_HUB', 'ANSWER_CONFIG_ID'];
const missingVars = requiredVars.filter(key => !COVEO_CONFIG[key]);

if (missingVars.length > 0) {
  console.error('❌ Missing required environment variables:');
  missingVars.forEach(key => {
    console.error(`   - COVEO_${key}`);
  });
  console.error('Please check your .env file and ensure all required variables are set.');
}

// ==========================================
// API Gateway Configuration & Helper
// ==========================================

const API_GATEWAY_BASE_URL = process.env.API_GATEWAY_URL;

/**
 * Invoke API Gateway endpoint instead of Lambda directly
 * @param {string} endpoint - API Gateway endpoint path
 * @param {object} payload - Request payload
 * @param {string} method - HTTP method (default: POST)
 * @param {object} headers - Additional headers
 * @returns {Promise<object>} - API response
 */
async function invokeAPIGateway(endpoint, payload, method = 'POST', headers = {}) {
  try {
    console.log(`🚀 Invoking API Gateway: ${method} ${endpoint}`);
    console.log('📦 Payload:', JSON.stringify(payload, null, 2));

    const config = {
      method,
      url: `${API_GATEWAY_BASE_URL}${endpoint}`,
      headers: {
        'Content-Type': 'application/json',
        ...headers
      },
      timeout: 30000
    };

    if (method !== 'GET' && payload) {
      config.data = payload;
    }

    const response = await axios(config);

    console.log('✅ API Gateway response status:', response.status);
    console.log('✅ API Gateway invocation successful');

    return response.data;

  } catch (error) {
    console.error('❌ API Gateway invocation failed:', error.message);
    if (error.response) {
      console.error('❌ Response status:', error.response.status);
      console.error('❌ Response data:', error.response.data);
    }
    throw error;
  }
}



// ==========================================
// Cognito JWT Authentication Middleware
// ==========================================

// JWKS client for Cognito
const cognitoJwksClient = jwksClient({
  jwksUri: `https://cognito-idp.${process.env.COGNITO_REGION || 'us-east-1'}.amazonaws.com/${process.env.COGNITO_USER_POOL_ID}/.well-known/jwks.json`,
  cache: true,
  cacheMaxAge: 600000, // 10 minutes
  rateLimit: true,
  jwksRequestsPerMinute: 10
});

/**
 * Get signing key from JWKS
 */
function getSigningKey(header, callback) {
  cognitoJwksClient.getSigningKey(header.kid, (err, key) => {
    if (err) {
      return callback(err);
    }
    const signingKey = key.getPublicKey();
    callback(null, signingKey);
  });
}

/**
 * Verify Cognito JWT token middleware
 * Protects all /api/* routes except /api/health
 */
async function verifyToken(req, res, next) {
  // Skip authentication for health check
  if (req.path === '/api/health') {
    return next();
  }

  // Skip authentication for non-API routes
  if (!req.path.startsWith('/api/')) {
    return next();
  }

  // Extract token from Authorization header
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    console.warn('⚠️  No authorization token provided for:', req.path);
    return res.status(401).json({
      error: 'Unauthorized',
      message: 'No authorization token provided'
    });
  }

  const token = authHeader.substring(7); // Remove 'Bearer ' prefix

  try {
    // Verify JWT token
    const decoded = await new Promise((resolve, reject) => {
      jwt.verify(token, getSigningKey, {
        issuer: `https://cognito-idp.${process.env.COGNITO_REGION}.amazonaws.com/${process.env.COGNITO_USER_POOL_ID}`,
        audience: process.env.COGNITO_CLIENT_ID
      }, (err, decoded) => {
        if (err) {
          reject(err);
        } else {
          resolve(decoded);
        }
      });
    });

    // Attach user info to request
    req.user = {
      sub: decoded.sub,
      email: decoded.email,
      username: decoded['cognito:username']
    };

    console.log('✅ Authenticated user:', req.user.email || req.user.username);
    next();

  } catch (error) {
    console.error('❌ Token verification failed:', error.message);
    return res.status(401).json({
      error: 'Unauthorized',
      message: 'Invalid or expired token'
    });
  }
}

// Apply authentication middleware to all routes
// ENABLE THIS FOR PRODUCTION - Currently disabled for development
// app.use(verifyToken);

console.log('⚠️  AUTHENTICATION MIDDLEWARE DISABLED FOR DEVELOPMENT');
console.log('⚠️  Enable by uncommenting: app.use(verifyToken) in server.js');

// ==========================================
// Configuration Endpoint (No Auth Required)
// ==========================================
app.get('/api/config', (req, res) => {
  res.json({
    cognito: {
      userPoolId: process.env.COGNITO_USER_POOL_ID,
      clientId: process.env.COGNITO_CLIENT_ID,
      region: process.env.COGNITO_REGION || 'us-east-1',
      domain: process.env.COGNITO_DOMAIN || 'workshop-auth'
    },
    api: {
      baseUrl: API_GATEWAY_BASE_URL
    },
    coveo: {
      orgId: COVEO_CONFIG.ORG_ID,
      searchHub: COVEO_CONFIG.SEARCH_HUB,
      searchPipeline: COVEO_CONFIG.SEARCH_PIPELINE
    }
  });
});

// ==========================================
// Health Check Endpoint (No Auth Required)
// ==========================================
app.get('/api/health', (req, res) => {
  res.json({
    status: 'healthy',
    timestamp: new Date().toISOString(),
    config: {
      coveoOrgId: COVEO_CONFIG.ORG_ID,
      searchHub: COVEO_CONFIG.SEARCH_HUB,
      searchPipeline: COVEO_CONFIG.SEARCH_PIPELINE,
      apiGateway: {
        baseUrl: API_GATEWAY_BASE_URL || 'not configured',
        configured: !!API_GATEWAY_BASE_URL
      },
      cognito: {
        userPoolId: process.env.COGNITO_USER_POOL_ID || 'not configured',
        region: process.env.COGNITO_REGION || 'not configured'
      }
    }
  });
});

// ==========================================
// API Endpoints (Authentication Required)
// ==========================================

// Search endpoint
app.post('/api/search', async (req, res) => {
  try {
    const { query, facets = {}, backendMode = 'coveo', numberOfResults = 12, firstResult = 0, sessionId } = req.body;

    console.log('🔍 Search request:', { query, facets, backendMode, numberOfResults, firstResult });

    // All backends use the same search endpoint with proper Coveo Search API payload
    const endpoint = '/search';
    const payload = {
      locale: "en",
      debug: false,
      tab: "default",
      referrer: "",
      timezone: "America/Chicago",
      fieldsToInclude: [
        "author", "language", "urihash", "objecttype", "collection", "source",
        "permanentid", "date", "filetype", "parents", "project", "documenttype", "infobox_type",
        "categories", "data", "title", "clickableuri", "summary", "body"
      ],
      q: query,
      enableQuerySyntax: false,
      searchHub: COVEO_CONFIG.SEARCH_HUB,
      sortCriteria: "relevancy",
      queryCorrection: {
        enabled: true,
        options: {
          automaticallyCorrect: "whenNoResults"
        }
      },
      enableDidYouMean: false,
      facets: [
        {
          filterFacetCount: true,
          injectionDepth: 1000,
          numberOfValues: 8,
          sortCriteria: "automatic",
          resultsMustMatch: "atLeastOneValue",
          type: "specific",
          currentValues: facets.project ? facets.project.map(v => ({ value: v, state: "selected" })) : [],
          freezeCurrentValues: false,
          isFieldExpanded: false,
          preventAutoSelect: false,
          facetId: "project",
          field: "project",
          tabs: { included: [], excluded: [] },
          activeTab: ""
        },
        {
          filterFacetCount: true,
          injectionDepth: 1000,
          numberOfValues: 8,
          sortCriteria: "automatic",
          resultsMustMatch: "atLeastOneValue",
          type: "specific",
          currentValues: facets.documentType ? facets.documentType.map(v => ({ value: v, state: "selected" })) : [],
          freezeCurrentValues: false,
          isFieldExpanded: false,
          preventAutoSelect: false,
          facetId: "documenttype",
          field: "documenttype",
          tabs: { included: [], excluded: [] },
          activeTab: ""
        },
        {
          filterFacetCount: true,
          injectionDepth: 1000,
          numberOfValues: 8,
          sortCriteria: "automatic",
          resultsMustMatch: "atLeastOneValue",
          type: "specific",
          currentValues: facets.categories ? facets.categories.map(v => ({ value: v, state: "selected" })) : [],
          freezeCurrentValues: false,
          isFieldExpanded: false,
          preventAutoSelect: false,
          facetId: "categories",
          field: "categories",
          tabs: { included: [], excluded: [] },
          activeTab: ""
        },
        {
          filterFacetCount: true,
          injectionDepth: 1000,
          numberOfValues: 8,
          sortCriteria: "automatic",
          resultsMustMatch: "atLeastOneValue",
          type: "specific",
          currentValues: [],
          freezeCurrentValues: false,
          isFieldExpanded: false,
          preventAutoSelect: false,
          facetId: "infobox_type",
          field: "infobox_type",
          tabs: { included: [], excluded: [] },
          activeTab: ""
        },
        {
          filterFacetCount: true,
          injectionDepth: 1000,
          numberOfValues: 8,
          sortCriteria: "automatic",
          resultsMustMatch: "atLeastOneValue",
          type: "specific",
          currentValues: [],
          freezeCurrentValues: false,
          isFieldExpanded: false,
          preventAutoSelect: false,
          facetId: "author",
          field: "author",
          tabs: { included: [], excluded: [] },
          activeTab: ""
        }
      ],
      numberOfResults,
      firstResult,
      facetOptions: {
        freezeFacetOrder: false
      },
      pipelineRuleParameters: {
        mlGenerativeQuestionAnswering: {
          responseFormat: {
            contentFormat: ["text/markdown", "text/plain"]
          },
          citationsFieldToInclude: ["filetype", "project", "documenttype", "clickableuri", "title"]
        }
      },
      backendMode  // Include backendMode for logging/tracking
    };

    console.log(`🎯 Routing to API Gateway ${endpoint} (${backendMode} mode)`)

    // Add authorization header if available
    const headers = {};
    if (req.headers.authorization) {
      headers.Authorization = req.headers.authorization;
    }

    // Invoke API Gateway
    const response = await invokeAPIGateway(endpoint, payload, 'POST', headers);

    console.log('✅ Search completed successfully');
    console.log('📊 Results count:', response.totalCount || response.results?.length || 0);

    res.json(response);
  } catch (error) {
    console.error('❌ Search error:', error.message);
    res.status(500).json({
      error: 'Search failed',
      message: error.message,
      details: error.response?.data || null
    });
  }
});

// Passage retrieval endpoint
app.post('/api/passages', async (req, res) => {
  try {
    const { query, backendMode = 'coveo', numberOfPassages = 5, sessionId } = req.body;

    console.log('📄 Passages request:', { query, backendMode, numberOfPassages });

    // All backends use the same passages endpoint with proper Coveo Passages API payload
    const endpoint = '/passages';
    const payload = {
      query,
      numberOfPassages,
      organizationId: COVEO_CONFIG.ORG_ID,
      pipeline: COVEO_CONFIG.SEARCH_PIPELINE,
      searchHub: COVEO_CONFIG.SEARCH_HUB,
      localization: {
        locale: 'en-US',
        fallbackLocale: 'en'
      },
      additionalFields: ["title", "clickableuri", "project", "uniqueid", "summary"],
      facets: [
        {
          filterFacetCount: true,
          injectionDepth: 1000,
          numberOfValues: 8,
          sortCriteria: "automatic",
          resultsMustMatch: "atLeastOneValue",
          type: "specific",
          currentValues: [],
          freezeCurrentValues: false,
          isFieldExpanded: false,
          preventAutoSelect: false,
          facetId: "project",
          field: "project",
          tabs: { included: [], excluded: [] },
          activeTab: ""
        }
      ],
      queryCorrection: {
        enabled: true,
        options: {
          automaticallyCorrect: "whenNoResults"
        }
      },
      analytics: {
        clientId: require('uuid').v4(),
        clientTimestamp: new Date().toISOString(),
        originContext: "Passages",
        actionCause: "passageRetrieval",
        capture: false,
        source: ["WikiSearch@1.0.0"]
      },
      backendMode  // Include backendMode for logging/tracking
    };

    console.log(`🎯 Routing to API Gateway ${endpoint} (${backendMode} mode)`)

    // Add authorization header if available
    const headers = {};
    if (req.headers.authorization) {
      headers.Authorization = req.headers.authorization;
    }

    // Invoke API Gateway
    const response = await invokeAPIGateway(endpoint, payload, 'POST', headers);

    console.log('✅ Passages retrieval completed successfully');
    res.json(response);
  } catch (error) {
    console.error('❌ Passage retrieval error:', error.message);
    res.status(500).json({
      error: 'Passage retrieval failed',
      message: error.message,
      details: error.response?.data || null
    });
  }
});

// Answer generation endpoint
app.post('/api/answer', async (req, res) => {
  try {
    const { query, backendMode = 'coveo', sessionId } = req.body;

    console.log('🤖 Answer request:', { query, backendMode });

    let endpoint;
    let payload;

    switch (backendMode) {
      case 'coveo':
        // Use answer endpoint with proper Coveo Answer API payload
        endpoint = '/answer';
        payload = {
          q: query,
          pipeline: COVEO_CONFIG.SEARCH_PIPELINE,
          pipelineRuleParameters: {
            mlGenerativeQuestionAnswering: {
              responseFormat: {
                contentFormat: ["text/markdown", "text/plain"]
              },
              citationsFieldToInclude: ["filetype", "project", "documenttype", "clickableuri", "title"]
            }
          },
          searchHub: COVEO_CONFIG.SEARCH_HUB,
          facets: [
            {
              filterFacetCount: true,
              injectionDepth: 1000,
              numberOfValues: 8,
              sortCriteria: "automatic",
              resultsMustMatch: "atLeastOneValue",
              type: "specific",
              currentValues: [],
              freezeCurrentValues: false,
              isFieldExpanded: false,
              preventAutoSelect: false,
              facetId: "project",
              field: "project",
              tabs: { included: [], excluded: [] },
              activeTab: ""
            },
            {
              filterFacetCount: true,
              injectionDepth: 1000,
              numberOfValues: 8,
              sortCriteria: "automatic",
              resultsMustMatch: "atLeastOneValue",
              type: "specific",
              currentValues: [],
              freezeCurrentValues: false,
              isFieldExpanded: false,
              preventAutoSelect: false,
              facetId: "documenttype",
              field: "documenttype",
              tabs: { included: [], excluded: [] },
              activeTab: ""
            },
            {
              filterFacetCount: true,
              injectionDepth: 1000,
              numberOfValues: 8,
              sortCriteria: "automatic",
              resultsMustMatch: "atLeastOneValue",
              type: "specific",
              currentValues: [],
              freezeCurrentValues: false,
              isFieldExpanded: false,
              preventAutoSelect: false,
              facetId: "categories",
              field: "categories",
              tabs: { included: [], excluded: [] },
              activeTab: ""
            }
          ],
          fieldsToInclude: [
            "author", "language", "urihash", "objecttype", "collection", "source",
            "permanentid", "date", "filetype", "parents", "project", "documenttype",
            "infobox_type", "categories", "data", "title", "clickableuri", "summary"
          ],
          queryCorrection: {
            enabled: true,
            options: {
              automaticallyCorrect: "whenNoResults"
            }
          },
          enableDidYouMean: false,
          numberOfResults: 10,
          firstResult: 0,
          tab: "",
          analytics: {
            clientId: require('uuid').v4(),
            clientTimestamp: new Date().toISOString(),
            documentReferrer: "",
            documentLocation: "WikiSearch",
            originContext: "Search",
            actionCause: "interfaceLoad",
            capture: false,
            source: ["WikiSearch@1.0.0"]
          }
        };
        console.log('🎯 Routing to API Gateway /answer (coveo mode)');
        break;

      case 'bedrockAgent':
        // Use Bedrock Agent endpoint with optimized Coveo passages payload (single-turn for answers)
        endpoint = '/bedrock-agent-chat';
        payload = {
          query: query,
          sessionId: null, // No session memory for single-turn answers
          backendMode: 'bedrockAgent',
          conversationType: 'single-turn', // Indicate this is a single-turn request
          numberOfPassages: 5,
          organizationId: COVEO_CONFIG.ORG_ID,
          pipeline: COVEO_CONFIG.SEARCH_PIPELINE,
          searchHub: COVEO_CONFIG.SEARCH_HUB,
          localization: {
            locale: 'en-US',
            fallbackLocale: 'en'
          },
          additionalFields: ["title", "clickableuri", "project", "uniqueid", "summary"],
          facets: [
            {
              filterFacetCount: true,
              injectionDepth: 1000,
              numberOfValues: 8,
              sortCriteria: "automatic",
              resultsMustMatch: "atLeastOneValue",
              type: "specific",
              currentValues: [],
              freezeCurrentValues: false,
              isFieldExpanded: false,
              preventAutoSelect: false,
              facetId: "project",
              field: "project",
              tabs: { included: [], excluded: [] },
              activeTab: ""
            }
          ],
          queryCorrection: {
            enabled: true,
            options: {
              automaticallyCorrect: "whenNoResults"
            }
          },
          analytics: {
            clientId: require('uuid').v4(),
            clientTimestamp: new Date().toISOString(),
            originContext: "Passages",
            actionCause: "passageRetrieval",
            capture: false,
            source: ["Coveo Workshop Knowledge Explorer@1.0.0"]
          }
        };
        console.log(`🤖 Routing to API Gateway ${endpoint} (${backendMode} mode - single-turn, no session memory)`);
        break;

      case 'coveoMCP':
        // Route through agentcore endpoint with proper parameters for MCP
        endpoint = '/agentcore';
        payload = {
          query,
          sessionId: sessionId || uuidv4(),
          backendMode: 'coveoMCP',
          conversationType: 'single-turn',  // Answer endpoint is single-turn
          controls: {
            answer: {
              additionalFields: ["title", "clickableuri", "project", "uniqueid", "summary"]
            },
            passages: {
              additionalFields: ["title", "clickableuri", "project", "uniqueid", "summary"]
            },
            search: {
              fieldsToInclude: ["title", "clickableuri", "project", "uniqueid", "summary", "excerpt"]
            }
          }
        };
        console.log('🎯 Routing to API Gateway /agentcore (coveoMCP mode - single-turn) with controls for answer, passages, and search');
        break;

      default:
        return res.status(400).json({
          error: 'Invalid backend mode',
          message: `Backend mode '${backendMode}' is not supported. Use 'coveo', 'bedrockAgent', or 'coveoMCP'.`
        });
    }

    // Add authorization header if available
    const headers = {};
    if (req.headers.authorization) {
      headers.Authorization = req.headers.authorization;
    }

    // Invoke API Gateway - Lambda already handles streaming processing
    const response = await invokeAPIGateway(endpoint, payload, 'POST', headers);

    console.log('✅ Answer generation completed successfully');
    console.log('📚 Response structure:', {
      hasAnswer: !!(response.answer || response.answerText || response.response),
      answerLength: (response.answer || response.answerText || response.response || '').length,
      hasCitations: !!(response.citations && response.citations.length > 0),
      citationsCount: response.citations?.length || 0,
      responseKeys: Object.keys(response || {}),
      fullResponse: response
    });

    res.json(response);
  } catch (error) {
    console.error('❌ Answer generation error:', error.message);
    res.status(500).json({
      error: 'Answer generation failed',
      message: error.message,
      details: error.response?.data || null
    });
  }
});

// Chat endpoint
app.post('/api/chat', async (req, res) => {
  try {
    const { message, sessionId, backendMode = 'coveo' } = req.body;

    console.log('💬 Chat request:', { message, backendMode, hasSessionId: !!sessionId });

    let endpoint;
    let payload;

    switch (backendMode) {
      case 'coveo':
        // Use answer endpoint for single-turn with proper payload
        endpoint = '/answer';
        payload = {
          q: message,
          pipeline: COVEO_CONFIG.SEARCH_PIPELINE,
          pipelineRuleParameters: {
            mlGenerativeQuestionAnswering: {
              responseFormat: {
                contentFormat: ["text/markdown", "text/plain"]
              },
              citationsFieldToInclude: ["filetype", "project", "documenttype", "clickableuri", "title"]
            }
          },
          searchHub: COVEO_CONFIG.SEARCH_HUB,
          facets: [
            {
              filterFacetCount: true,
              injectionDepth: 1000,
              numberOfValues: 8,
              sortCriteria: "automatic",
              resultsMustMatch: "atLeastOneValue",
              type: "specific",
              currentValues: [],
              freezeCurrentValues: false,
              isFieldExpanded: false,
              preventAutoSelect: false,
              facetId: "project",
              field: "project",
              tabs: { included: [], excluded: [] },
              activeTab: ""
            }
          ],
          fieldsToInclude: [
            "author", "language", "urihash", "objecttype", "collection", "source",
            "permanentid", "date", "filetype", "parents", "project", "documenttype",
            "infobox_type", "categories", "data", "title", "clickableuri", "summary"
          ],
          queryCorrection: {
            enabled: true,
            options: {
              automaticallyCorrect: "whenNoResults"
            }
          },
          enableDidYouMean: false,
          numberOfResults: 10,
          firstResult: 0,
          tab: "",
          analytics: {
            clientId: require('uuid').v4(),
            clientTimestamp: new Date().toISOString(),
            documentReferrer: "",
            documentLocation: "WikiSearch",
            originContext: "Search",
            actionCause: "interfaceLoad",
            capture: false,
            source: ["WikiSearch@1.0.0"]
          }
        };
        console.log('🎯 Routing to API Gateway /answer (coveo mode - single turn)');
        break;

      case 'bedrockAgent':
        // Use Bedrock Agent endpoint with optimized Coveo passages payload for multi-turn conversations
        endpoint = '/bedrock-agent-chat';
        payload = {
          query: message,
          sessionId: sessionId || require('uuid').v4(),
          backendMode: 'bedrockAgent',
          conversationType: 'multi-turn', // Indicate this is a multi-turn request
          numberOfPassages: 5,
          organizationId: COVEO_CONFIG.ORG_ID,
          pipeline: COVEO_CONFIG.SEARCH_PIPELINE,
          searchHub: COVEO_CONFIG.SEARCH_HUB,
          localization: {
            locale: 'en-US',
            fallbackLocale: 'en'
          },
          additionalFields: ["title", "clickableuri", "project", "uniqueid", "summary"],
          facets: [
            {
              filterFacetCount: true,
              injectionDepth: 1000,
              numberOfValues: 8,
              sortCriteria: "automatic",
              resultsMustMatch: "atLeastOneValue",
              type: "specific",
              currentValues: [],
              freezeCurrentValues: false,
              isFieldExpanded: false,
              preventAutoSelect: false,
              facetId: "project",
              field: "project",
              tabs: { included: [], excluded: [] },
              activeTab: ""
            }
          ],
          queryCorrection: {
            enabled: true,
            options: {
              automaticallyCorrect: "whenNoResults"
            }
          },
          analytics: {
            clientId: require('uuid').v4(),
            clientTimestamp: new Date().toISOString(),
            originContext: "Passages",
            actionCause: "passageRetrieval",
            capture: false,
            source: ["Coveo Workshop Knowledge Explorer@1.0.0"]
          }
        };
        console.log(`🤖 Routing to API Gateway ${endpoint} (${backendMode} mode - multi-turn with sessionId: ${payload.sessionId.substring(0, 8)}...)`);
        break;

      case 'coveoMCP':
        // Use agentcore endpoint for multi-turn
        endpoint = '/agentcore';
        payload = {
          question: message,
          sessionId: sessionId || require('uuid').v4(),
          backendMode,
          conversationType: 'multi-turn',  // Chat endpoint is multi-turn with memory
          controls: {
            answer: {
              additionalFields: ["title", "clickableuri", "project", "uniqueid", "summary"]
            },
            passages: {
              additionalFields: ["title", "clickableuri", "project", "uniqueid", "summary"]
            },
            search: {
              fieldsToInclude: ["title", "clickableuri", "project", "uniqueid", "summary", "excerpt"]
            }
          }
        };
        console.log(`🎯 Routing to API Gateway /agentcore (${backendMode} mode - multi-turn with memory) with controls for answer, passages, and search`);
        break;

      default:
        return res.status(400).json({
          error: 'Invalid backend mode',
          message: `Backend mode '${backendMode}' is not supported. Use 'coveo', 'bedrockAgent', or 'coveoMCP'.`
        });
    }

    // Add authorization header if available
    const headers = {};
    if (req.headers.authorization) {
      headers.Authorization = req.headers.authorization;
    }

    // Invoke API Gateway - Lambda already handles streaming processing
    const response = await invokeAPIGateway(endpoint, payload, 'POST', headers);

    // Handle Lambda response format - API Gateway returns the full Lambda response
    let processedResponse = response;

    // If response has statusCode and body (Lambda format), extract the body
    if (response.statusCode && response.body) {
      try {
        processedResponse = typeof response.body === 'string' ? JSON.parse(response.body) : response.body;
        console.log('📦 Parsed Lambda response body');
      } catch (parseError) {
        console.error('❌ Failed to parse Lambda response body:', parseError);
        processedResponse = response;
      }
    }

    console.log('✅ Chat completed successfully');
    console.log('💬 Response structure:', {
      hasResponse: !!(processedResponse.response || processedResponse.answer || processedResponse.answerText),
      responseLength: (processedResponse.response || processedResponse.answer || processedResponse.answerText || '').length,
      hasCitations: !!(processedResponse.citations && processedResponse.citations.length > 0),
      citationsCount: processedResponse.citations?.length || 0,
      responseKeys: Object.keys(processedResponse || {}),
      sessionId: processedResponse.sessionId || 'none (stateless)',
      fullResponse: processedResponse
    });

    res.json(processedResponse);
  } catch (error) {
    console.error('❌ Chat error:', error.message);
    res.status(500).json({
      error: 'Chat failed',
      message: error.message,
      details: error.response?.data || null
    });
  }
});


// Query suggestions endpoint
app.post('/api/QuerySuggest', async (req, res) => {
  try {
    const { q, count = 5 } = req.body;

    console.log('🔍 Query suggest request:', { q, count });

    // Add authorization header if available
    const headers = {};
    if (req.headers.authorization) {
      headers.Authorization = req.headers.authorization;
    }

    const request_body = {
      'q': q || '',
      'count': count,
      'searchHub': COVEO_CONFIG.SEARCH_HUB,
      'pipeline': COVEO_CONFIG.SEARCH_PIPELINE || 'aws-workshop-pipeline',
      'locale': 'en-US',
      'timezone': 'America/New_York'
    };

    const response = await invokeAPIGateway('/QuerySuggest', request_body, 'POST', headers);

    res.json(response);
  } catch (error) {
    console.error('❌ Query suggest error:', error.response?.data || error.message);
    res.status(500).json({ error: 'Query suggestions failed', details: error.response?.data || error.message });
  }
});



// HTML content endpoint
app.post('/api/html', async (req, res) => {
  try {
    const { query, uniqueId, requestedOutputSize = 0 } = req.body;

    console.log('📄 HTML content request:', { query, uniqueId, requestedOutputSize });

    if (!uniqueId) {
      return res.status(400).json({
        error: 'Missing required parameters',
        details: 'uniqueId is required'
      });
    }

    // Add authorization header if available
    const headers = {};
    if (req.headers.authorization) {
      headers.Authorization = req.headers.authorization;
    }

    const request_body = {
      'q': query,
      'uniqueId': uniqueId,
      'requestedOutputSize': requestedOutputSize.toString()
    };

    const response = await invokeAPIGateway('/html', request_body, 'POST', headers);

    // Return HTML content as JSON with proper structure
    res.json({
      html: response,
      uniqueId: uniqueId,
      query: query
    });

  } catch (error) {
    console.error('❌ HTML content error:', error.response?.status, error.response?.statusText);
    console.error('❌ Error details:', error.response?.data || error.message);

    res.status(500).json({
      error: 'HTML content retrieval failed',
      details: error.response?.data || error.message,
      status: error.response?.status
    });
  }
});

// Serve React app
app.get('*', (req, res) => {
  const buildPath = path.join(__dirname, 'client/build', 'index.html');
  console.log('🔍 Looking for build at:', buildPath);
  console.log('🔍 Build exists:', require('fs').existsSync(buildPath));

  if (require('fs').existsSync(buildPath)) {
    console.log('✅ Serving React app');
    res.sendFile(buildPath);
  } else {
    console.log('❌ Build not found, serving fallback');
    res.send(`
      <h1>WikiSearch Server Running</h1>
      <p>React app not built yet. Use <a href="/api/health">Health Check</a> to test the API.</p>
      <p>To build the React app, run: <code>cd client && npm run build</code></p>
      <p>Looking for: ${buildPath}</p>
    `);
  }
});

app.listen(PORT, () => {
  console.log(`🚀 Server running on port ${PORT}`);
  console.log(`🔍 Coveo Org ID: ${COVEO_CONFIG.ORG_ID}`);
  console.log(`📊 Search Hub: ${COVEO_CONFIG.SEARCH_HUB}`);
  console.log(`🌐 API Gateway: ${API_GATEWAY_BASE_URL || 'Not configured'}`);
});