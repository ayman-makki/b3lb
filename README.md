# B3LB - BigBlueButton Load Balancer

B3LB is an open source [BigBlueButton API](https://docs.bigbluebutton.org/dev/api.html) load balancer similar to [Scalelite](https://github.com/blindsidenetworks/scalelite). B3LB is based on the [Django](https://www.djangoproject.com/) Python Web framework and is designed to work in large scale-out deployments with 100+ BigBlueButton nodes and high attendee join rates.

**Note:** This fork of B3LB includes significant enhancements for easier deployment, local development, and operational management.

## 🚀 Key Features of This Fork

This repository extends the original B3LB project with the following improvements:

### 🛠️ Automated Installation & Deployment
- **Automated Scripts**: Complete suite of installation scripts for BBB nodes in `scripts/bbb/install/`, including preflight checks and dependency management.
- **Streamlined Setup**: One-command installation (`install-all.sh`) to deploy `b3lb-load`, `b3lb-push`, and `b3lb-cleaner` services.
- **Infrastructure Updates**: Optimized Traefik configuration, CORS support, and static file routing.

### 💻 Local Development Experience
- **Local Dev Support**: Enhanced support for local development with Celery workers and `dlower`.
- **Docker Improvements**: Updated Docker Compose configurations for both local and production environments.
- **Health Checks**: Improved health checks for Celery containers, Redis exporter, and B3LB static services.

### 📊 Enhanced Observability & Management
- **Developer Tools**: Comprehensive `Makefile` with shortcuts for common tasks (`make start`, `make logs`, `make shell`) and B3LB-specific commands (`make addnode`, `make meetingstats`).
- **Logging**: Comprehensive logging configuration for Django and worker nodes.
- **Periodic Tasks**: New management commands for handling periodic tasks.
- **Clean Up**: Automated meeting cleanup service (`b3lb-cleaner`) to handle orphaned meetings.

### ⚡ Performance & Infrastructure
- **Traefik v3**: Updated to Traefik v3 with Hetzner DNS challenge support for automatic SSL.
- **PyPy Support**: Worker nodes can run on PyPy for improved performance.
- **Database**: Optimized PostgreSQL configuration and migrations.

## 📚 Documentation

Detailed documentation is available in the `docs/` directory:

- [**Overview**](docs/00-overview.md): Architecture, technology stack, and core capabilities.
- [**Architecture**](docs/01-architecture.md): System design and component layout.
- [**Database Schema**](docs/02-database-schema.md): Data models and relationships.
- [**Configuration**](docs/04-configuration.md): Environment variables and settings.
- [**Docker Deployment**](docs/05-docker-deployment.md): Guide for deploying with Docker.
- [**Operations**](docs/08-operations.md): Operational manual for ongoing management.

### Node Installation Guide
For instructions on installing the necessary scripts on your BigBlueButton nodes, please refer to the [BBB Node Scripts Installation Guide](scripts/bbb/install/README.md).

## 🏗️ Architecture

B3LB uses a modern technology stack designed for scalability:

- **Web Framework**: Django 5.2.2 (Async enabled)
- **Task Queue**: Celery 5.5.3 with Redis
- **Database**: PostgreSQL
- **Reverse Proxy**: Traefik
- **Static Files**: Caddy

## 📄 License

B3LB is licensed under the **GNU Affero General Public License v3.0** (AGPL-3.0).

---
*This project uses BigBlueButton and is not endorsed or certified by BigBlueButton Inc. BigBlueButton and the BigBlueButton Logo are trademarks of BigBlueButton Inc.*
