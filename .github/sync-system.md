# Offline‑First Sync System Specification

## Purpose

Design a robust local‑first data architecture where applications work fully offline using **Isar** as the local database and synchronize with a **Laravel API + MySQL** backend. The system must support:

* multi‑device editing
* conflict resolution
* reliable retry
* deterministic sync
* scalability

The UI must always operate on the **local database first**.

---

# Core Principles

1. **Local First**

   * UI reads/writes only from Isar
   * network sync occurs asynchronously

2. **Server As Sync Authority**

   * server resolves conflicts
   * server maintains change log

3. **Deterministic State**

   * every change must have version metadata

4. **Idempotent APIs**

   * duplicate requests must not corrupt data

---

# Architecture Overview

Device

UI

Local Database (Isar)

Sync Engine

REST Sync API

Server Database (MySQL)

Change Log

Other Devices

---

# Required Record Metadata

Every synchronized table must contain the following columns.

id (uuid)
created_at
updated_at
deleted_at
row_version
device_id

Explanation

id
Globally unique identifier generated on client.

row_version
Integer incremented on every modification.

updated_at
Timestamp used for conflict detection.

deleted_at
Soft delete timestamp.

device_id
Identifier of device making change.

---

# UUID Strategy

Use UUID or ULID for all primary keys.

Do NOT use auto increment ids.

Reasons

* allows offline creation
* avoids merge collisions
* safe multi device writes

---

# Local Database Structure

Isar tables mirror server tables.

Example

customers
orders
invoices

Additional local tables

sync_queue
sync_state

---

# sync_queue Table

Stores pending operations waiting for server sync.

Fields

queue_id
operation
entity
record_id
payload
row_version
device_id
created_at
status

Operation values

create
update
delete

---

# sync_state Table

Stores device sync metadata.

Fields

device_id
last_sync_token
last_sync_at

---

# Device Identification

Each installation must generate a persistent device_id.

Example

DEV-4F82K2A

Store locally.

Send with every API request.

---

# Server Database Structure

Main tables

customers
orders
invoices

Sync infrastructure tables

change_log
sync_devices
sync_conflicts

---

# change_log Table

Tracks all server side modifications.

Fields

log_id (auto increment)
table_name
record_id
operation
row_version
updated_at
device_id

Purpose

Allows devices to request changes after a token.

---

# Sync Tokens

Each device stores last_sync_token.

Example

last_sync_token = 10023

During pull sync device requests

GET /sync/pull?since=10023

Server returns all changes where log_id > token.

---

# Push Sync Flow

Step 1

Client reads unsynced items from sync_queue.

Step 2

Batch send to server.

POST /sync/push

Payload

{
device_id,
operations[]
}

Each operation contains

entity
record_id
row_version
operation
payload
updated_at

Step 3

Server validation

IF client_version > server_version
apply change
ELSE
ignore or create conflict

Step 4

Server writes entry to change_log.

Step 5

Server response returns success and latest token.

---

# Pull Sync Flow

Device requests changes.

GET /sync/pull?since=token

Server returns

new_token
changes[]

Device applies updates to local database.

---

# Conflict Resolution Strategy

Primary rule

Last Write Wins

Comparison fields

row_version
updated_at

If server_version > client_version

Server state wins.

Client overwrites local record.

---

# Soft Delete Strategy

Never hard delete.

Use deleted_at timestamp.

Delete operation must be synced like any update.

---

# Sync Scheduling

Trigger sync in these situations

app startup
network restored
periodic timer (30–60 seconds)
manual user action

---

# Batch Sync

Send operations in batches.

Recommended size

50–200 operations per request

---

# Retry Mechanism

If push fails

leave operations in sync_queue
retry with exponential backoff

Example retry delays

5 seconds
15 seconds
30 seconds
60 seconds

---

# Idempotency Rules

Server must detect duplicate operations.

Use combination

record_id
row_version

If already processed

ignore safely.

---

# Data Integrity Rules

All server sync operations must run inside database transactions.

Laravel example

DB::transaction

Ensures atomic updates.

---

# Multi Device Example

Device A updates record version 5

Device B updates record version 6

Server stores version 6.

Device A receives updated version during next pull.

All devices converge to same state.

---

# Security

Each sync request must include

API token
Device ID

Validate device before applying changes.

---

# Large Dataset Optimization

If tables grow large

Maintain separate tokens per table

Example

customers_token
orders_token
invoices_token

---

# Sync Engine Responsibilities

The sync engine must

monitor local changes
queue operations
push changes
pull updates
retry failed operations
resolve conflicts
update local database

---

# UI Rules

UI must never directly write to server.

Correct flow

UI -> Local Database -> Sync Queue -> Sync Engine -> API

---

# Error Handling

Handle these cases

network failure
partial sync
API timeout
server rejection

System must retry safely without data loss.

---

# Scalability

Design must support

100+ devices
millions of records
simultaneous sync

---

# Testing Requirements

The implementation must include tests for

multi device conflict
network interruption
retry logic
large batch sync

---

# Deliverables Expected From Copilot

Copilot should generate

Laravel Sync Controller
Sync Service Layer
Database Migrations
Conflict Resolution Service
Isar Sync Engine
Queue Processor
Retry Logic
Sync State Manager

---

# Final Requirement

System must guarantee

no silent data loss
no duplicate records
consistent state across devices
safe offline editing
