import axios from 'axios';

const API_BASE = process.env.NODE_ENV === 'production' ? '' : 'http://localhost:3003';

// Create axios instance
const api = axios.create({
  baseURL: API_BASE,
  timeout: 30000,
  headers: {
    'Content-Type': 'application/json',
  },
});

// Function to get auth token from localStorage
const getAuthToken = (backendMode) => {
  // For coveoMCP backend, use ACCESS token (has client_id claim for AgentCore)
  // For other backends, use ID token (has aud claim for API Gateway)
  if (backendMode === 'coveoMCP') {
    return localStorage.getItem('access_token');
  }
  return localStorage.getItem('auth_token');
};

// Request interceptor for logging and auth
api.interceptors.request.use(
  (config) => {
    // Add auth token if available
    // Check if request data has backendMode to determine which token to use
    const backendMode = config.data?.backendMode;
    const token = getAuthToken(backendMode);
    if (token) {
      config.headers.Authorization = `Bearer ${token}`;
    }

    console.log(`🚀 API Request: ${config.method?.toUpperCase()} ${config.url}`);
    console.log('📤 Request data:', config.data);
    console.log('🔐 Auth header:', config.headers.Authorization ? 'Present' : 'Missing');
    return config;
  },
  (error) => {
    console.error('❌ API Request Error:', error);
    return Promise.reject(error);
  }
);

// Response interceptor for logging and auth error handling
api.interceptors.response.use(
  (response) => {
    console.log(`✅ API Response: ${response.config.url}`);
    console.log('📥 Response status:', response.status);
    console.log('📊 Response data:', response.data);
    return response;
  },
  (error) => {
    console.error('❌ API Response Error:', error.response?.status, error.response?.statusText);
    console.error('❌ Error data:', error.response?.data);
    console.error('❌ Error message:', error.message);

    // Handle authentication errors
    if (error.response?.status === 401) {
      console.warn('🔐 Authentication required - redirecting to login');
      // Remove invalid token
      localStorage.removeItem('auth_token');
      // Trigger re-authentication (the AuthProvider will handle this)
      window.dispatchEvent(new CustomEvent('auth-required'));
    }

    return Promise.reject(error);
  }
);

export const searchAPI = async (query, facets = {}, backendMode = 'coveo', numberOfResults = 12, firstResult = 0) => {
  try {
    const response = await api.post('/api/search', {
      query,
      facets,
      backendMode,
      numberOfResults,
      firstResult
    });
    return response.data;
  } catch (error) {
    throw new Error(`Search failed: ${error.response?.data?.error || error.message}`);
  }
};

export const passageAPI = async (query, backendMode = 'coveo', numberOfPassages = 5) => {
  try {
    const response = await api.post('/api/passages', {
      query,
      backendMode,
      numberOfPassages
    });
    return response.data;
  } catch (error) {
    throw new Error(`Passage retrieval failed: ${error.response?.data?.error || error.message}`);
  }
};

export const answerAPI = async (query, backendMode = 'coveo') => {
  try {
    const response = await api.post('/api/answer', {
      query,
      backendMode
    });
    return response.data;
  } catch (error) {
    throw new Error(`Answer generation failed: ${error.response?.data?.error || error.message}`);
  }
};

export const chatAPI = async (message, sessionId, backendMode = 'coveo') => {
  try {
    const response = await api.post('/api/chat', {
      message,
      sessionId,
      backendMode
    });
    return response.data;
  } catch (error) {
    throw new Error(`Chat failed: ${error.response?.data?.error || error.message}`);
  }
};

export const suggestAPI = async (query, count = 5) => {
  try {
    const response = await api.post('/api/QuerySuggest', {
      q: query, // Use 'q' parameter for new API
      count
    });
    return response.data;
  } catch (error) {
    throw new Error(`Query suggestions failed: ${error.response?.data?.error || error.message}`);
  }
};

export const htmlAPI = async (query, uniqueId, requestedOutputSize = 0) => {
  try {
    const response = await api.post('/api/html', {
      query,
      uniqueId,
      requestedOutputSize,
      enableNavigation: 'false'
    });
    return response.data;
  } catch (error) {
    throw new Error(`HTML content retrieval failed: ${error.response?.data?.error || error.message}`);
  }
};

export const testAPI = async () => {
  try {
    const response = await api.get('/api/test');
    return response.data;
  } catch (error) {
    throw new Error(`Test failed: ${error.response?.data?.error || error.message}`);
  }
};

export default api;