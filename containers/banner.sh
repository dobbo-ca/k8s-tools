#!/bin/sh
# Print the k8s-tools welcome banner on interactive shell start.

case $- in *i*) ;; *) return 0 2>/dev/null || exit 0 ;; esac
[ -n "$K8S_TOOLS_BANNER_SHOWN" ] && return 0 2>/dev/null
K8S_TOOLS_BANNER_SHOWN=1
export K8S_TOOLS_BANNER_SHOWN

cat <<'EOF'

================================================================
  k8s-tools — diagnostic container
================================================================
  DNS         dig host nslookup drill
  TLS         openssl sslscan testssl
  HTTP        curl wget nmap
  Network     ping mtr tcptraceroute tracepath
  Sockets     nc ss netstat
  Capture     tcpdump strace
  Bandwidth   iperf3
  Data        jq yq less tree file
  Editor      nvim
EOF

if command -v psql >/dev/null 2>&1; then
  echo '  Postgres    psql pg_dump pg_restore pgbench wal-g pgcenter pgbadger'
fi
if command -v python >/dev/null 2>&1; then
  echo '  Python      python pip  (psycopg pgcli rich click tenacity)'
fi

cat <<'EOF'

  Full reference: cat /TOOLS.md
================================================================

EOF
