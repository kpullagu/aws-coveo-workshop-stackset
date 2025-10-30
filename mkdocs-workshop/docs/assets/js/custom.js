// Custom JavaScript for Coveo + AWS Workshop

// Add copy button functionality to code blocks
document.addEventListener('DOMContentLoaded', function() {
  // Add smooth scrolling to all links
  document.querySelectorAll('a[href^="#"]').forEach(anchor => {
    anchor.addEventListener('click', function (e) {
      e.preventDefault();
      const target = document.querySelector(this.getAttribute('href'));
      if (target) {
        target.scrollIntoView({
          behavior: 'smooth',
          block: 'start'
        });
      }
    });
  });

  // Add external link indicators
  document.querySelectorAll('a[href^="http"]').forEach(link => {
    if (!link.hostname.includes(window.location.hostname)) {
      link.setAttribute('target', '_blank');
      link.setAttribute('rel', 'noopener noreferrer');
      link.classList.add('external-link');
    }
  });

  // Add progress tracking for labs
  const labPages = ['lab1', 'lab2', 'lab3', 'lab4'];
  const currentPath = window.location.pathname;
  
  labPages.forEach((lab, index) => {
    if (currentPath.includes(lab)) {
      const progress = ((index + 1) / labPages.length) * 100;
      console.log(`Workshop Progress: ${progress}%`);
    }
  });

  // Add keyboard shortcuts
  document.addEventListener('keydown', function(e) {
    // Alt + N: Next page
    if (e.altKey && e.key === 'n') {
      const nextLink = document.querySelector('a[title="Next"]');
      if (nextLink) nextLink.click();
    }
    
    // Alt + P: Previous page
    if (e.altKey && e.key === 'p') {
      const prevLink = document.querySelector('a[title="Previous"]');
      if (prevLink) prevLink.click();
    }
  });

  // Add print-friendly styling
  window.addEventListener('beforeprint', function() {
    document.body.classList.add('printing');
  });

  window.addEventListener('afterprint', function() {
    document.body.classList.remove('printing');
  });
});

// Utility function to highlight query examples
function highlightQuery(query) {
  return `<span class="query-highlight">${query}</span>`;
}

// Utility function to format backend mode
function formatBackendMode(mode) {
  const modes = {
    'coveo': 'Coveo Direct API',
    'bedrockAgent': 'Bedrock Agent',
    'coveoMCP': 'Coveo MCP Server'
  };
  return modes[mode] || mode;
}

// Add workshop timer (optional)
function startWorkshopTimer(durationMinutes) {
  const startTime = Date.now();
  const endTime = startTime + (durationMinutes * 60 * 1000);
  
  const timerInterval = setInterval(() => {
    const now = Date.now();
    const remaining = endTime - now;
    
    if (remaining <= 0) {
      clearInterval(timerInterval);
      console.log('Workshop time complete!');
      return;
    }
    
    const minutes = Math.floor(remaining / 60000);
    const seconds = Math.floor((remaining % 60000) / 1000);
    console.log(`Time remaining: ${minutes}:${seconds.toString().padStart(2, '0')}`);
  }, 60000); // Update every minute
}

// Console welcome message
console.log('%c🎓 Welcome to the Coveo + AWS Bedrock Workshop!', 'font-size: 16px; font-weight: bold; color: #0066cc;');
console.log('%cWorkshop Duration: 90 minutes', 'font-size: 12px; color: #666;');
console.log('%cKeyboard Shortcuts: Alt+N (Next), Alt+P (Previous)', 'font-size: 12px; color: #666;');
