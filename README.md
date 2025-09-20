# Introduction

Welcome to **DEVCORP Lab**, a fully documented, step-by-step Windows-centric enterprise homelab.  
The goal is simple: anyone should be able to clone this approach and rebuild the entire environment from scratch, while learning real enterprise practices along the way.

This is not a loose pile of notes. It’s a repeatable build with:

- A **living Lab Notebook** for design decisions, configurations, issues, and resolutions.
- **Numbered Build Steps** you follow in order (each includes *Objective → Prerequisites → Procedure → Verification → Challenges & Solutions*).
- **Reusable scripts and sanitized configs** for automation and redeployability.

---

## Why this lab?

- Practice enterprise best practices end-to-end: multi-site AD, Windows DHCP failover, IP-Helper PXE, least privilege, SQL on a dedicated host, structured PowerShell.  
- Build a portfolio-grade reference you can show to peers and hiring managers.  
- Document every step so the project is reproducible on fresh hardware.  

---

## What you’ll build

- **Core Infrastructure**: AD DS (multi-site), DNS, DHCP (failover), PKI.  
- **Management**: SQL Server 2022 on dedicated VM; SCCM/MECM 2403+ (Primary, DP, SUP/WSUS, Reporting, PXE Responder).  
- **Networking**: pfSense firewall/router simulating WAN + site-to-site scenarios.  
- **Automation**: PowerShell-first (advanced functions, `CmdletBinding`, `SupportsShouldProcess`, typed params/validation, logging, Pester).  
- **Monitoring/SIEM**: Foundations to capture logs and metrics from day one.  

---

## How to use this repository

1. Read `/docs/LabNotebook.md` for the current version and high-level map.  
2. Work through `/docs/BuildSteps` in ascending numeric order (`00-`, `01-`, `02-`, …).  

For every step:

- Review **Objective** and **Prerequisites**.  
- Follow the **Procedure** exactly (GUI paths + commands).  
- Confirm success via **Verification** checks.  
- If anything breaks, use **Challenges & Solutions** (and add your findings).  

---

## Step format (every step includes this)

- **Objective**: What this step achieves and why.  
- **Prerequisites**: Required prior steps, ISOs, accounts (redact secrets).  
- **Procedure**: Exact, copy-pasteable commands + GUI clicks.  
- **Verification**: Commands/outputs/screens proving success.  
- **Challenges & Solutions**:  
  - **Challenge**: Symptoms/what went wrong  
  - **Root Cause**: Why it happened  
  - **Solution**: Exact fix (commands/settings)  
  - **Evidence of Fix**: Screenshot/log/command output  
  - **Prevention**: What we’ll do to avoid it next time  

---

## Conventions & promises

- Best practices by default (with rationale and trade-offs).  
- No secrets committed (use environment variables/SecretManagement).  
- Versioned history: Each meaningful change bumps `vX.X` in `LabNotebook.md`.  
- Commit style: `type(scope): message` (e.g., `feat(build): add 01-Host-Setup with Hyper-V`).  
- Repeatable outputs: Every step has **Verification** plus **Challenges & Solutions**.  

---

## Repository structure

```text
📘 /docs
 ├─ 📝 LabNotebook.md   ← living notebook with version history
 ├─ 📂 BuildSteps/      ← numbered, atomic build steps
 └─ 📑 templates/       ← step template
⚙️  /scripts            ← automation (PowerShell first)
🛠️  /configs            ← sanitized exports and config files
🖼️  /screenshots        ← versioned screenshots per step (vX.X/)

