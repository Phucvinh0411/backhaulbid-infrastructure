-- ============================================
-- PostgreSQL Init Script
-- Creates separate databases for each service
-- ============================================

CREATE DATABASE backhaulbid_fleet;
CREATE DATABASE backhaulbid_wallet;
CREATE DATABASE backhaulbid_contract;

-- backhaulbid_identity is already created via POSTGRES_DB env var
