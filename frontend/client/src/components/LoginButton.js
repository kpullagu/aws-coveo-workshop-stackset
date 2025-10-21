import React from 'react';
import styled from 'styled-components';
import { motion } from 'framer-motion';
import { useAuth } from './AuthProvider';

const LoginContainer = styled(motion.div)`
  display: flex;
  align-items: center;
  gap: 12px;
`;

const LoginButton = styled(motion.button)`
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  color: white;
  border: none;
  padding: 8px 16px;
  border-radius: 8px;
  font-size: 14px;
  font-weight: 500;
  cursor: pointer;
  display: flex;
  align-items: center;
  gap: 8px;
  transition: all 0.2s ease;

  &:hover {
    transform: translateY(-1px);
    box-shadow: 0 4px 12px rgba(102, 126, 234, 0.3);
  }

  &:active {
    transform: translateY(0);
  }
`;

const LogoutButton = styled(LoginButton)`
  background: linear-gradient(135deg, #ff6b6b 0%, #ee5a24 100%);

  &:hover {
    box-shadow: 0 4px 12px rgba(255, 107, 107, 0.3);
  }
`;

const UserInfo = styled.div`
  display: flex;
  align-items: center;
  gap: 6px;
  font-size: 13px;
  color: white;
  font-weight: 500;
  background: rgba(255, 255, 255, 0.15);
  padding: 6px 12px;
  border-radius: 6px;
  backdrop-filter: blur(10px);
`;

const LoadingSpinner = styled(motion.div)`
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

const LoginButtonComponent = () => {
  const { user, loading, login, logout, isAuthenticated } = useAuth();

  if (loading) {
    return (
      <LoginContainer
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        transition={{ duration: 0.3 }}
      >
        <LoadingSpinner />
      </LoginContainer>
    );
  }

  if (isAuthenticated()) {
    return (
      <LoginContainer
        initial={{ opacity: 0, x: 20 }}
        animate={{ opacity: 1, x: 0 }}
        transition={{ duration: 0.3 }}
      >
        <UserInfo>
          Logged in as {user.email}
        </UserInfo>
        <LogoutButton
          onClick={logout}
          whileHover={{ scale: 1.05 }}
          whileTap={{ scale: 0.95 }}
        >
          <span>🚪</span>
          Logout
        </LogoutButton>
      </LoginContainer>
    );
  }

  return (
    <LoginContainer
      initial={{ opacity: 0, x: 20 }}
      animate={{ opacity: 1, x: 0 }}
      transition={{ duration: 0.3 }}
    >
      <LoginButton
        onClick={login}
        whileHover={{ scale: 1.05 }}
        whileTap={{ scale: 0.95 }}
      >
        <span>🔐</span>
        Login
      </LoginButton>
    </LoginContainer>
  );
};

export default LoginButtonComponent;