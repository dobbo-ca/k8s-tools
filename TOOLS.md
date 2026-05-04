# TOOLS.md — k8s-tools Diagnostic Cheatsheet

In-container reference for the diagnostic tools shipped in `k8s-tools`. Each
section lists tools with one-line descriptions and example commands.

> **Quick exec:** `kubectl exec -it <pod> -- bash`
> **Full image:** all base tools below.
> **Postgres image:** all base tools + the Postgres section.

---

## DNS

Resolve names, debug CoreDNS, trace delegation chains.

- **`dig`** — flexible DNS lookup, the standard tool.
  - `dig example.com A`
  - `dig @8.8.8.8 example.com` (query specific resolver)
  - `dig +trace example.com` (full delegation chain)
  - `dig +short MX example.com`
- **`host`** — quick A/AAAA/MX/TXT lookup.
  - `host example.com`
  - `host -t TXT example.com`
- **`nslookup`** — interactive resolver tool.
  - `nslookup example.com`
- **`drill`** — `dig` alternative with cleaner output.
  - `drill example.com`

**Common scenarios:**
- Verify in-cluster DNS: `dig kubernetes.default.svc.cluster.local`
- Check CoreDNS reachability: `dig @<coredns-ip> example.com`
- Trace external delegation: `dig +trace example.com`

---

## SSL/TLS

Inspect certs, scan ciphers, debug handshake failures.

- **`openssl`** — Swiss-army knife for crypto/TLS.
  - `openssl s_client -connect host:443 -servername host < /dev/null`
  - `openssl s_client -connect host:443 -showcerts < /dev/null`
  - `openssl x509 -in cert.pem -text -noout` (inspect cert file)
  - `echo | openssl s_client -connect host:443 2>/dev/null | openssl x509 -noout -dates` (cert expiry)
- **`sslscan`** — fast cipher/protocol scanner.
  - `sslscan host:443`
  - `sslscan --no-failed host:443` (only successful ciphers)
- **`testssl`** — comprehensive TLS audit.
  - `testssl host:443`
  - `testssl --severity HIGH host:443`

**Common scenarios:**
- Cert chain: `openssl s_client -connect host:443 -showcerts`
- Verify SAN/CN: `openssl x509 -in cert.pem -noout -ext subjectAltName`
- Check TLS versions: `sslscan host:443 | grep -E "TLSv|SSLv"`

---

## HTTP

Send requests, inspect responses, debug services.

- **`curl`** — request workhorse.
  - `curl -vvv https://host/path` (verbose)
  - `curl -k https://host` (skip TLS verify)
  - `curl -I https://host` (headers only)
  - `curl -L https://host` (follow redirects)
  - `curl -w "%{time_total}\n" -o /dev/null -s https://host` (timing)
- **`wget`** — alternative downloader/probe.
  - `wget --spider https://host/path` (check existence, no download)
  - `wget -qO- https://host/path` (print to stdout)
- **`nmap`** — service detection / port scan.
  - `nmap -sV -p 443 host`
  - `nmap -sT -p 80,443,8080 host` (TCP connect)

**Common scenarios:**
- Inspect headers + redirects: `curl -ILv https://host`
- Test service from inside cluster: `curl -v http://svc.namespace.svc.cluster.local`
- Time breakdown: `curl -w "@-" ...` with custom format file

---

## Network/Routing

Reachability, latency, packet loss, route tracing.

- **`ping`** / **`iputils`** — basic reachability.
  - `ping -c 4 host`
- **`mtr`** — combined ping + traceroute, live.
  - `mtr --report --report-cycles 10 host`
  - `mtr -T -P 443 host` (TCP-mode to port)
- **`tcptraceroute`** — TCP-based hop discovery (works through firewalls that drop ICMP/UDP).
  - `tcptraceroute host 443`
- **`tracepath`** — like traceroute, no root needed (from iputils).
  - `tracepath host`

**Common scenarios:**
- Latency to upstream: `mtr --report host`
- Find broken hop: `traceroute -n host`
- Confirm pod-to-pod routing: `ping <other-pod-ip>`

---

## Port/Socket

TCP probes, listening sockets, connection state.

- **`nc` (netcat-openbsd)** — TCP/UDP swiss army knife.
  - `nc -zv host 443` (port reachability)
  - `nc -zvu host 53` (UDP)
  - `nc -l 8080` (listen, debug)
- **`ss`** — modern socket inspector (iproute2).
  - `ss -tlnp` (TCP listening, with PID)
  - `ss -tan` (all TCP)
  - `ss -s` (summary)
- **`netstat`** — legacy alternative (net-tools).
  - `netstat -tlnp`

**Common scenarios:**
- Quick TCP test: `nc -zv host port`
- See what's listening: `ss -tlnp`
- Connection states: `ss -tan state established`

---

## Packet Capture / Tracing

Capture wire traffic, trace syscalls.

- **`tcpdump`** — packet capture.
  - `tcpdump -i any -n port 5432` (Postgres traffic)
  - `tcpdump -i any -n -w /tmp/cap.pcap host 1.2.3.4` (write file)
- **`strace`** — syscall tracer.
  - `strace -p <pid>`
  - `strace -e network curl https://host`

**Common scenarios:**
- Sniff DB traffic: `tcpdump -i any -n -A port 5432`
- Diagnose hangs: `strace -p <pid> -f`

---

## Bandwidth

- **`iperf3`** — TCP/UDP throughput.
  - `iperf3 -c host` (client)
  - `iperf3 -s` (server)
  - `iperf3 -c host -u -b 100M` (UDP, target rate)

---

## Data Munging / Inspection

- **`jq`** — JSON query/transform.
  - `curl -s https://host/api | jq '.items[].name'`
  - `jq '.field // "default"'`
- **`yq`** — YAML query/transform (jq-like).
  - `yq '.spec.replicas' deployment.yaml`
- **`less`** — pager for big files.
- **`tree`** — directory tree view.
- **`file`** — identify file type.

---

## Editor / Shell

- **`nvim`** (neovim) — primary editor.
- **`bash`** — shell.
- **`htop`** — interactive process viewer.

---

## Postgres (postgres variant only)

Client tools, backup/restore, monitoring, log analysis.

### Connect & Query

- **`psql`** — Postgres client.
  - `psql -h host -U user -d db`
  - `psql "postgresql://user:pass@host:5432/db"`
  - `psql -h host -U user -d db -c "SELECT version();"`

### Backup / Restore

- **`pg_dump`** — logical backup.
  - `pg_dump -h host -U user -d db > backup.sql`
  - `pg_dump -h host -U user -Fc -d db > backup.dump` (custom format)
- **`pg_restore`** — restore custom-format dumps.
  - `pg_restore -h host -U user -d db backup.dump`
- **`pgbackrest`** — production-grade backup tool.
  - `pgbackrest --stanza=main backup`
  - `pgbackrest --stanza=main info`
- **`wal-g`** — WAL archiving / point-in-time recovery.
  - `wal-g backup-list`
  - `wal-g backup-push /var/lib/postgresql/data`

### Performance / Monitoring

- **`pgbench`** — benchmarking tool.
  - `pgbench -i -h host -U user -d db` (initialize)
  - `pgbench -h host -U user -d db -c 10 -T 60` (10 clients, 60s)
- **`pgcenter`** — top-like real-time stats.
  - `pgcenter top -h host -U user -d db`
- **`pgbadger`** — log analyzer, generates HTML report.
  - `pgbadger /path/to/postgresql.log -o report.html`

### Useful Diagnostic Queries

```sql
-- Top slow queries (requires pg_stat_statements extension)
SELECT query, calls, mean_exec_time, total_exec_time
FROM pg_stat_statements
ORDER BY mean_exec_time DESC LIMIT 10;

-- Active connections
SELECT pid, usename, application_name, state, query
FROM pg_stat_activity
WHERE state != 'idle';

-- Locks blocking other queries
SELECT blocked.pid AS blocked_pid, blocking.pid AS blocking_pid,
       blocked.query AS blocked_query, blocking.query AS blocking_query
FROM pg_stat_activity blocked
JOIN pg_stat_activity blocking
  ON blocking.pid = ANY(pg_blocking_pids(blocked.pid));

-- Index usage
SELECT schemaname, relname, indexrelname, idx_scan, idx_tup_read
FROM pg_stat_user_indexes
ORDER BY idx_scan ASC LIMIT 20;

-- Table size
SELECT relname, pg_size_pretty(pg_total_relation_size(relid)) AS size
FROM pg_catalog.pg_statio_user_tables
ORDER BY pg_total_relation_size(relid) DESC LIMIT 20;
```

---

## Tips

- Container runs as nobody (UID 65534). Most tools work; raw sockets and bind <1024 do not.
- Read-only rootfs by default — write to `/tmp` or mounted volumes only.
- `kubectl cp` to pull captures (e.g., `tcpdump` pcaps) out of the pod.
- For interactive use, `kubectl exec -it <pod> -- bash`.
