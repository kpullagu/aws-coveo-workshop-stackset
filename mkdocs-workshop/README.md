# Coveo + AWS Bedrock Workshop Documentation

This repository contains the documentation for the Coveo + AWS Bedrock Workshop, built with MkDocs Material.

## 🎯 Workshop Overview

A hands-on 90-minute workshop exploring three progressive AI integration patterns:
1. **Lab 1**: Direct Coveo API Integration
2. **Lab 2**: Bedrock Agent with Coveo Passage Retrieval Tool
3. **Lab 3**: Bedrock AgentCore with Coveo Hosted MCP
4. **Lab 4**: Multi-Turn Conversations and Use Cases

## 📚 Documentation Structure

```
mkdocs-workshop/
├── docs/
│   ├── index.md              # Home page
│   ├── lab1/                 # Lab 1: Coveo Discovery
│   ├── lab2/                 # Lab 2: Bedrock Agent
│   ├── lab3/                 # Lab 3: AgentCore + Hosted MCP
│   ├── lab4/                 # Lab 4: Chatbot & Use Cases
│   ├── resources/            # Additional resources
│   ├── images/               # Workshop screenshots
│   └── assets/               # Custom CSS/JS
├── mkdocs.yml                # MkDocs configuration
└── requirements.txt          # Python dependencies
```

## 🚀 Local Development

### Prerequisites

- Python 3.8 or higher
- pip

### Setup

1. Clone the repository:
```bash
git clone <your-repo-url>
cd <repo-name>/mkdocs-workshop
```

2. Install dependencies:
```bash
pip install -r requirements.txt
```

3. Run local development server:
```bash
mkdocs serve
```

4. Open your browser to `http://127.0.0.1:8000`

### Build Static Site

```bash
mkdocs build
```

The static site will be generated in the `site/` directory.

## 🌐 GitHub Pages Deployment

This repository is configured to automatically deploy to GitHub Pages using GitHub Actions.

### Setup Instructions

1. **Enable GitHub Pages**:
   - Go to your repository Settings
   - Navigate to Pages (under Code and automation)
   - Under "Build and deployment":
     - Source: Select "GitHub Actions"

2. **Push to main branch**:
   - The workflow will automatically trigger
   - Your site will be available at: `https://<username>.github.io/<repo-name>/`

3. **Manual deployment** (if needed):
   - Go to Actions tab
   - Select "Deploy MkDocs to GitHub Pages"
   - Click "Run workflow"

### Custom Domain (Optional)

To use a custom domain:
1. Add a `CNAME` file to `mkdocs-workshop/docs/` with your domain
2. Configure DNS settings with your domain provider
3. Update `site_url` in `mkdocs.yml`

## 📝 Content Guidelines

### Adding New Pages

1. Create a new `.md` file in the appropriate directory
2. Add the page to `nav` section in `mkdocs.yml`
3. Use proper markdown formatting with blank lines before lists

### Images

- Place images in `docs/images/`
- Reference with relative paths: `![Alt text](../images/filename.png)`

### Code Examples

Use placeholder values for sensitive information:
```python
COVEO_API_KEY = os.environ['COVEO_API_KEY']  # ✅ Good
COVEO_API_KEY = 'actual-key-here'            # ❌ Never do this
```

## 🔒 Security

This documentation is safe for public repositories:
- ✅ No API keys or secrets
- ✅ No credentials
- ✅ Only instructional placeholders
- ✅ Environment variable examples

**Note**: Actual workshop infrastructure (AWS resources, Coveo org) is deployed separately and not included in this repository.

## 🛠️ Technology Stack

- **MkDocs**: Static site generator
- **Material for MkDocs**: Theme
- **Mermaid**: Diagrams
- **GitHub Actions**: CI/CD
- **GitHub Pages**: Hosting

## 📖 Additional Resources

- [MkDocs Documentation](https://www.mkdocs.org/)
- [Material for MkDocs](https://squidfunk.github.io/mkdocs-material/)
- [Mermaid Diagrams](https://mermaid.js.org/)

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test locally with `mkdocs serve`
5. Submit a pull request

## 📄 License

Copyright © 2025 AWS + Coveo

## 📞 Support

For questions about the workshop content or documentation, please contact your workshop instructor or open an issue in this repository.
