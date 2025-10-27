import React, { useState, useEffect } from 'react';
import styled from 'styled-components';
import { motion } from 'framer-motion';
import { FiFilter, FiCheck, FiX, FiChevronDown, FiChevronUp } from 'react-icons/fi';

const SidebarContainer = styled(motion.aside)`
  width: 280px;
  background: rgba(255, 255, 255, 0.95);
  backdrop-filter: blur(20px);
  border-radius: 16px;
  padding: 24px;
  max-height: calc(100vh - 140px);
  overflow-y: auto;
  position: sticky;
  top: 120px;
  box-shadow: 0 8px 32px rgba(0, 0, 0, 0.1);
  
  /* Custom scrollbar styling */
  &::-webkit-scrollbar {
    width: 8px;
  }
  
  &::-webkit-scrollbar-track {
    background: rgba(241, 241, 241, 0.5);
    border-radius: 4px;
  }
  
  &::-webkit-scrollbar-thumb {
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    border-radius: 4px;
  }
  
  &::-webkit-scrollbar-thumb:hover {
    background: linear-gradient(135deg, #764ba2 0%, #667eea 100%);
  }
`;

const SidebarHeader = styled.div`
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 24px;
  padding-bottom: 16px;
  border-bottom: 1px solid #e1e5e9;
`;

const SidebarTitleGroup = styled.div`
  display: flex;
  align-items: center;
  gap: 12px;
`;

const ClearFiltersButton = styled(motion.button)`
  padding: 6px 12px;
  background: #f8f9fa;
  border: 1px solid #e1e5e9;
  border-radius: 6px;
  color: #666;
  cursor: pointer;
  font-size: 12px;
  font-weight: 500;
  transition: all 0.2s ease;

  &:hover {
    background: #e9ecef;
    border-color: #667eea;
    color: #667eea;
  }

  &:disabled {
    opacity: 0.3;
    cursor: not-allowed;
    
    &:hover {
      background: #f8f9fa;
      border-color: #e1e5e9;
      color: #666;
    }
  }
`;

const SidebarTitle = styled.h3`
  font-size: 18px;
  font-weight: 600;
  color: #333;
`;

const ResultsCount = styled.div`
  font-size: 14px;
  color: #666;
  margin-bottom: 24px;
  padding: 12px;
  background: #f8f9fa;
  border-radius: 8px;
  text-align: center;
`;

const FacetGroup = styled.div`
  margin-bottom: 20px;
  border: 1px solid #e1e5e9;
  border-radius: 8px;
  overflow: hidden;
`;

const FacetHeader = styled(motion.div)`
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 12px 16px;
  background: #f8f9fa;
  cursor: pointer;
  border-bottom: ${props => props.isExpanded ? '1px solid #e1e5e9' : 'none'};
  transition: all 0.2s ease;

  &:hover {
    background: #e9ecef;
  }
`;

const FacetTitle = styled.h4`
  font-size: 13px;
  font-weight: 600;
  color: #333;
  text-transform: uppercase;
  letter-spacing: 0.5px;
  margin: 0;
`;

const FacetToggleIcon = styled(motion.div)`
  color: #666;
  display: flex;
  align-items: center;
`;

const FacetContent = styled(motion.div)`
  padding: ${props => props.isExpanded ? '12px 16px' : '0 16px'};
  max-height: ${props => props.isExpanded ? '400px' : '0'};
  overflow-y: ${props => props.isExpanded ? 'auto' : 'hidden'};
  overflow-x: hidden;
  transition: all 0.3s ease;
  
  /* Custom scrollbar styling */
  &::-webkit-scrollbar {
    width: 6px;
  }
  
  &::-webkit-scrollbar-track {
    background: #f1f1f1;
    border-radius: 3px;
  }
  
  &::-webkit-scrollbar-thumb {
    background: #667eea;
    border-radius: 3px;
  }
  
  &::-webkit-scrollbar-thumb:hover {
    background: #764ba2;
  }
`;

const FacetList = styled.div`
  display: flex;
  flex-direction: column;
  gap: 8px;
`;

const FacetItem = styled(motion.div)`
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 8px 12px;
  border-radius: 8px;
  cursor: pointer;
  transition: all 0.2s ease;
  font-size: 14px;

  &:hover {
    background: #f8f9fa;
  }
`;

const FacetCheckbox = styled.input`
  display: none;
`;

const CustomCheckbox = styled.div`
  width: 18px;
  height: 18px;
  border: 2px solid ${props => props.isSelected ? '#667eea' : '#d1d5db'};
  border-radius: 4px;
  display: flex;
  align-items: center;
  justify-content: center;
  transition: all 0.2s ease;
  flex-shrink: 0;
  background: ${props => props.isSelected ? 'linear-gradient(135deg, #667eea 0%, #764ba2 100%)' : 'white'};
  color: ${props => props.isSelected ? 'white' : 'transparent'};
`;

const FacetLabel = styled.span`
  flex: 1;
  color: #333;
  line-height: 1.4;
`;

const FacetCount = styled.span`
  color: #666;
  font-size: 12px;
  background: #e5e7eb;
  padding: 2px 6px;
  border-radius: 10px;
  min-width: 20px;
  text-align: center;
`;

const EmptyState = styled.div`
  text-align: center;
  color: #666;
  font-style: italic;
  padding: 40px 20px;
`;

const facetDisplayNames = {
  project: 'Project',
  documenttype: 'Document Type',
  language: 'Language',
  source: 'Source',
  filetype: 'File Type',
  collection: 'Collection'
};

const Sidebar = ({ facets, selectedFacets, onFacetChange, onClearFilters, totalResults }) => {
  const [expandedFacets, setExpandedFacets] = useState({});

  const handleFacetToggle = (field, value) => {
    const isSelected = selectedFacets[field]?.includes(value) || false;
    console.log('🔄 Toggling facet:', { field, value, isSelected, willBeSelected: !isSelected });
    onFacetChange(field, value, !isSelected);
  };

  const toggleFacetExpansion = (field) => {
    setExpandedFacets(prev => ({
      ...prev,
      [field]: !prev[field]
    }));
  };

  const hasActiveFilters = Object.keys(selectedFacets).length > 0;
  
  console.log('🔍 Sidebar render:', {
    selectedFacets,
    hasActiveFilters,
    facetsCount: facets.length
  });

  // Initialize expanded state for facets with selected values
  useEffect(() => {
    const initialExpanded = {};
    facets.forEach(facet => {
      initialExpanded[facet.field] = selectedFacets[facet.field]?.length > 0 || facet.field === 'project';
    });
    setExpandedFacets(initialExpanded);
  }, [facets, selectedFacets]);

  const formatNumber = (num) => {
    if (num >= 1000000) {
      return (num / 1000000).toFixed(1) + 'M';
    } else if (num >= 1000) {
      return (num / 1000).toFixed(1) + 'K';
    }
    return num.toString();
  };

  const formatFacetValue = (field, value) => {
    if (field === 'documenttype') {
      return value.replace(/_/g, ' ').replace(/\b\w/g, l => l.toUpperCase());
    }
    if (field === 'project') {
      return value.charAt(0).toUpperCase() + value.slice(1);
    }
    if (field === 'filetype') {
      return value.toUpperCase();
    }
    return value;
  };

  if (!facets || facets.length === 0) {
    return (
      <SidebarContainer
        initial={{ opacity: 0, x: -20 }}
        animate={{ opacity: 1, x: 0 }}
        transition={{ duration: 0.5 }}
      >
        <SidebarHeader>
          <FiFilter size={20} color="#667eea" />
          <SidebarTitle>Filters</SidebarTitle>
        </SidebarHeader>
        <EmptyState>
          Search to see available filters
        </EmptyState>
      </SidebarContainer>
    );
  }

  return (
    <SidebarContainer
      initial={{ opacity: 0, x: -20 }}
      animate={{ opacity: 1, x: 0 }}
      transition={{ duration: 0.5 }}
    >
      <SidebarHeader>
        <SidebarTitleGroup>
          <FiFilter size={20} color="#667eea" />
          <SidebarTitle>Filters</SidebarTitle>
        </SidebarTitleGroup>
        <ClearFiltersButton
          onClick={hasActiveFilters ? onClearFilters : undefined}
          disabled={!hasActiveFilters}
          whileHover={{ scale: hasActiveFilters ? 1.05 : 1 }}
          whileTap={{ scale: hasActiveFilters ? 0.95 : 1 }}
        >
          <FiX size={12} style={{ marginRight: '4px' }} />
          Clear All
        </ClearFiltersButton>
      </SidebarHeader>

      {totalResults > 0 && (
        <ResultsCount>
          {formatNumber(totalResults)} results found
        </ResultsCount>
      )}

      {facets.map((facet) => {
        const isExpanded = expandedFacets[facet.field];
        const visibleValues = isExpanded ? facet.values.slice(0, 10) : facet.values.slice(0, 5);
        
        return (
          <FacetGroup key={facet.field}>
            <FacetHeader
              isExpanded={isExpanded}
              onClick={() => toggleFacetExpansion(facet.field)}
              whileHover={{ backgroundColor: '#e9ecef' }}
            >
              <FacetTitle>
                {facetDisplayNames[facet.field] || facet.field}
                {selectedFacets[facet.field]?.length > 0 && (
                  <span style={{ 
                    marginLeft: '8px', 
                    background: '#667eea', 
                    color: 'white', 
                    borderRadius: '10px', 
                    padding: '2px 6px', 
                    fontSize: '10px' 
                  }}>
                    {selectedFacets[facet.field].length}
                  </span>
                )}
              </FacetTitle>
              <FacetToggleIcon
                animate={{ rotate: isExpanded ? 180 : 0 }}
                transition={{ duration: 0.2 }}
              >
                <FiChevronDown size={16} />
              </FacetToggleIcon>
            </FacetHeader>
            
            <FacetContent isExpanded={isExpanded}>
              <FacetList>
                {visibleValues.map((value) => {
                  const isSelected = selectedFacets[facet.field]?.includes(value.value) || false;
                  
                  return (
                    <FacetItem
                      key={value.value}
                      whileHover={{ scale: 1.02 }}
                      whileTap={{ scale: 0.98 }}
                      onClick={(e) => {
                        e.preventDefault();
                        e.stopPropagation();
                        console.log('🔘 Facet clicked:', facet.field, value.value, 'Currently selected:', isSelected);
                        handleFacetToggle(facet.field, value.value);
                      }}
                    >
                      <FacetCheckbox
                        type="checkbox"
                        checked={isSelected}
                        onChange={() => {}} // Handled by onClick
                        style={{ display: 'none' }} // Hide the actual checkbox
                      />
                      <CustomCheckbox isSelected={isSelected}>
                        {isSelected && <FiCheck size={12} />}
                      </CustomCheckbox>
                      <FacetLabel>
                        {formatFacetValue(facet.field, value.value)}
                      </FacetLabel>
                      <FacetCount>
                        {formatNumber(value.numberOfResults)}
                      </FacetCount>
                    </FacetItem>
                  );
                })}
              </FacetList>
            </FacetContent>
          </FacetGroup>
        );
      })}
    </SidebarContainer>
  );
};

export default Sidebar;