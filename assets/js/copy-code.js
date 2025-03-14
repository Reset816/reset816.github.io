document.addEventListener('DOMContentLoaded', function() {
  // Add copy buttons to all code blocks
  const codeBlocks = document.querySelectorAll('div.highlighter-rouge, figure.highlight');
  
  codeBlocks.forEach(function(codeBlock) {
    // Create copy button
    const copyButton = document.createElement('button');
    copyButton.className = 'copy-button';
    copyButton.setAttribute('aria-label', 'Copy code');
    copyButton.setAttribute('title', 'Copy code');
    
    // Add the button to the code block
    codeBlock.appendChild(copyButton);
    
    // Add click event listener
    copyButton.addEventListener('click', function() {
      // Get the code content
      const code = codeBlock.querySelector('pre').innerText;
      
      // Copy to clipboard
      navigator.clipboard.writeText(code).then(function() {
        // Visual feedback
        copyButton.classList.add('copied');
        
        // Reset after 2 seconds
        setTimeout(function() {
          copyButton.classList.remove('copied');
        }, 2000);
      }).catch(function(error) {
        console.error('Failed to copy code: ', error);
      });
    });
  });
}); 