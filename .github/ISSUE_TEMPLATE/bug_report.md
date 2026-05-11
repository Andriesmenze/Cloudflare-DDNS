---
name: Bug report
about: Report a problem with the container or script
title: '[Bug] '
labels: bug
assignees: ''
---

**Description**
A clear description of what the bug is.

**Steps to reproduce**
1. ...
2. ...

**Expected behavior**
What you expected to happen.

**Actual behavior**
What actually happened.

**Logs**
Relevant log output. **Redact all API tokens, zone IDs, and domain names** before posting.

```
paste logs here
```

**Environment**

| Item | Value |
|------|-------|
| Image version / tag | |
| Host OS | |
| Architecture | |
| Docker version | |
| IPv6 enabled | yes / no |

**Configuration (sanitized)**

`cloudflare-ddns-config.yaml` with sensitive values replaced:

```yaml
API_TOKEN: "REDACTED"
SLEEP_INTERVAL: 900
...
```

`dns-records.json` with sensitive values replaced:

```json
{
  "RECORDS_CONFIG": [
    {
      "zone_id": "REDACTED",
      ...
    }
  ]
}
```
