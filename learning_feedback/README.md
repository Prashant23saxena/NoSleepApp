# 🎓 Learning & User Feedback Knowledge Base

Welcome to the **Learning & User Feedback** archive for **NoSleepApp**.

This directory documents the iterative feedback, design critiques, bug reports, and architectural reviews provided across the entire lifecycle of the project. It serves as an authoritative guide for both human engineers and AI agents to understand **why** the application is built the way it is, what pitfalls were encountered, and how they were systematically resolved.

---

## 📚 Documents in this Directory

| Document | Description | Primary Topics Covered |
| :--- | :--- | :--- |
| [**`USER_FEEDBACK_ANALYSIS.md`**](USER_FEEDBACK_ANALYSIS.md) | **Domain-by-Domain Analysis** | Comprehensive breakdown across 5 technical domains: Security & Privileges, Hardware Thermal Protection, UI/UX & Copywriting, Concurrency & Threading, and Repository Portability. |
| [**`CHRONOLOGICAL_FEEDBACK_LOG.md`**](CHRONOLOGICAL_FEEDBACK_LOG.md) | **Chronological Audit Trail** | Step-by-step history tracing every user prompt, underlying requirement, and exact technical remediation from Step 0 through Step 1144+. |
| [**`RULES_AND_BEST_PRACTICES.md`**](RULES_AND_BEST_PRACTICES.md) | **Codified Systems Rules** | Actionable engineering rules derived from feedback: George Orwell's 6 rules for UI copy, atomic sudoers verification, crash reconciler patterns, and macOS distribution standards. |

---

## 🔍 Key Engineering Insights at a Glance

1. **Hardware Thermal Safety is Paramount**:
   - Closed-lid operation with an active screen creates severe thermal risks. Backlight must be set to **0%** (not 5%) using native `DisplayServices` C bindings.
   - All keepalive operations must be gated by a **5-hour safety timeout** and an immediate **20% battery cutoff** driven by kernel-level `IOKit` notifications.

2. **Least Privilege & Safe Escalation**:
   - Never grant group-wide `%admin` privileges. Scope passwordless `pmset` rules strictly to the specific `$USER` after regex sanitization.
   - Never write directly to `/etc/sudoers.d/`. Always stage in `.tmp`, verify with `/usr/sbin/visudo -c -f`, and move atomically.

3. **System State Ownership & Crash Reconciliation**:
   - `pmset -a disablesleep 1` persists across system crashes and reboots.
   - A crash reconciler must verify dead PIDs via persistent state files (`~/.nosleepapp_state.json`), restoring default power behavior only when application ownership is verified.

4. **Orwellian Plain English**:
   - Technical concepts must be conveyed in terms of user outcomes ("Mac will stay awake", "dims backlight", "saves battery") rather than implementation details ("IOPMAssertion", "attenuate luminosity").

5. **Distribution & Portability**:
   - Installer DMGs must meet Apple-grade aesthetics (light silver/platinum canvas, frosted cards, branded custom volume icons).
   - Checksum manifests must strictly use relative paths to ensure portability across different host environments.
