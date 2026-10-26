# Privacy and access-control checklist

**Status:** Complete for the synthetic seed workbook. Production controls that depend on a hospital data-sharing agreement remain open (section 6).

**Source checked:** `Kaduna_AMR_Clean_Handoff_v2.xlsx` (v2.0, built 15 September 2026).

> **The seed workbook is synthetic practice data.** It describes invented patients in four fictional hospitals. Nothing in it is a finding about Kaduna or about real patients.

---

## 1. What is in the seed data

The data dictionary (`3_DATA_DICTIONARY`) defines 49 column entries:

- **34 columns** in `4_ISOLATES`, one row per isolate.
- **15 columns** in `5_AST_RESULTS`, one row per isolate-antibiotic test.

The data contains no patient names, telephone numbers, email addresses, street addresses, National Identification Numbers (NIN), or Bank Verification Numbers (BVN).

### Direct identifier check

| Check | Result |
|---|---|
| Name columns (`first_name`, `surname`, `patient_name`, etc.) | None. |
| Telephone or mobile number columns | None. |
| Email address columns | None. |
| Street address columns (street, plot, house number, P.O. Box, etc.) | None. |
| Government identifiers (NIN, BVN) | None. |
| Patient identifier | `patient_id` uses the synthetic form `SYN-P-NNNNNN`. It is not derived from a real hospital number. |
| Facility names | `hospital_label` values are explicitly marked `(synthetic)`. |
| Location | `lga_residence` holds a Local Government Area only (for example, `Zaria` or `Kaduna North`). It is not a street address. |

**Checked 49 data-dictionary entries (34 isolate columns and 15 AST columns); no names, telephone numbers, or addresses found.**

### Free-text review

The following text columns were reviewed for unexpected personal data:

- Isolates: `hospital_label`, `lga_residence`, `setting`, `ward`, `specimen`, `organism_as_recorded`, `organism_clean`, `organism_group`, `empiric_antibiotic`, `outcome`.
- AST results: `antibiotic`, `antibiotic_class`, `aware_category`, `method`, `guideline`, `result`.

The values are facility descriptions, clinical categories, organism names, antibiotic names, and coded results. `organism_as_recorded` contains laboratory spellings only, not patient text.

A pattern scan of the workbook's 19,182 unique text values found:

- 0 email addresses.
- 0 Nigerian telephone numbers.
- 0 street-address terms.
- 0 NIN or BVN values.
- 0 numeric cells containing 10 to 15 digit telephone-like values.

Text containing "name" or "phone" appears only in documentation strings, such as the data-dictionary note *"Hashed patient ID. Never store a real name or phone number here."* and descriptions like "Standardised organism name". These are guidance, not personal data.

### Residual risk

`lga_residence`, `age_years`, `sex`, `ward`, `collection_date`, and `hospital_code` are **quasi-identifiers**. Even without a name, a rare organism in a small ward on a known date could point to one patient. This is why the reporting layer must publish aggregates, not row-level extracts, and why cells with fewer than 30 isolates carry an `under_30` flag.

This check covers the synthetic workbook only. Real hospital data must pass the same check before loading, and the result must be recorded in the data-sharing agreement.

---

## 2. Least-privilege database access

`sql/roles.sql` creates three login roles and grants each only the access its job needs.

| Role | Intended user | Allowed | Explicitly denied |
|---|---|---|---|
| `amr_analyst` | Python, Power BI, dashboards | `CONNECT`; `USAGE` on `public`; `SELECT` on tables and views | `INSERT`, `UPDATE`, `DELETE`, `TRUNCATE`, schema changes, role management |
| `amr_loader` | Monthly data pipeline | `CONNECT`; `USAGE` on `public`; `SELECT`, `INSERT`, `UPDATE` on tables; use of sequences | `DELETE`, `TRUNCATE`, schema changes, role management |
| `amr_admin` | Database administrator and migrations | `CONNECT`; `CREATE` on `public`; all table and sequence privileges; `CREATEROLE` | `SUPERUSER`, `CREATEDB` |

The admin role is not a superuser. A superuser is used only to bootstrap the database and run this roles script; day-to-day schema work should use `amr_admin`.

**Use PostgreSQL 16 or later for real data.** On PostgreSQL 15 and earlier, a role with `CREATEROLE` can grant itself powerful built-in roles (for example `pg_execute_server_program`), which makes `amr_admin` close to a superuser. PostgreSQL 16 removed that path. `sql/roles.sql` prints a warning when it runs on an older version.

If a password variable is missing, `sql/roles.sql` stops with an error and a non-zero exit code before changing anything.

### Passwords are not committed

No password appears in this repository. The roles script requires passwords at run time through `psql` variables:

```bash
psql -U postgres -d kaduna_amr \
  -v analyst_password="$AMR_ANALYST_PASSWORD" \
  -v loader_password="$AMR_LOADER_PASSWORD" \
  -v admin_password="$AMR_ADMIN_PASSWORD" \
  -f sql/roles.sql
```

PowerShell equivalent:

```powershell
psql -U postgres -d kaduna_amr `
  -v analyst_password="$env:AMR_ANALYST_PASSWORD" `
  -v loader_password="$env:AMR_LOADER_PASSWORD" `
  -v admin_password="$env:AMR_ADMIN_PASSWORD" `
  -f sql/roles.sql
```

Set the variables from a local secret store, not in a committed file. `.env` is already ignored by `.gitignore`; `.pgpass` is ignored too.

### Order of operations

1. Create the database and run `sql/schema.sql` as the database owner or superuser.
2. Run `sql/roles.sql` as a superuser. It can be re-run safely: it creates roles if absent, resets passwords, and reapplies grants.
3. Run `sql/test_roles.sql` to prove the restrictions.
4. Give Python and Power BI only the `amr_analyst` credentials. Never give a dashboard the loader or admin password.

The roles script removes the default `CREATE` privilege that older PostgreSQL versions give to `PUBLIC` on the `public` schema. That is deliberate: after this script, only `amr_admin` can add objects.

`amr_admin` can create new objects, but PostgreSQL still requires the object owner (or a superuser) to `ALTER` or `DROP` an existing table. For repeatable migrations, either run `schema.sql` as `amr_admin` after creating the roles, or transfer ownership of the existing objects to `amr_admin`.

### Required test result

After `sql/roles.sql` (and again after every schema change), run:

```bash
psql -U postgres -d kaduna_amr -f sql/test_roles.sql
```

The test creates a scratch table as `amr_admin`, tries each operation as each role, then rolls everything back. It checks that:

- `amr_analyst` can `SELECT`, and is denied `INSERT`, `UPDATE`, `DELETE`, `TRUNCATE` and `CREATE TABLE`.
- `amr_loader` can `SELECT`, `INSERT` and `UPDATE`, and is denied `DELETE`, `TRUNCATE`, `CREATE TABLE` and `ALTER TABLE`.
- On every existing table and view in `public`, the analyst can only read and the loader cannot delete.
- No `amr_*` role is a superuser or can create databases.

Each check prints `PASS`. Any failure prints `FAIL`, stops, and exits with a non-zero code, so the test can run in CI. It works before `schema.sql` exists, and covers the real tables once it does.

If anything fails, fix the grants before connecting any reporting tool.

### Check the analyst login

`test_roles.sql` uses `SET ROLE`, which proves the grants but not that the analyst can log in. Test the login itself as the analyst user:

```bash
psql "host=localhost dbname=kaduna_amr user=amr_analyst" \
  -c "SELECT current_user" \
  -c "DELETE FROM isolates"
```

The first command should print `amr_analyst`; the second must fail with `ERROR: permission denied for table isolates`. Paste that output on issue #9.

From Python:

```python
import os
import psycopg
with psycopg.connect(host="localhost", dbname="kaduna_amr", user="amr_analyst",
                     password=os.environ["AMR_ANALYST_PASSWORD"]) as conn:
    print(conn.execute("SELECT current_user").fetchone())
```

In Power BI, use **Get Data → PostgreSQL database**, server `localhost`, database `kaduna_amr`, **Database** credentials with `amr_analyst`. If the login is refused, check `pg_hba.conf` allows password login for `amr_analyst` from that machine.

---

## 3. Pseudonymisation and hashing before real data arrives

Real patient identifiers must never reach this repository in plain form. The hospital that controls the patient record should replace the hospital number with a keyed hash before transfer.

### The rule

For each patient, the hospital computes:

```
patient_key = HMAC-SHA256(secret_key, facility_code || "|" || hospital_patient_number)
```

- `secret_key` is a random key of at least 256 bits, held by the project lead or a named key custodian. It is stored in a secret manager, never in this repository, the database, a spreadsheet, or a backup.
- `facility_code` prevents the same hospital number from producing the same token at two facilities.
- The hospital keeps the mapping between its hospital numbers and the tokens. The mapping is not sent with the dataset.
- If the key is rotated, store a key version with the token so records can still be linked after rotation. Do not store the old key alongside the data.
- If longitudinal linkage is not needed, use a per-patient random salt instead; that produces a different token each time but prevents linkage.

### Why a plain hash is not enough

A hospital number is often short and predictable. Anyone can compute `SHA256("000001")`, `SHA256("000002")`, and so on and match the results against the dataset. A plain hash is effectively a lookup table for a small identifier space.

HMAC-SHA256 requires the secret key. Without it, an attacker cannot test guesses offline. The key must still be protected, because anyone who obtains both the data and the key can reverse the mapping for the identifiers they can guess.

Never use `MD5`, an unsalted `SHA256(patient_id)`, or a hash of a name alone as a privacy control.

### Why this is pseudonymisation, not anonymisation

The NDPA treats pseudonymised data as personal data. The keyed hash can be reversed by the key holder, and even without the key, other details can re-identify a person:

- A rare organism in a small ward on a known date.
- Age, sex, ward, Local Government Area, and collection date in combination.
- The same patient appearing across months, which links their records together.

Removing the name is not anonymisation. Anonymisation requires that re-identification is not reasonably possible, by anyone, using any reasonably available means. That is a much higher bar and should not be claimed for this dataset.

### What must not be loaded

- Names, telephone numbers, addresses, email addresses, NIN, BVN, next-of-kin details, or free-text clinical notes.
- A raw hospital number in any column, including `patient_id`.
- An identifier hash produced with a key that is stored in the same repository or database.
- Small-cell tables that could identify a patient by combining quasi-identifiers.

If a direct identifier arrives by mistake, quarantine the row in the rejects table, do not promote it, and follow the incident process in section 5.

---

## 4. NDPA 2023 principles that apply

The Nigeria Data Protection Act 2023 (NDPA) sets the principles in section 24. The NDPC's 2025 General Application and Implementation Directive (GAID) lists eight principles that apply to all processing. The ones relevant here are:

| Principle | What it means for this repository |
|---|---|
| **Fairness, lawfulness and transparency** | The hospital must have a documented lawful basis for sharing surveillance data, and patients must be told how their data is used. This repository does not create a lawful basis by itself. |
| **Purpose limitation** | Data is loaded and used only for AMR surveillance, reporting, and the agreed public-health work. It must not be reused for marketing, employment, insurance, or unrelated research. |
| **Data minimisation and ethics** | Collect only the columns needed for surveillance. No names, phone numbers, addresses, or free-text notes. The 49-column dictionary is the approved minimum for this project. |
| **Storage limitation** | Set a retention period in the data-sharing agreement and delete or archive data when it expires. Synthetic training data may be kept; real patient data may not be kept indefinitely. |
| **Data accuracy** | Loads are validated, rejects are recorded, and corrections are traceable. `lga_residence` and other fields must not be invented to fill gaps. |
| **Confidentiality, integrity and availability** | Use least-privilege roles, encrypted connections, restricted backups, and tested recovery. Dashboards read with `amr_analyst`; they never hold write credentials. |
| **Accountability** | Record who approved the data-sharing agreement, who holds the HMAC key, who has admin access, and when access was last reviewed. Keep this document and the role script under version control. |
| **Duty of care** | Treat health data as sensitive personal data. A breach or accidental disclosure must be handled through the incident process, not quietly deleted. |

The NDPA also requires an appropriate lawful basis under section 25 and gives data subjects rights over their data. Health data is sensitive personal data, so the hospital's lawful basis and safeguards must be confirmed before any real load. The NDPA breach-notification duty (section 40) requires notifying the Nigeria Data Protection Commission within 72 hours of becoming aware of a reportable breach.

---

## 5. Handling rules

1. **No real patient data in Git.** Only the agreed synthetic workbook belongs in `seed/`. CSV exports are ignored by `.gitignore`.
2. **No direct identifiers in staging.** The staging tables accept raw files for validation, but a file containing names, phone numbers, or addresses must be rejected before it reaches the database.
3. **Aggregates only for analysts.** Dashboards read the reporting views. They do not receive row-level extracts or the `rejects` table.
4. **Small cells stay flagged.** Every percentage must carry its count, and cells with fewer than 30 isolates must be suppressed or clearly marked with `under_30`.
5. **Least privilege at all times.** Python and Power BI use `amr_analyst`. Only the loader uses `amr_loader`. Only the DBA uses `amr_admin`.
6. **Secrets stay outside the repository.** The HMAC key and database passwords live in a secret manager. They are not committed, logged, or pasted into issues.
7. **Breach response.** If identifiable data is exposed, preserve evidence, notify the project lead and the hospital's data protection officer, and follow the NDPA 72-hour notification process. Do not try to hide the incident by deleting rows.
8. **Retention.** The data-sharing agreement must state how long raw and pseudonymised data is kept, who approves deletion, and how backups are handled.

---

## 6. Open items before real hospital data

- [ ] Signed data-sharing agreement naming the hospital as data controller and this project as processor.
- [ ] Documented lawful basis for surveillance processing, reviewed by the hospital's data protection officer.
- [ ] Data Protection Impact Assessment completed for the real data flow.
- [ ] HMAC key generated, stored in a secret manager, and assigned to a named custodian.
- [ ] Hospital-side hashing procedure tested on a sample and checked for collisions.
- [ ] Retention and deletion schedule agreed, including backups.
- [ ] Real-data column check repeated and recorded; any direct identifier found is quarantined.
- [ ] Access review completed: who has `amr_analyst`, `amr_loader`, and `amr_admin`.
- [ ] Incident-response contact list and 72-hour notification procedure tested.
- [ ] Cross-border transfer review completed if any service or backup is outside Nigeria.

---

## 7. Sign-off checklist for this issue

- [x] Three roles created: `amr_analyst`, `amr_loader`, `amr_admin`.
- [x] Analyst is read-only and cannot `DELETE` or `UPDATE`.
- [x] Loader can load rows but cannot change the schema.
- [x] No password is committed to Git.
- [x] `sql/test_roles.sql` passes and fails loudly if a grant is wrong.
- [ ] Analyst login tested with `psql -U amr_analyst` and the `permission denied` output pasted on issue #9.
- [ ] Python and Power BI connected with `amr_analyst` credentials.
- [x] Seed workbook checked for names, telephone numbers, addresses, and government identifiers.
- [x] Keyed-hash pseudonymisation and its limits are documented.
- [x] NDPA 2023 principles that apply are listed with project-specific meaning.
