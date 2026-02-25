-- Kessel-in-a-Box: Inventory Database Initialization
-- The real insights-host-inventory runs its own Alembic migrations to create tables.
-- This script only sets up extensions and permissions needed before migrations run.
-- NOTE: kessel-inventory-api (real) runs its own migrations via 'inventory-api migrate'

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- Success message
DO $$
BEGIN
    RAISE NOTICE 'Inventory database initialized successfully';
END $$;
