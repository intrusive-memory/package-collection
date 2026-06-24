---
type: docs
---

# Tracking Index System

## Overview

A **Tracking Index** is a meta-configuration that coordinates work across multiple independent repositories. It uses the **same filename** as a single-repo config (REQUIREMENTS.md, EXECUTION_PLAN.md, SUPERVISOR_STATE.md) but with `tracking_index: true` in the frontmatter to distinguish it.

Each Tracking Index lists discrete efforts being performed in separate repositories, with brief explanations of the work in each.

---

## Three Tracking Index Types

| Config Type | Tracking Index | Purpose |
|---|---|---|
| `REQUIREMENTS.md` | `REQUIREMENTS.md` (with `tracking_index: true`) | List all requirement documents across repos |
| `EXECUTION_PLAN.md` | `EXECUTION_PLAN.md` (with `tracking_index: true`) | List all execution plans across repos |
| `SUPERVISOR_STATE.md` | `SUPERVISOR_STATE.md` (with `tracking_index: true`) | Track state of all repos during mission execution |

---

## Structure Template

### REQUIREMENTS.md (Tracking Index)

```markdown
---
title: Requirements Index
tracking_index: true
created: 2026-04-18
mission: Subscription System Overhaul
---

# Requirements Index

## Billing Service
**Repository**: `/repos/billing-service/`  
**Requirements**: `REQUIREMENTS.md`  
**Description**: Core billing service with subscription management, payment processing, and Stripe integration. Foundation for all other services.

---

## Upgrade Flow
**Repository**: `/repos/web-app/`  
**Requirements**: `features/subscriptions/SPEC.md`  
**Description**: User-facing web UI for subscription upgrades, downgrades, and plan changes. Depends on Billing Service API.

---

## Analytics Sync
**Repository**: `/repos/analytics-pipeline/`  
**Requirements**: `PRD.md`  
**Description**: ETL pipeline to sync subscription events to data warehouse. Kafka → S3 → Redshift. Feeds analytics and reporting.

---

## Customer Portal
**Repository**: `/repos/customer-portal/`  
**Requirements**: `REQUIREMENTS.md`  
**Description**: Self-service portal for customers to manage subscriptions, view billing, and update payment methods. Built on Upgrade Flow.
```

### EXECUTION_PLAN.md (Tracking Index)

```markdown
---
title: Execution Plan Index
tracking_index: true
created: 2026-04-18
mission: Subscription System Overhaul
---

# Execution Plan Index

## Billing Service
**Repository**: `/repos/billing-service/`  
**Local Plan**: `EXECUTION_PLAN.md`  
**Layer**: 1 (Foundation)  
**Sorties**: 5  
**Description**: Payment processor integration, subscription state machine, usage-based billing, webhook handling. All other services depend on this.

---

## Upgrade Flow
**Repository**: `/repos/web-app/`  
**Local Plan**: `features/subscriptions/EXECUTION_PLAN.md`  
**Layer**: 2  
**Sorties**: 6  
**Depends on**: Billing Service  
**Description**: Plan comparison UI, checkout flow, confirmation/receipt pages, billing history view. Integrates with Billing Service API.

---

## Analytics Sync
**Repository**: `/repos/analytics-pipeline/`  
**Local Plan**: `EXECUTION_PLAN.md`  
**Layer**: 2  
**Sorties**: 4  
**Depends on**: Billing Service  
**Description**: Event schema, Kafka consumer, S3/Redshift pipeline, historical backfill. Parallel execution with Upgrade Flow (both Layer 2).

---

## Customer Portal
**Repository**: `/repos/customer-portal/`  
**Local Plan**: `EXECUTION_PLAN.md`  
**Layer**: 3  
**Sorties**: 3  
**Depends on**: Upgrade Flow  
**Description**: Subscription dashboard, billing management UI, cancellation flow. Built on Upgrade Flow—doesn't block if Analytics still running.
```

### SUPERVISOR_STATE.md (Tracking Index)

```markdown
---
title: Supervisor State Index
tracking_index: true
created: 2026-04-18
mission: Subscription System Overhaul
operation_name: OPERATION SUBSCRIPTION ONSLAUGHT
mission_branch: mission/subscription-onslaught/01
---

# Supervisor State Index

## Billing Service
**Repository**: `/repos/billing-service/`  
**Local State**: `SUPERVISOR_STATE.md`  
**Status**: RUNNING  
**Sorties**: 2/5 complete  
**Last Update**: 2026-04-18T10:15:00Z  
**Description**: Foundation service in progress. Sortie 1.1 (Payment Processor) active, 1.2 (State Machine) pending.

---

## Upgrade Flow
**Repository**: `/repos/web-app/`  
**Local State**: `features/subscriptions/SUPERVISOR_STATE.md`  
**Status**: LOCKED  
**Sorties**: 0/6 complete  
**Blocked by**: Billing Service (not yet COMPLETED)  
**Description**: Awaiting Billing Service completion. All 6 sorties pending.

---

## Analytics Sync
**Repository**: `/repos/analytics-pipeline/`  
**Local State**: `SUPERVISOR_STATE.md`  
**Status**: LOCKED  
**Sorties**: 0/4 complete  
**Blocked by**: Billing Service (not yet COMPLETED)  
**Description**: Awaiting Billing Service completion. Will run in parallel with Upgrade Flow once unblocked.

---

## Customer Portal
**Repository**: `/repos/customer-portal/`  
**Local State**: `SUPERVISOR_STATE.md`  
**Status**: LOCKED  
**Sorties**: 0/3 complete  
**Blocked by**: Upgrade Flow (not yet COMPLETED)  
**Description**: Awaiting Upgrade Flow completion. All 3 sorties pending.

---

## Aggregate Progress
**Items Completed**: 0/4  
**Total Sorties**: 2/18  
**Critical Path**: Billing Service → Upgrade Flow → Customer Portal  
**Parallelizable**: Upgrade Flow + Analytics Sync (both Layer 2)
```

---

## Key Principles

### Same Filename, Different Purpose

A **Tracking Index** is identified solely by `tracking_index: true` in frontmatter:

```markdown
---
title: Requirements Index
tracking_index: true  # ← This marks it as a tracking index
---
```

Single-repo configs omit this field:

```markdown
---
title: Requirements
# (no tracking_index field)
---
```

### Main Body Lists Efforts

Each entry in the Tracking Index describes one discrete repository/effort:

```markdown
## Item Name
**Repository**: `/path/to/repo/`
**Local Config File**: `relative/path/REQUIREMENTS.md`  
**Description**: What work is being done here...
```

### Brief Explanations

Each repository entry includes:
- **Repository path** (absolute)
- **Local config file path** (relative to repo)
- **Layer/Status** (for EXECUTION_PLAN and SUPERVISOR_STATE)
- **Dependencies** (if applicable)
- **Short explanation** of the work being performed

---

## Mission Supervisor Integration

When mission-supervisor encounters a Tracking Index:

1. **Detect** `tracking_index: true` in frontmatter
2. **Parse** repository paths and local config file references
3. **For each repository**:
   - Clone or enter the repo
   - Read the referenced local config (REQUIREMENTS.md, EXECUTION_PLAN.md, etc.)
   - Treat it as a distinct work unit
4. **Enforce dependencies** — don't start Item N until Item N-1 is COMPLETED
5. **Dispatch parallel agents** — run up to 4 independent repos simultaneously
6. **Update Tracking Index** (SUPERVISOR_STATE.md only) with current status

---

## Workflow

### Phase 1: Create Individual Plans

For each repository, generate its own EXECUTION_PLAN.md using `breakdown`:

```bash
cd /repos/billing-service
/mission-supervisor breakdown REQUIREMENTS.md

cd /repos/web-app
/mission-supervisor breakdown features/subscriptions/SPEC.md

# ... etc for each repo
```

### Phase 2: Assemble Tracking Index

Create a Tracking Index EXECUTION_PLAN.md that references all local plans:

```bash
cd /mission-root
# Manually create EXECUTION_PLAN.md with tracking_index: true
# List all 4 repos and their local plan paths
```

### Phase 3: Execute

```bash
cd /mission-root
/mission-supervisor start
```

Mission-supervisor reads EXECUTION_PLAN.md, detects `tracking_index: true`, and orchestrates all repositories in parallel (respecting layer dependencies).

---

## File Locations

**Mission root** (where you run `/mission-supervisor`):
- `REQUIREMENTS.md` (or `REQUIREMENTS.md` with `tracking_index: true` if multi-repo)
- `EXECUTION_PLAN.md` (or `EXECUTION_PLAN.md` with `tracking_index: true` if multi-repo)
- `SUPERVISOR_STATE.md` (or `SUPERVISOR_STATE.md` with `tracking_index: true` if multi-repo)

**Each repository** (listed in Tracking Index):
- `REQUIREMENTS.md` (local to repo)
- `EXECUTION_PLAN.md` (local to repo)
- `SUPERVISOR_STATE.md` (created at start, local to repo)

---

## Example Directory Tree

```
/mission-root/                          # Where you run /mission-supervisor
├── REQUIREMENTS.md                     # Tracking Index (if multi-repo)
├── EXECUTION_PLAN.md                   # Tracking Index (references local plans)
├── SUPERVISOR_STATE.md                 # Tracking Index (tracks all repos)
└── ...

/repos/billing-service/                 # Repository 1
├── REQUIREMENTS.md                     # Local requirements
├── EXECUTION_PLAN.md                   # Local execution plan
├── SUPERVISOR_STATE.md                 # Local state (created at mission start)
└── ...

/repos/web-app/                         # Repository 2
├── REQUIREMENTS.md
├── features/subscriptions/
│   ├── SPEC.md                        # Local requirements
│   ├── EXECUTION_PLAN.md              # Local execution plan
│   └── SUPERVISOR_STATE.md            # Local state
└── ...

/repos/analytics-pipeline/              # Repository 3
├── REQUIREMENTS.md                     # Local requirements
├── EXECUTION_PLAN.md                   # Local execution plan
├── SUPERVISOR_STATE.md                 # Local state
└── ...

/repos/customer-portal/                 # Repository 4
├── REQUIREMENTS.md                     # Local requirements
├── EXECUTION_PLAN.md                   # Local execution plan
├── SUPERVISOR_STATE.md                 # Local state
└── ...
```

---

## Detecting Tracking Index vs Single-Repo

**Single-repo mission**:
```markdown
---
title: Build User Dashboard
# (no tracking_index field or tracking_index: false)
---

# EXECUTION_PLAN.md
## Work Units
...
```

**Tracking index mission**:
```markdown
---
title: Execution Plan Index
tracking_index: true  # ← This flag
---

# EXECUTION_PLAN.md
## Dashboard Service
**Repository**: `/repos/dashboard-service/`
...

## Analytics Integration
**Repository**: `/repos/analytics-pipeline/`
...
```

---

## Why This Design

1. **No new files**: Same filenames mean no confusion or duplication
2. **Clear flag**: `tracking_index: true` explicitly marks multi-repo mode
3. **Minimal overhead**: Just list repos and descriptions—no complex schema
4. **Natural composition**: Each repo maintains its own local config; Tracking Index just references them
5. **Easy to switch**: Convert single-repo → multi-repo by adding `tracking_index: true` and listing repos
