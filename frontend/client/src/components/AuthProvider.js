import React, { createContext, useContext, useState, useEffect } from 'react';
import { jwtDecode } from 'jwt-decode';

const AuthContext = createContext();

export const useAuth = () => {
  const context = useContext(AuthContext);
  if (!context) {
    throw new Error('useAuth must be used within an AuthProvider');
  }
  return context;
};

export const AuthProvider = ({ children }) => {
  const [user, setUser] = useState(null);
  const [token, setToken] = useState(null);
  const [loading, setLoading] = useState(true);
  const [cognitoConfig, setCognitoConfig] = useState(null);

  // Fetch runtime configuration
  useEffect(() => {
    const fetchConfig = async () => {
      try {
        console.log('🔄 Fetching runtime configuration...');
        const response = await fetch('/api/config');
        if (!response.ok) {
          throw new Error(`Config fetch failed: ${response.status}`);
        }
        const config = await response.json();
        console.log('✅ Runtime configuration loaded:', config.cognito);
        setCognitoConfig(config.cognito);
      } catch (error) {
        console.error('❌ Failed to fetch runtime config, using fallback:', error);
        // Fallback to hardcoded values if API fails
        setCognitoConfig({
          userPoolId: 'us-east-1_BV6rwETF7',
          clientId: '2uf2g5mgnn6mr3rutuncsu8lut',
          region: 'us-east-1',
          domain: 'workshop-auth'
        });
      }
    };

    fetchConfig();
  }, []);

  // Check for existing token on mount (only after config is loaded)
  useEffect(() => {
    if (!cognitoConfig) return; // Wait for config to load
    const checkExistingAuth = () => {
      try {
        // Check URL for auth callback
        const urlParams = new URLSearchParams(window.location.search);
        const code = urlParams.get('code');
        const error = urlParams.get('error');

        if (error) {
          console.error('❌ Auth error:', error);
          localStorage.removeItem('auth_token');
          localStorage.removeItem('access_token');
          setLoading(false);
          return;
        }

        if (code) {
          // Handle OAuth callback
          handleAuthCallback(code);
          return;
        }

        // Check for stored token
        const storedToken = localStorage.getItem('auth_token');
        if (storedToken) {
          try {
            const decoded = jwtDecode(storedToken);
            
            // Check if token is expired
            if (decoded.exp * 1000 > Date.now()) {
              setToken(storedToken);
              setUser({
                sub: decoded.sub,
                email: decoded.email,
                username: decoded['cognito:username'] || decoded.username,
                name: decoded.name || decoded.email
              });
              console.log('✅ Restored authentication from stored token');
            } else {
              console.log('⚠️ Stored token expired, removing');
              localStorage.removeItem('auth_token');
              localStorage.removeItem('access_token');
              alert('Your session has expired. Please log in again.');
            }
          } catch (error) {
            console.error('❌ Invalid stored token:', error);
            localStorage.removeItem('auth_token');
            localStorage.removeItem('access_token');
          }
        }
      } catch (error) {
        console.error('❌ Error checking existing auth:', error);
      } finally {
        setLoading(false);
      }
    };

    checkExistingAuth();
  }, [cognitoConfig]);

  // Monitor token expiration every minute
  useEffect(() => {
    if (!token) return;

    const checkTokenExpiration = () => {
      try {
        const decoded = jwtDecode(token);
        const expirationTime = decoded.exp * 1000;
        const currentTime = Date.now();
        
        // Check if token expired
        if (expirationTime <= currentTime) {
          console.log('⚠️ Token expired, logging out');
          alert('Your session has expired. Please log in again.');
          logout();
        }
      } catch (error) {
        console.error('❌ Error checking token expiration:', error);
      }
    };

    // Check every minute
    const interval = setInterval(checkTokenExpiration, 60000);
    
    // Also check immediately
    checkTokenExpiration();
    
    return () => clearInterval(interval);
  }, [token]);

  const handleAuthCallback = async (code) => {
    if (!cognitoConfig) return;
    
    try {
      console.log('🔄 Processing OAuth callback...');
      
      const HOSTED_UI_URL = `https://${cognitoConfig.domain}.auth.${cognitoConfig.region}.amazoncognito.com`;
      const REDIRECT_URI = window.location.origin;
      
      // Exchange code for tokens
      const tokenResponse = await fetch(`${HOSTED_UI_URL}/oauth2/token`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: new URLSearchParams({
          grant_type: 'authorization_code',
          client_id: cognitoConfig.clientId,
          code: code,
          redirect_uri: REDIRECT_URI
        })
      });

      if (!tokenResponse.ok) {
        throw new Error(`Token exchange failed: ${tokenResponse.status}`);
      }

      const tokens = await tokenResponse.json();
      const accessToken = tokens.access_token;  // For AgentCore (has client_id)
      const idToken = tokens.id_token;          // For API Gateway (has aud)

      if (!idToken) {
        throw new Error('No ID token received');
      }

      // Decode ID token for user info
      const decoded = jwtDecode(idToken);
      setToken(idToken);  // Store ID token for API Gateway
      setUser({
        sub: decoded.sub,
        email: decoded.email,
        username: decoded['cognito:username'] || decoded.username,
        name: decoded.name || decoded.email
      });

      // Store both tokens
      localStorage.setItem('auth_token', idToken);  // ID token for API Gateway
      localStorage.setItem('access_token', accessToken);  // ACCESS token for AgentCore
      
      // Clean up URL
      window.history.replaceState({}, document.title, window.location.pathname);
      
      console.log('✅ Authentication successful');
    } catch (error) {
      console.error('❌ Auth callback error:', error);
    } finally {
      setLoading(false);
    }
  };

  const login = () => {
    if (!cognitoConfig) {
      console.error('❌ Cognito config not loaded yet');
      return;
    }

    const HOSTED_UI_URL = `https://${cognitoConfig.domain}.auth.${cognitoConfig.region}.amazoncognito.com`;
    const REDIRECT_URI = window.location.origin;
    
    const authUrl = `${HOSTED_UI_URL}/login?` + new URLSearchParams({
      client_id: cognitoConfig.clientId,
      response_type: 'code',
      scope: 'openid email profile',
      redirect_uri: REDIRECT_URI
    });

    console.log('🔄 Redirecting to Cognito login...');
    console.log('🔧 Using client ID:', cognitoConfig.clientId);
    window.location.href = authUrl;
  };

  const logout = () => {
    // Clear authentication tokens
    localStorage.removeItem('auth_token');
    localStorage.removeItem('access_token');
    
    // Clear session IDs for security (prevent session reuse)
    localStorage.removeItem('bedrock_session_id');
    localStorage.removeItem('coveo_mcp_session_id');
    
    setToken(null);
    setUser(null);

    if (!cognitoConfig) {
      console.log('🔄 Logging out (config not loaded)...');
      return;
    }

    const HOSTED_UI_URL = `https://${cognitoConfig.domain}.auth.${cognitoConfig.region}.amazoncognito.com`;
    const REDIRECT_URI = window.location.origin;

    const logoutUrl = `${HOSTED_UI_URL}/logout?` + new URLSearchParams({
      client_id: cognitoConfig.clientId,
      logout_uri: REDIRECT_URI
    });

    console.log('🔄 Logging out and clearing all session data...');
    window.location.href = logoutUrl;
  };

  const getAuthHeaders = () => {
    if (!token) return {};
    return {
      'Authorization': `Bearer ${token}`
    };
  };

  const isAuthenticated = () => {
    return !!token && !!user;
  };

  const value = {
    user,
    token,
    loading: loading || !cognitoConfig, // Keep loading until config is loaded
    login,
    logout,
    getAuthHeaders,
    isAuthenticated,
    cognitoConfig
  };

  return (
    <AuthContext.Provider value={value}>
      {children}
    </AuthContext.Provider>
  );
};

export default AuthProvider;