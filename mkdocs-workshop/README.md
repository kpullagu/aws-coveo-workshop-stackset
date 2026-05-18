# Coveo + AWS Workshop Documentation

This folder contains the MkDocs documentation site for the Coveo + AWS Workshop.

## Workshop Overview

A hands-on workshop exploring three AI integration patterns with Coveo and AWS:

1. **Lab 1** – Direct Coveo APIs (Search, Passages, Answer)
2. **Lab 2** – AWS Bedrock AgentCore + Coveo Hosted MCP (memory-enabled chatbot)
3. **Lab 3** – Native Coveo Search Agent with Headless (no AWS agent runtime)

## Documentation Structure

```
mkdocs-workshop/
├── mkdocs.yml                    # MkDocs configuration and nav
├── requirements.txt              # Python dependencies (mkdocs-material, mermaid2)
├── docs/
│   ├── index.md                  # Workshop home page
│   ├── lab1/
│   │   ├── index.md              # Lab 1 exercises
│   │   ├── architecture.md       # Direct Coveo API architecture
│   │   └── queries.md            # Sample queries for Lab 1
│   ├── lab2/
│   │   ├── index.md              # Lab 2 exercises
│   │   └── architecture.md       # AgentCore + Hosted MCP architecture
│   ├── lab3/
│   │   ├── index.md              # Lab 3 exercises
│   │   ├── architecture.md       # Native Search Agent architecture
│   │   ├── queries.md            # Sample queries for Lab 3
│   │   └── instructor-guide.md   # Preflight and demo script
│   ├── resources/
│   │   ├── code.md               # Annotated project file structure
│   │   ├── diagrams.md           # Architecture diagrams for all labs
│   │   └── reading.md            # Official documentation links
│   ├── images/                   # Workshop screenshots and diagrams
│   └── assets/                   # Custom CSS and JS
└── retired/                      # Old lab content (not in published nav)
```

## Published Site

The site is automatically deployed to GitHub Pages on every push to `main`:

**https://kpullagu.github.io/aws-coveo-workshop-stackset/**

## Local Development

### Prerequisites

- Python 3.8 or higher

### Setup

```bash
cd mkdocs-workshop
pip install -r requirements.txt
mkdocs serve
```

Open `http://127.0.0.1:8000` in your browser.

### Build Static Site

```bash
mkdocs build
```

The static site is generated in `site/` (excluded from git via `.gitignore`).

## Technology Stack

- [MkDocs](https://www.mkdocs.org/) – static site generator
- [Material for MkDocs](https://squidfunk.github.io/mkdocs-material/) – theme
- [mermaid2](https://github.com/fralau/mkdocs-mermaid2-plugin) – diagram rendering
- GitHub Actions – automated deploy on push to `main`
- GitHub Pages – hosting

## Security

This documentation contains no secrets, API keys, or credentials. All sensitive
values use environment variable placeholders.
