"""
Centralized environment configuration loader for Lambda functions.

This module provides a unified way to load configuration from:
1. Environment variables (highest priority)
2. AWS Systems Manager Parameter Store

Usage in Lambda functions:
    from config.env import get_config
    
    config = get_config()
    org_id = config['COVEO_ORG_ID']
    api_key = config['COVEO_SEARCH_API_KEY']
"""

import os
import json
import boto3
from typing import Dict, Any, Optional
from functools import lru_cache

# AWS clients (initialized lazily)
_ssm_client = None


def get_ssm_client():
    """Get or create SSM client (singleton pattern)."""
    global _ssm_client
    if _ssm_client is None:
        _ssm_client = boto3.client('ssm', region_name=os.environ.get('AWS_REGION', 'us-east-1'))
    return _ssm_client


def get_parameter(name: str, decrypt: bool = False) -> Optional[str]:
    """
    Retrieve a parameter from SSM Parameter Store.
    
    Args:
        name: Parameter name (can be full path like /workshop/coveo/org-id)
        decrypt: Whether to decrypt SecureString parameters
        
    Returns:
        Parameter value or None if not found
    """
    try:
        ssm = get_ssm_client()
        response = ssm.get_parameter(Name=name, WithDecryption=decrypt)
        return response['Parameter']['Value']
    except ssm.exceptions.ParameterNotFound:
        return None
    except Exception as e:
        print(f"Error retrieving SSM parameter {name}: {e}")
        return None





@lru_cache(maxsize=1)
def get_config() -> Dict[str, Any]:
    """
    Load and cache configuration from all sources.
    
    Priority order:
    1. Environment variables (direct values)
    2. SSM Parameter Store
    
    Returns:
        Dictionary of configuration values
    """
    config = {}
    stack_prefix = os.environ.get('STACK_PREFIX', 'workshop')
    
    # Define configuration keys and their SSM/Secrets paths
    config_mapping = {
        # Coveo settings (from SSM and Secrets)
        'COVEO_ORG_ID': {
            'env': 'COVEO_ORG_ID',
            'ssm': f'/{stack_prefix}/coveo/org-id',
            'required': True
        },
        'COVEO_SEARCH_API_KEY': {
            'env': 'COVEO_SEARCH_API_KEY',
            'ssm': f'/{stack_prefix}/coveo/search-api-key',
            'required': True
        },
        'COVEO_ANSWERING_CONFIG_ID': {
            'env': 'COVEO_ANSWERING_CONFIG_ID',
            'ssm': f'/{stack_prefix}/coveo/answering-config-id',
            'required': True
        },
        'COVEO_PLATFORM_URL': {
            'env': 'COVEO_PLATFORM_URL',
            'default': 'https://platform.cloud.coveo.com',
            'required': False
        },
        'COVEO_SEARCH_HUB': {
            'env': 'COVEO_SEARCH_HUB',
            'default': 'workshop',
            'required': False
        },
        
        # Cognito settings (from CloudFormation outputs → SSM)
        'COGNITO_USER_POOL_ID': {
            'env': 'COGNITO_USER_POOL_ID',
            'ssm': f'/{stack_prefix}/coveo/user-pool-id',
            'required': True
        },
        'COGNITO_CLIENT_ID': {
            'env': 'COGNITO_CLIENT_ID',
            'ssm': f'/{stack_prefix}/coveo/client-id',
            'required': True
        },
        'COGNITO_DOMAIN': {
            'env': 'COGNITO_DOMAIN',
            'ssm': f'/{stack_prefix}/cognito/domain',
            'required': True
        },
        
        # API Gateway
        'API_BASE_URL': {
            'env': 'API_BASE_URL',
            'ssm': f'/{stack_prefix}/coveo/api-base-url',
            'required': True
        },
        
        # Bedrock Agent (optional for Lab 2)
        'BEDROCK_AGENT_ID': {
            'env': 'BEDROCK_AGENT_ID',
            'ssm': f'/{stack_prefix}/coveo/agent-id',
            'required': False
        },
        'BEDROCK_AGENT_ALIAS_ID': {
            'env': 'BEDROCK_AGENT_ALIAS_ID',
            'ssm': f'/{stack_prefix}/coveo/agent-alias-id',
            'required': False
        },
        'BEDROCK_MODEL_ID': {
            'env': 'BEDROCK_MODEL_ID',
            'default': 'amazon.nova-lite-v1:0',
            'required': False
        },
        
        # AgentCore + MCP (optional for Lab 3)
        'AGENTCORE_GATEWAY_URL': {
            'env': 'AGENTCORE_GATEWAY_URL',
            'ssm': f'/{stack_prefix}/agentcore/gateway-url',
            'required': False
        },
        'MCP_SERVER_URL': {
            'env': 'MCP_SERVER_URL',
            'ssm': f'/{stack_prefix}/mcp/server-url',
            'required': False
        },
        
        # General settings
        'AWS_REGION': {
            'env': 'AWS_REGION',
            'default': 'us-east-1',
            'required': True
        },
        'LOG_LEVEL': {
            'env': 'LOG_LEVEL',
            'default': 'INFO',
            'required': False
        }
    }
    
    # Load each configuration value
    for key, sources in config_mapping.items():
        value = None
        
        # 1. Try environment variable
        if sources.get('env'):
            value = os.environ.get(sources['env'])
        
        # 2. Try SSM Parameter Store
        if value is None and sources.get('ssm'):
            value = get_parameter(sources['ssm'], decrypt=False)
        
        # 3. Use default value
        if value is None and sources.get('default'):
            value = sources['default']
        
        # Check if required value is missing
        if value is None and sources.get('required'):
            raise ValueError(f"Required configuration '{key}' not found in environment or SSM Parameter Store")
        
        config[key] = value
    
    return config


def get_config_value(key: str, default: Any = None) -> Any:
    """
    Get a single configuration value.
    
    Args:
        key: Configuration key name
        default: Default value if key not found
        
    Returns:
        Configuration value or default
    """
    config = get_config()
    return config.get(key, default)


# Convenience functions for common use cases
def get_coveo_config() -> Dict[str, str]:
    """Get Coveo-specific configuration."""
    config = get_config()
    return {
        'org_id': config['COVEO_ORG_ID'],
        'api_key': config['COVEO_SEARCH_API_KEY'],
        'answering_config_id': config['COVEO_ANSWERING_CONFIG_ID'],
        'platform_url': config['COVEO_PLATFORM_URL'],
        'search_hub': config['COVEO_SEARCH_HUB']
    }


def get_cognito_config() -> Dict[str, str]:
    """Get Cognito-specific configuration."""
    config = get_config()
    return {
        'user_pool_id': config['COGNITO_USER_POOL_ID'],
        'client_id': config['COGNITO_CLIENT_ID'],
        'domain': config['COGNITO_DOMAIN']
    }


def get_bedrock_config() -> Dict[str, Optional[str]]:
    """Get Bedrock Agent configuration (may be None if not configured)."""
    config = get_config()
    return {
        'agent_id': config.get('BEDROCK_AGENT_ID'),
        'agent_alias_id': config.get('BEDROCK_AGENT_ALIAS_ID'),
        'model_id': config.get('BEDROCK_MODEL_ID')
    }


def get_agentcore_config() -> Dict[str, Optional[str]]:
    """Get AgentCore + MCP configuration (may be None if not configured)."""
    config = get_config()
    return {
        'gateway_url': config.get('AGENTCORE_GATEWAY_URL'),
        'mcp_server_url': config.get('MCP_SERVER_URL')
    }
