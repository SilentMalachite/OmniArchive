# Development Commands for OmniArchive

## Setup & Dependencies
```bash
mix setup                          # Install deps, create DB, run migrations
mix deps.get                       # Install dependencies
mix ecto.setup                     # Create DB, run migrations, seed data
```

## Testing
```bash
mix test                           # Run all tests
mix test test/path/to/test_file.exs  # Run specific test file
mix precommit                      # Compile with warnings as errors, format, test
```

## Linting & Quality
```bash
mix format                         # Format code
mix credo --strict                 # Lint with Credo
mix dialyzer                       # Type check
mix sobelow --config               # Security scan
mix review                         # Full quality review (compile, credo, sobelow, dialyzer)
```

## Development Server
```bash
mix phx.server                     # Start Phoenix development server
OMNI_ARCHIVE_PROFILE_YAML=$PWD/priv/profiles/example_profile.yaml mix phx.server
```

## Build & Release
```bash
mix assets.build                   # Build CSS/JS assets
mix assets.deploy                  # Deploy assets (minified)
```

## Asset Management
```bash
mix esbuild.install --if-missing   # Install esbuild
mix tailwind.install --if-missing  # Install Tailwind
```

## Database Operations
```bash
mix ecto.create                    # Create database
mix ecto.migrate                   # Run migrations
mix ecto.reset                     # Drop and recreate database with seeds
```
