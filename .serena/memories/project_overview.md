# OmniArchive Project Overview

## Purpose
OmniArchive is an Elixir/Phoenix web application that converts PDFs and image sources into searchable IIIF-compatible digital assets through ingestion, review, approval, and delivery workflows. The current inspector UI includes a 5-step wizard that is especially PDF-centric, while shared ingestion and delivery modules should remain generic enough to support image-source workflows as well.

## Tech Stack
- **Language**: Elixir 1.15+
- **Web Framework**: Phoenix 1.8+
- **Database**: PostgreSQL 15+
- **Image Processing**: Vix (libvips wrapper for PTIF generation and tile cutting)
- **Frontend**: Phoenix LiveView, Tailwind, esbuild
- **Standards**: IIIF v3.0
- **YAML Processing**: yaml_elixir (~> 2.9)

## Key Modules Structure
- OmniArchive.Search: Search functionality
- OmniArchive.Ingestion.*: Source ingestion/processing (currently PDF-heavy, but designed to stay generic for image sources too)
- OmniArchive.IIIF.*, OmniArchiveWeb.IIIF.*: IIIF distribution
- OmniArchive.Pipeline.*: Pipeline processing
- OmniArchiveWeb.*: Web interface

## Code Conventions
- Elixir conventions with LiveView patterns
- Japanese language used in UI, documentation, and code comments
- Module documentation with Japanese descriptions
- Atom-based naming for fields and parameters
