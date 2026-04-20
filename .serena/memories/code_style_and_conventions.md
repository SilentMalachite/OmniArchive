# OmniArchive Code Style & Conventions

## Elixir Style
- Follow standard Elixir conventions
- Use atoms for keys and function names
- Pipe operator for chaining operations
- Pattern matching in function heads
- Module-level documentation in Japanese

## Naming Conventions
- Modules: CamelCase (e.g. OmniArchive.DomainProfiles.YamlLoader; profile implementations live under OmniArchive.DomainProfiles.*, while OmniArchive.DomainProfile is the behaviour)
- Functions: snake_case
- Private functions: snake_case with underscore prefix or private module scope
- Variables: snake_case
- Atoms/Fields: snake_case (e.g., :caption, :label, :metadata_fields)

## Phoenix LiveView Patterns
- Use socket.assigns for state management
- Handle events with handle_event/3
- Use hooks for JavaScript integration
- Prefer LiveView over traditional controllers when possible

## YAML Domain Profile Fields
- Field names: lowercase with numbers/underscores, starting with lowercase letter
- Storage types: :core (only for caption/label) or :metadata
- All metadata_fields require :field, :label keys
- :storage key is mandatory
- UI text keys must be complete (heading, description, duplicate_warning, etc.)

## Code Quality Standards
- Type checking with Dialyzer
- Security scanning with Sobelow
- Linting with Credo (strict mode)
- Test coverage tracking
- Pre-commit hooks for warnings-as-errors compilation
