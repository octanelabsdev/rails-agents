# Rails Development Team Agents

A complete team of specialized AI agents for Ruby on Rails development. Drop these agents into any Rails project and they'll analyze your codebase, learn your patterns, and help you build features following your established conventions.

> **This is an agent bundle — one example payload for [the harness](https://github.com/octanelabsdev/harness).**
> The harness (a separate, stack-agnostic repo) provides the *mechanism* — enforcement hooks
> (session banner, verification gate, pipeline gate), guardrail playbooks, and the PM delivery
> pipeline — and expects you to **bring your own agents**. This repo is the Rails set of those
> agents. Install the harness for the mechanism; drop these agents into your project's
> `.claude/agents/` (see [QUICKSTART](QUICKSTART.md)). The generic hooks/guardrails/PM pipeline
> that used to live here now live in the harness.

## 🎯 Overview

These agents form a **codebase-aware Rails development team** that:
- ✅ **Analyzes your codebase** on first use to learn your patterns
- ✅ **Matches your style** (testing framework, authentication, frontend stack)
- ✅ **Works together** as a cohesive team
- ✅ **Integrates with Agent OS** workflows
- ✅ **Follows Rails best practices** while respecting your choices

## 👥 The Team

### 🏗️ @rails-architect
**Technical Lead & System Designer**

**Model**: Opus (`model: opus` — tracks the latest Opus)
**Tools**: Read, Glob, Grep, Bash

**Responsibilities**:
- Architectural decisions and system design
- Where code should live and how to organize it
- Database schema design
- Feature planning and technical approach

**Use When**:
- Planning new features
- Making architectural decisions
- Designing database schemas
- Evaluating technical approaches

---

### 🗄️ @rails-model-engineer
**Data Layer Specialist**

**Model**: Sonnet (`model: sonnet` — tracks the latest Sonnet)
**Tools**: Read, Write, Edit, Glob, Grep, Bash

**Responsibilities**:
- Models, migrations, and database design
- ActiveRecord associations and validations
- Concerns and query optimization
- Data layer implementation

**Use When**:
- Creating or modifying models
- Writing migrations
- Extracting concerns
- Optimizing database queries

---

### 🎛️ @rails-controller-engineer
**API & Request Handler**

**Model**: Sonnet (`model: sonnet` — tracks the latest Sonnet)
**Tools**: Read, Write, Edit, Glob, Grep, Bash

**Responsibilities**:
- Controllers and routing
- Authentication and authorization
- Strong parameters
- API endpoint design

**Use When**:
- Creating controllers and routes
- Implementing authentication/authorization
- Building API endpoints
- Handling request/response logic

---

### 🎨 @rails-hotwire-engineer
**Frontend & Interaction Specialist**

**Model**: Sonnet (`model: sonnet` — tracks the latest Sonnet)
**Tools**: Read, Write, Edit, Glob, Grep, Bash

**Responsibilities**:
- Views, partials, and layouts
- JavaScript interactions (Hotwire, React, Vue, etc.)
- Frontend components and UI
- Real-time features

**Use When**:
- Creating views and UI
- Adding JavaScript functionality
- Building frontend components
- Implementing real-time features

---

### 🧪 @rails-testing-expert
**Quality Assurance & Testing**

**Model**: Opus (`model: opus` — tracks the latest Opus)
**Tools**: Read, Write, Edit, Glob, Grep, Bash

**Responsibilities**:
- Comprehensive test coverage
- Test fixtures/factories
- Integration and system tests
- Test quality and best practices

**Use When**:
- Writing any tests
- Improving test coverage
- Creating fixtures or factories
- Testing new features

---

### 🔒 @rails-security-performance
**Security & Performance Auditor**

**Model**: Opus (`model: opus` — tracks the latest Opus)
**Tools**: Read, Glob, Grep, Bash

**Responsibilities**:
- Security audits and vulnerability reviews
- Authorization and authentication checks
- Performance optimization
- Query optimization and N+1 prevention

**Use When**:
- Security reviews
- Performance optimization
- Auditing code for vulnerabilities
- Production readiness checks

---

### 🧐 @dhh-code-reviewer
**DHH-Standards Code Reviewer — Mandatory Post-Write Gate**

**Model**: Opus (`model: opus` — tracks the latest Opus)
**Tools**: Read, Write, Edit, Glob, Grep, Bash

**Responsibilities**:
- Reviews newly written or modified Ruby/Rails and JavaScript/Svelte code against DHH's exacting standards
- Flags non-idiomatic patterns, unnecessary complexity, and Rails-convention violations
- Provides concrete refactoring suggestions with before/after examples
- Cross-references existing codebase patterns for consistency

**Use When**:
- **Always**, after any code-writing task by you or a sub-agent (this is the **mandatory review gate** — see global CLAUDE.md "MANDATORY: DHH Code Review Gate")
- After refactoring Ruby, Rails, JavaScript, or Svelte code
- Before proposing a commit or marking a task complete
- When auditing whether a feature would be "Rails-core worthy"

> **Blocking gate:** Code-writing tasks are not complete until `@dhh-code-reviewer` has run and any Critical Issues have been resolved. The user can waive per-task with explicit opt-out language ("skip review", "no review", "ship without review"). Acceptance of code is not a waiver.

---

### ⚡ @rails-background-jobs
**Background Jobs & Async Processing Specialist**

**Model**: Sonnet (`model: sonnet` — tracks the latest Sonnet)
**Tools**: Read, Write, Edit, Glob, Grep, Bash

**Responsibilities**:
- Background job implementation (Solid Queue, Sidekiq, etc.)
- Recurring/scheduled task setup
- Job retry strategies and error handling
- Queue configuration and prioritization
- Multi-tenant job context preservation

**Use When**:
- Creating background jobs
- Setting up recurring tasks
- Implementing async processing
- Configuring job queues and workers
- Adding webhook delivery or notifications

---

### 🔐 @rails-authentication
**Authentication & Identity Specialist**

**Model**: Sonnet (`model: sonnet` — tracks the latest Sonnet)
**Tools**: Read, Write, Edit, Glob, Grep, Bash

**Responsibilities**:
- Passwordless/magic link authentication
- Session management and security
- Identity vs User model separation
- OAuth integration
- Rate limiting on auth endpoints

**Use When**:
- Implementing authentication systems
- Setting up magic link login
- Managing user sessions
- Adding OAuth providers
- Multi-tenant user/identity patterns

---

### 🧩 @rails-viewcomponent-engineer
**ViewComponent & Component-Driven UI Specialist**

**Model**: Sonnet (`model: sonnet` — tracks the latest Sonnet)
**Tools**: Read, Write, Edit, Glob, Grep, Bash

**Responsibilities**:
- ViewComponent design and implementation
- Slot patterns (single, multiple, polymorphic)
- Component variants and configuration
- Stimulus integration within components
- Component testing and previews

**Use When**:
- Building reusable UI components with ViewComponent
- Designing slot-based component APIs
- Creating component previews and lookbooks
- Integrating Stimulus controllers with components
- Refactoring partials into ViewComponents

---

### 📧 @rails-mailer
**Email & Mailer Specialist**

**Model**: Sonnet (`model: sonnet` — tracks the latest Sonnet)
**Tools**: Read, Write, Edit, Glob, Grep, Bash

**Responsibilities**:
- Action Mailer implementation
- Email templates (HTML + text)
- Mailer previews and testing
- Delivery configuration (SMTP, Postmark, SendGrid)
- Interceptors and observers
- Async delivery patterns

**Use When**:
- Creating transactional emails
- Setting up mailer previews
- Configuring email delivery for environments
- Implementing parameterized mailers
- Adding email attachments

---

### 🚢 @rails-deployment
**Deployment & Infrastructure Specialist**

**Model**: Sonnet (`model: sonnet` — tracks the latest Sonnet)
**Tools**: Read, Write, Edit, Glob, Grep, Bash

**Responsibilities**:
- Kamal deployment configuration
- Docker multi-stage builds
- Production environment setup
- SSL/proxy configuration
- Health checks and monitoring
- Secret management
- Server operations and troubleshooting

**Use When**:
- Setting up Kamal for a new project
- Configuring Docker builds
- Managing production deployments
- Troubleshooting production issues
- Setting up CI/CD pipelines
- Configuring SSL and proxies

---

### 📦 @rails-data-migration
**Data Migration & Seeds Specialist**

**Model**: Sonnet (`model: sonnet` — tracks the latest Sonnet)
**Tools**: Read, Write, Edit, Glob, Grep, Bash

**Responsibilities**:
- Data migrations (separate from schema migrations)
- Seed data management and organization
- Backfill scripts and bulk data operations
- Maintenance tasks and cleanup jobs

**Use When**:
- Backfilling data after schema changes
- Managing seed data across environments
- Bulk updating or transforming records
- Cleaning up orphaned or duplicate data

---

### 🧠 @rails-domain-logic
**Domain Logic & PORO Specialist**

**Model**: Sonnet (`model: sonnet` — tracks the latest Sonnet)
**Tools**: Read, Write, Edit, Glob, Grep, Bash

**Responsibilities**:
- Rich domain model patterns (preferred over service objects)
- Service objects for multi-model orchestration
- Form objects for complex forms
- Query objects for advanced filtering
- Plain Ruby objects and value objects

**Use When**:
- Implementing complex business logic
- Building multi-step workflows (signup, checkout)
- Creating form objects for non-model-backed forms
- Extracting query logic from controllers

---

### 📡 @rails-api-serializer
**API Serialization & Response Specialist**

**Model**: Sonnet (`model: sonnet` — tracks the latest Sonnet)
**Tools**: Read, Write, Edit, Glob, Grep, Bash

**Responsibilities**:
- JSON API response formatting (jbuilder, Blueprinter, Alba)
- API versioning strategies
- Pagination (Pagy, cursor-based)
- Webhook payload serialization
- Response envelope patterns

**Use When**:
- Building JSON API endpoints
- Adding pagination to collection endpoints
- Designing webhook payloads
- Setting up API versioning

---

### ♿ @rails-accessibility
**Accessibility & Inclusive Design Specialist**

**Model**: Sonnet (`model: sonnet` — tracks the latest Sonnet)
**Tools**: Read, Write, Edit, Glob, Grep, Bash

**Responsibilities**:
- WCAG 2.1 AA compliance
- Semantic HTML and ARIA attributes
- Keyboard navigation and focus management
- Screen reader support
- Accessible forms and dynamic content

**Use When**:
- Auditing pages for accessibility issues
- Adding keyboard navigation to components
- Making forms accessible with proper labels and errors
- Ensuring Turbo/Stimulus updates are announced to screen readers

---

### 🌐 @rails-i18n
**Internationalization & Localization Specialist**

**Model**: Haiku (`model: haiku` — tracks the latest Haiku)
**Tools**: Read, Write, Edit, Glob, Grep, Bash

**Responsibilities**:
- Locale file organization and management
- Translation helpers in views and controllers
- Date, time, and number formatting
- Pluralization rules
- Multi-language support

**Use When**:
- Adding multi-language support
- Centralizing flash messages and error strings
- Formatting dates and numbers for locales
- Setting up locale switching

---

### 📎 @rails-active-storage
**File Upload & Storage Specialist**

**Model**: Sonnet (`model: sonnet` — tracks the latest Sonnet)
**Tools**: Read, Write, Edit, Glob, Grep, Bash

**Responsibilities**:
- Active Storage setup and configuration
- Image variants and processing
- Direct uploads with progress
- Cloud storage (S3, GCS) configuration
- Attachment validations and security

**Use When**:
- Adding file uploads to models
- Configuring image variants
- Setting up direct uploads with drag-and-drop
- Configuring cloud storage for production

---

## 🚀 How to Use

### Claude Code Sub-Agents

These agents are designed to work as **Claude Code sub-agents**. Claude Code looks for agent definitions in the `.claude/agents/` directory of your project.

**How it works:**
1. Place agent `.md` files in `.claude/agents/` (or a `commands/` directory)
2. Reference agents using `@agent-name` syntax in Claude Code
3. The agent's instructions, model, and tools are loaded automatically
4. Each agent can analyze and work within your project context

### First Time Setup

1. **Drop the agents into your Rails project**:
   ```bash
   # Create the agents directory if it doesn't exist
   mkdir -p /path/to/your/rails/project/.claude/agents

   # Copy all agent files
   cp *.md /path/to/your/rails/project/.claude/agents/
   ```

2. **On first use, each agent will**:
   - Analyze your codebase patterns
   - Learn your conventions
   - Document what they observe
   - Match your existing style

### Basic Usage

```markdown
# Get architectural guidance
@rails-architect: How should I implement user notifications?

# Implement a model
@rails-model-engineer: Create a Notification model with polymorphic associations

# Build the API
@rails-controller-engineer: Add controller and routes for notifications

# Create the UI
@rails-hotwire-engineer: Build the notification UI with real-time updates

# Write tests
@rails-testing-expert: Write comprehensive tests for notifications

# Security review
@rails-security-performance: Audit the notification system for security issues
```

### Team Workflow

**For a new feature**, follow this workflow:

1. **Architecture** → @rails-architect designs the approach
2. **Data Layer** → @rails-model-engineer implements models
3. **Data Migrations** → @rails-data-migration handles seeds/backfills
4. **Domain Logic** → @rails-domain-logic implements service/form/query objects
5. **API Layer** → @rails-controller-engineer builds controllers
6. **API Serialization** → @rails-api-serializer shapes JSON responses
7. **Frontend** → @rails-hotwire-engineer creates views
8. **Components** → @rails-viewcomponent-engineer builds reusable UI
9. **Accessibility** → @rails-accessibility ensures WCAG compliance
10. **Internationalization** → @rails-i18n adds translations
11. **File Uploads** → @rails-active-storage handles attachments
12. **Email** → @rails-mailer implements notifications (if needed)
13. **Testing** → @rails-testing-expert writes tests
14. **Security/Performance Review** → @rails-security-performance audits
15. **DHH Code Review (mandatory gate)** → @dhh-code-reviewer reviews against Rails-core standards
16. **Deploy** → @rails-deployment handles production release

> Step 15 is a **blocking gate**: any task that produced Ruby, JavaScript, Svelte, or ViewComponent code is not complete until `@dhh-code-reviewer` has run and Critical Issues have been resolved. See global CLAUDE.md ("MANDATORY: DHH Code Review Gate") for the full enforcement rules and the user opt-out language.

### Example: Adding a New Feature

```markdown
## Feature: User Notifications

### Step 1: Architecture
@rails-architect: Design a notification system with:
- Multiple notification types (mention, like, comment)
- Mark as read functionality
- Real-time delivery

### Step 2: Data Layer
@rails-model-engineer: Implement the Notification model based on the architecture

### Step 3: API
@rails-controller-engineer: Create NotificationsController with index, show, mark_read actions

### Step 4: UI
@rails-hotwire-engineer: Build notification dropdown with unread count

### Step 5: Testing
@rails-testing-expert: Write model, controller, and system tests

### Step 6: Review
@rails-security-performance: Audit for N+1 queries and authorization issues
```

## 🧠 How They Learn Your Codebase

On first invocation, each agent:

1. **Reads representative files** from your codebase
2. **Documents patterns** they observe
3. **Matches your style** in all implementations

### What They Learn

- **Rails version** and feature usage
- **Database choice** (PostgreSQL, MySQL, SQLite)
- **Testing framework** (RSpec vs Minitest)
- **Frontend stack** (Hotwire, React, Vue, traditional)
- **Authentication** (Devise, custom, etc.)
- **Authorization** (Pundit, CanCanCan, custom)
- **Background jobs** (Sidekiq, Resque, Solid Queue)
- **Code organization** (concerns, service objects, etc.)
- **Naming conventions** and code style

## 🤝 Agent Collaboration

Agents naturally work together:

```markdown
# Architect designs → Model implements → Controller exposes →
# Frontend visualizes → Testing validates → Security secures
```

They reference each other:
- "Based on @rails-architect's design..."
- "Following the pattern @rails-model-engineer established..."
- "Coordinating with @rails-controller-engineer on strong parameters..."

## 🔗 Integration with Agent OS

These agents enhance Agent OS workflows:

```markdown
# 1. Create product specs
@.agent-os/instructions/core/create-spec.md

# 2. Get architectural review
@rails-architect: Review the spec and provide technical design

# 3. Implement with the team
@.agent-os/instructions/core/implement-spec.md
(Agents automatically contribute during implementation)

# 4. Test thoroughly
@rails-testing-expert: Ensure comprehensive coverage

# 5. Security audit
@rails-security-performance: Final review before deployment
```

Agents reference:
- `.agent-os/product/overview.md` - Product vision
- `.agent-os/product/roadmap.md` - Feature priorities
- `.agent-os/product/tech-stack.md` - Technology decisions

## 📋 Best Practices

### 1. Ask the Right Agent

Match your question to the agent's expertise:
- Architecture questions → @rails-architect
- Data modeling → @rails-model-engineer
- Data migrations & seeds → @rails-data-migration
- Business logic & POROs → @rails-domain-logic
- API design → @rails-controller-engineer
- API serialization & pagination → @rails-api-serializer
- UI work → @rails-hotwire-engineer
- ViewComponents → @rails-viewcomponent-engineer
- Accessibility & WCAG → @rails-accessibility
- Translations & i18n → @rails-i18n
- File uploads & storage → @rails-active-storage
- Testing → @rails-testing-expert
- Security/Performance → @rails-security-performance
- Post-write code review (mandatory gate) → @dhh-code-reviewer
- Background jobs → @rails-background-jobs
- Authentication → @rails-authentication
- Email/mailers → @rails-mailer
- Deployment/infrastructure → @rails-deployment
- Git workflow (branches, commits, PRs, releases) → @rails-git-workflow

### 2. Provide Context

```markdown
# ✅ Good
@rails-model-engineer: Add polymorphic Comments that work on Posts and Photos

# ❌ Vague
@rails-model-engineer: Add comments
```

### 3. Follow the Workflow

Start with architecture, implement layer by layer, test thoroughly, audit for security.

### 4. Trust the Analysis

On first use, agents analyze your codebase and match your patterns. Trust their recommendations—they're based on what you're already doing.

### 5. Iterate Together

```markdown
@rails-architect: Design user following system
# Review design, provide feedback
@rails-model-engineer: Implement the design from @rails-architect
# Iterate as needed
```

## 🎯 What Makes These Agents Special

### Codebase-Aware
They analyze and match YOUR patterns, not generic examples.

### Team Players
They work together as a cohesive development team.

### Consistent
They ensure new code matches existing conventions.

### Comprehensive
From architecture to testing to security—full coverage.

### Framework Agnostic
They adapt to your choices: RSpec or Minitest, Hotwire or React, Devise or custom auth.

## 📚 Agent Details

Each agent file contains:
- **Model tier** (`opus` / `sonnet` / `haiku` alias in the frontmatter; never a pinned version)
- **Available tools** for their work
- **Analysis instructions** for learning your codebase
- **Best practices** for Rails development
- **Code examples** showing common patterns
- **Integration guidelines** with other agents
- **Anti-patterns** to avoid

## 🔄 Updating & Customizing Agents

### Agent File Structure

Each agent file follows this structure:

```markdown
---
name: agent-name
description: Brief description shown in Claude Code
model: sonnet
tools: Read,Write,Edit,Glob,Grep,Bash
---

# Agent Title

[Role description and instructions]

## Your First Task: Analyze the Codebase
[Instructions for learning project patterns]

## Core Patterns
[Code examples and best practices]

## Testing Patterns
[Both Minitest and RSpec examples]

## Best Practices
[Do's and Don'ts]

## Integration with Other Agents
[Cross-references to related agents]
```

### Frontmatter Options

| Field | Description | Values |
|-------|-------------|--------|
| `name` | Agent identifier (used with `@agent-name`) | kebab-case string |
| `description` | Short description shown in Claude Code UI | String |
| `model` | Claude model to use | `sonnet`, `opus`, `haiku` |
| `tools` | Comma-separated list of allowed tools | `Read,Write,Edit,Glob,Grep,Bash` |

### Adding Project-Specific Patterns

To add patterns from your own codebase:

1. **Identify the pattern** in your codebase
2. **Extract a minimal example** that demonstrates the pattern
3. **Add it to the relevant agent** under "Advanced Patterns" or create a new section
4. **Include both test frameworks** (Minitest and RSpec) when applicable

Example addition to `rails-model-engineer.md`:

```markdown
## Your Project's Patterns

### Soft Delete Pattern

Your codebase uses soft deletes via `discarded_at`:

\`\`\`ruby
# app/models/concerns/discardable.rb
module Discardable
  extend ActiveSupport::Concern

  included do
    scope :kept, -> { where(discarded_at: nil) }
    scope :discarded, -> { where.not(discarded_at: nil) }
  end

  def discard
    update!(discarded_at: Time.current)
  end

  def kept?
    discarded_at.nil?
  end
end
\`\`\`

Always use this pattern instead of `dependent: :destroy` for user-facing records.
```

### Creating a New Agent

1. **Create a new markdown file** in the agents directory:
   ```bash
   touch rails-your-specialty.md
   ```

2. **Add the frontmatter**:
   ```markdown
   ---
   name: rails-your-specialty
   description: Your Specialty Expert - brief description
   model: sonnet
   tools: Read,Write,Edit,Glob,Grep,Bash
   ---
   ```

3. **Include these sections**:
   - Role description
   - "Your First Task: Analyze the Codebase" section
   - Core patterns with code examples
   - Testing patterns (both Minitest and RSpec)
   - Best practices (Do's and Don'ts)
   - Integration with other agents

4. **Update README.md** to include your new agent

### Enhancing Agents from Your Codebase

Use Claude Code to help analyze your codebase and extract patterns:

```markdown
@claude Analyze our app/models/concerns/ directory and identify patterns
that should be added to rails-model-engineer.md. Format them as code
examples with explanations.
```

```markdown
@claude Review our app/jobs/ directory and suggest additions to
rails-background-jobs.md based on our job patterns.
```

### Best Practices for Agent Updates

**Do:**
- Keep examples minimal and focused
- Include both Minitest and RSpec examples for testing patterns
- Add "Use When" guidance for new patterns
- Cross-reference related agents
- Match the existing formatting style
- Test patterns in your actual codebase first

**Don't:**
- Add overly complex examples
- Include sensitive/proprietary code
- Remove existing patterns (add alongside them)
- Forget to update the "Integration with Other Agents" section
- Skip the "Your First Task" analysis instructions

### Keeping Agents in Sync

When your codebase evolves:

1. **Periodic review**: Review agents quarterly against your codebase
2. **Pattern extraction**: When you solve something novel, add it to the relevant agent
3. **Deprecation notes**: Mark outdated patterns as deprecated rather than removing
4. **Version notes**: Consider adding a changelog section for major updates

```markdown
## Changelog

### 2024-01
- Added soft delete pattern from Project X
- Updated authentication to use magic links
- Deprecated Devise patterns (migrated to custom auth)
```

## ❓ Questions & Troubleshooting

**Q: Do I need all agents?**
A: No! Use the ones you need. They work independently or together.

**Q: What if my project uses RSpec instead of Minitest?**
A: The testing agent analyzes your `spec/` directory and adapts automatically.

**Q: Can I customize the agents?**
A: Yes! Edit the agent files to add project-specific patterns or guidelines.

**Q: Do they work with Rails API-only apps?**
A: Yes! They adapt to your Rails configuration and won't suggest view code if you don't have views.

**Q: What about monolithic vs modular Rails apps?**
A: They analyze your structure and follow your organization patterns.

## 🤝 Contributing

Found a pattern these agents should handle better? Edit the agent files to add:
- New pattern examples
- Additional best practices
- Better analysis instructions
- More comprehensive examples

## 📄 License

These agents are designed to be dropped into any Rails project. Use them freely in your development workflow.

---

**Built for**: Any Ruby on Rails Application
**Version**: 2.0
**Models**: Opus (architect, security, testing-expert, dhh-code-reviewer, copywriter) / Haiku (i18n) / Sonnet (all others). Aliases, so agents track the latest model of each tier.
**Integration**: Agent OS Compatible