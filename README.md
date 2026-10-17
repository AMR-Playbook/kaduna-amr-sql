<div align="center">

# 🗄️ Kaduna AMR Watch — Database

**The single trusted home for every laboratory result, from practice data today to twenty real hospitals tomorrow.**

![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-336791?style=flat-square&logo=postgresql&logoColor=white)
![Data](https://img.shields.io/badge/data-SYNTHETIC%20practice-d29922?style=flat-square)
![Privacy](https://img.shields.io/badge/privacy-NDPA%202023-8250df?style=flat-square)

</div>

> [!IMPORTANT]
> **SYNTHETIC PRACTICE DATA.** Every number this database produces today comes from invented data. Never present it as a finding about Kaduna.

## Why this exists

Excel works one file at a time. A surveillance system receives new data every month, from many hospitals, for years. It needs one home with rules that stop bad data at the door, remove duplicates the same way every time, protect patient privacy, and give Python and Power BI **the same trusted numbers**.

## Where this sits

```mermaid
flowchart LR
    XL["📗 Clean Handoff Pack v2<br/>(Excel, complete)"] --> STG["Staging tables"]
    STG -->|valid rows| CORE["Core tables<br/>isolates · ast_results"]
    STG -->|broken rows + reason| REJ["rejects"]
    CORE --> FI["First-isolate view"]
    FI --> V["Trusted views<br/>v_antibiogram · v_resistance_trend<br/>v_mdr_by_ward · v_turnaround<br/>v_empiric_mismatch · v_aware_mix"]
    V -->|read-only role| PY["🐍 Python"]
    V -->|read-only role| BI["📊 Power BI"]
```

## Target data model (draft)

Finalised in the schema issue. Lookups are stored once, not repeated on 94,000 rows.

```mermaid
erDiagram
    HOSPITALS ||--o{ ISOLATES : "reports"
    ORGANISMS ||--o{ ISOLATES : "identifies"
    WARDS ||--o{ ISOLATES : "admitted to"
    SPECIMENS ||--o{ ISOLATES : "taken from"
    ISOLATES ||--|{ AST_RESULTS : "tested against"
    ANTIBIOTICS ||--o{ AST_RESULTS : "uses"

    HOSPITALS {
        text hospital_code PK
        text hospital_label
        text hospital_type
    }
    ORGANISMS {
        text organism PK
        text organism_group
    }
    ANTIBIOTICS {
        text antibiotic PK
        text antibiotic_class
        text aware_category
    }
    ISOLATES {
        text isolate_id PK
        text patient_id_hash
        text hospital_code FK
        date collection_date
        date report_date
        text organism FK
        text ward FK
        text specimen FK
        boolean mdr_flag
    }
    AST_RESULTS {
        text isolate_id FK
        text antibiotic FK
        char result "S, I or R"
        text guideline "CLSI or EUCAST + year"
        text method
        numeric zone_mm_or_mic "real data only"
    }
```

## The answer key

Every view must reproduce sheet `11_ANSWER_KEY` of the [Clean Handoff Pack](https://github.com/AMR-Playbook/.github/releases/tag/excel-handoff-v2):

| Check | Expected |
|---|---|
| Isolates loaded | 9,108 |
| AST test rows loaded | 94,454 |
| Orphan AST rows | 0 |
| *E. coli* + ceftriaxone 2024, % resistant | **61.66%** (201 of 326) |
| *K. pneumoniae* + meropenem 2024, % resistant | 16.26% (40 of 246) |
| MDR rate, all isolates | 85.74% (count isolates, not test rows) |

> [!WARNING]
> **The classic trap:** joining `isolates` to `ast_results` gives about ten rows per isolate. Counting isolates from that join inflates everything tenfold. Count isolates on `isolates`, and tests on `ast_results`.

## Layout

```
schema/      schema_v1.sql and constraints, builds everything from zero
load/        staging, validation and load scripts
views/       one file per view, each with a header comment explaining it
roles/       database roles and grants
docs/        ERD, design decisions, privacy checklist, view catalogue
```

## Getting started

1. Install PostgreSQL 16 and a client such as DBeaver or pgAdmin.
2. Download `Kaduna_AMR_Clean_Handoff_v2.xlsx` from the [release](https://github.com/AMR-Playbook/.github/releases/tag/excel-handoff-v2). **Never commit it.**
3. Pick an [open issue](../../issues) and read [CONTRIBUTING](https://github.com/AMR-Playbook/.github/blob/main/CONTRIBUTING.md).
