#!/usr/bin/env bash
# vapt_intermediate.sh
# Automated Basic -> Intermediate VAPT runner for Ubuntu 24.04 LTS
# Runs recon, web scans, SQLi checks, basic infra checks + saves logs.
# Shows a live progress bar in the terminal.
#
# IMPORTANT: Run only with written permission from the target owner.
# Tested on Ubuntu 24.04 LTS. Some commands may be skipped if not installed.

set -euo pipefail

# ---------- Helpers ----------
print_header(){
    echo "======================================================="
    echo "$1"
    echo "======================================================="
}

progress_bar(){
    # args: percent, status_text
    pct=$1
    text="$2"
    cols=50
    filled=$(( (pct * cols) / 100 ))
    empty=$(( cols - filled ))
    filled_str=$(printf "%0.s#" $(seq 1 $filled))
    empty_str=$(printf "%0.s-" $(seq 1 $empty))
    printf "\r[%s%s] %3s%%  %s" "$filled_str" "$empty_str" "$pct" "$text"
}

check_cmd(){
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "MISSING:$1"
        return 1
    fi
    echo "OK:$1"
    return 0
}

# ---------- Prompt & Setup ----------
echo
print_header "Automated VAPT (Basic -> Intermediate) - Ubuntu 24.04 LTS"

read -rp "Enter target domain (e.g. example.com): " TARGET
if [ -z "$TARGET" ]; then
    echo "No target provided. Exiting."
    exit 1
fi

read -rp "Confirm you have WRITTEN permission from the owner for testing (yes/no): " CONF
if [[ "${CONF,,}" != "yes" ]]; then
    echo "You must have written permission to proceed. Exiting."
    exit 1
fi

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
SAFE_TARGET=$(echo "$TARGET" | sed 's~https\?://~~; s~/~~_~g')
OUTDIR="VAPT_${SAFE_TARGET}_${TIMESTAMP}"
mkdir -p "$OUTDIR"
echo "Output directory: $OUTDIR"

# Save environment info
uname -a > "$OUTDIR/env_uname.txt"
lsb_release -a > "$OUTDIR/env_lsb.txt" 2>/dev/null || true
echo "Script run: $(whoami) @ $(date)" > "$OUTDIR/README.txt"

# ---------- Determine installed tools ----------
TOOLS=(whois dig sublist3r nmap nikto wapiti sqlmap wpscan whatweb curl gobuster sslyze sslscan nikto)
declare -A TOOLSTATUS
for t in "${TOOLS[@]}"; do
    if check_cmd "$t" >/dev/null 2>&1; then
        TOOLSTATUS[$t]=1
    else
        TOOLSTATUS[$t]=0
    fi
done

# special check for zaproxy
if command -v zaproxy >/dev/null 2>&1 || command -v owasp-zap >/dev/null 2>&1; then
    TOOLSTATUS["zaproxy"]=1
else
    TOOLSTATUS["zaproxy"]=0
fi

# build list of steps for progress
STEPS=()
STEPS+=("WHOIS")
STEPS+=("DNS (dig)")
STEPS+=("Subdomain enumeration (sublist3r)")
STEPS+=("Nmap full port/service scan")
STEPS+=("Nmap vulnerability scripts")
STEPS+=("Nikto web scan")
STEPS+=("Wapiti web scan")
STEPS+=("Directory brute force (gobuster - optional)")
STEPS+=("SSL/TLS checks")
STEPS+=("SQL injection quick (sqlmap - low risk)")
STEPS+=("CMS detection (whatweb)")
STEPS+=("WPScan if WordPress")
STEPS+=("OWASP ZAP (manual - start instructions)")
STEPS+=("Assemble summary & zip")

TOTAL=${#STEPS[@]}
CUR=0

# ---------- Run steps ----------
step_done(){
    CUR=$((CUR+1))
    pct=$(( (CUR*100)/TOTAL ))
    progress_bar "$pct" "$1"
    echo
}

# WHOIS
progress_bar 0 "Starting VAPT..."
echo
print_header "Step 1: WHOIS"
whois "$TARGET" > "$OUTDIR/whois.txt" 2>&1 || true
step_done "WHOIS complete"

# DIG
print_header "Step 2: DNS (dig)"
dig "$TARGET" ANY +noall +answer > "$OUTDIR/dig_any.txt" 2>&1 || true
dig +short NS "$TARGET" > "$OUTDIR/dig_ns.txt" 2>&1 || true
step_done "DNS complete"

# Subdomains
print_header "Step 3: Subdomain enumeration (sublist3r)"
if command -v sublist3r >/dev/null 2>&1; then
    sublist3r -d "$TARGET" -o "$OUTDIR/subdomains.txt" > "$OUTDIR/sublist3r_stdout.txt" 2>&1 || true
else
    echo "sublist3r not installed - skipping. Consider installing with pip." > "$OUTDIR/subdomains.txt"
fi
step_done "Subdomain enumeration complete"

# Nmap full port
print_header "Step 4: Nmap full port/service scan (this may take time)"
if command -v nmap >/dev/null 2>&1; then
    nmap -p- -T4 -oA "$OUTDIR/nmap_full" "$TARGET" > "$OUTDIR/nmap_full_stdout.txt" 2>&1 || true
else
    echo "nmap not installed. Skipping." > "$OUTDIR/nmap_full.txt"
fi
step_done "Nmap full scan complete"

# Nmap scripts vuln
print_header "Step 5: Nmap vuln scripts (CVE & ssl scripts)"
if command -v nmap >/dev/null 2>&1; then
    # service/version + default scripts + vuln category + ssl checks
    nmap -sV --script "default,vuln,ssl-cert,ssl-enum-ciphers" -oA "$OUTDIR/nmap_scripts" "$TARGET" > "$OUTDIR/nmap_scripts_stdout.txt" 2>&1 || true
else
    echo "nmap not installed. Skipping script scans." > "$OUTDIR/nmap_scripts.txt"
fi
step_done "Nmap NSE scripts complete"

# Nikto
print_header "Step 6: Nikto web scan"
if command -v nikto >/dev/null 2>&1; then
    nikto -host "http://$TARGET" -output "$OUTDIR/nikto_http.txt" -Format txt || true
    nikto -host "https://$TARGET" -output "$OUTDIR/nikto_https.txt" -Format txt || true
else
    echo "nikto not installed. Skipping." > "$OUTDIR/nikto_note.txt"
fi
step_done "Nikto complete"

# Wapiti
print_header "Step 7: Wapiti (web app scanner)"
if command -v wapiti >/dev/null 2>&1; then
    wapiti -u "http://$TARGET" -f txt -o "$OUTDIR/wapiti_http.txt" || true
    wapiti -u "https://$TARGET" -f txt -o "$OUTDIR/wapiti_https.txt" || true
else
    echo "wapiti not installed. Skipping." > "$OUTDIR/wapiti_note.txt"
fi
step_done "Wapiti complete"

# Directory brute force - gobuster
print_header "Step 8: Directory brute force (gobuster) - optional"
if command -v gobuster >/dev/null 2>&1; then
    # uses default wordlist if /usr/share/wordlists/dirb/common.txt exists; else skip
    WL="/usr/share/wordlists/dirb/common.txt"
    if [ -f "$WL" ]; then
        gobuster dir -u "http://$TARGET" -w "$WL" -o "$OUTDIR/gobuster_http.txt" -q || true
        gobuster dir -u "https://$TARGET" -w "$WL" -o "$OUTDIR/gobuster_https.txt" -q || true
    else
        echo "No common wordlist found at $WL — install wordlists or provide custom." > "$OUTDIR/gobuster_note.txt"
    fi
else
    echo "gobuster not installed. Skipping directory brute force." > "$OUTDIR/gobuster_note.txt"
fi
step_done "Directory brute force step done"

# SSL/TLS - curl headers + nmap ssl
print_header "Step 9: SSL/TLS checks"
curl -Is "https://$TARGET" > "$OUTDIR/headers_https.txt" 2>&1 || true
curl -Is "http://$TARGET" > "$OUTDIR/headers_http.txt" 2>&1 || true
if command -v nmap >/dev/null 2>&1; then
    nmap --script ssl-enum-ciphers -p 443 "$TARGET" -oN "$OUTDIR/nmap_ssl_enum.txt" >/dev/null 2>&1 || true
fi
step_done "SSL/TLS checks complete"

# SQLMap (low-risk quick)
print_header "Step 10: SQLMap quick (LOW RISK: crawl=0, risk=1, level=1)"
if command -v sqlmap >/dev/null 2>&1; then
    # Quick attempt - target root page; this is conservative
    sqlmap -u "http://$TARGET" --batch --risk=1 --level=1 --crawl=0 --threads=1 -o "$OUTDIR/sqlmap_dummy.txt" >/dev/null 2>&1 || true
    # If sqlmap version does not support -o, save output redirection
else
    echo "sqlmap not installed. Skipping." > "$OUTDIR/sqlmap_note.txt"
fi
step_done "SQLMap quick scan complete"

# CMS detection
print_header "Step 11: CMS detection (whatweb)"
if command -v whatweb >/dev/null 2>&1; then
    whatweb "http://$TARGET" > "$OUTDIR/whatweb_http.txt" 2>&1 || true
    whatweb "https://$TARGET" > "$OUTDIR/whatweb_https.txt" 2>&1 || true
else
    echo "whatweb not installed. Skipping CMS detection." > "$OUTDIR/whatweb_note.txt"
fi
step_done "CMS detection complete"

# WPScan if WordPress detected
print_header "Step 12: WPScan (if WordPress detected)"
WPSCAN_RUN=0
if command -v wpscan >/dev/null 2>&1; then
    detected=0
    if grep -qi "WordPress" "$OUTDIR/whatweb_http.txt" 2>/dev/null || grep -qi "WordPress" "$OUTDIR/whatweb_https.txt" 2>/dev/null; then
        detected=1
    fi
    if [ $detected -eq 1 ]; then
        echo "WordPress detected, running wpscan with API key..."
        wpscan --url "https://$TARGET" \
               --enumerate u,ap,at,tt,cb,dbe \
               --api-token "7k2r3NngoAl9ch4FhqyJlg6akD2T1ZAirrNTpPcXafo" \
               > "$OUTDIR/wpscan.txt" 2>&1 || true
        WPSCAN_RUN=1
    else
        echo "WordPress not detected. Skipping wpscan." > "$OUTDIR/wpscan_note.txt"
    fi
else
    echo "wpscan not installed. Skipping." > "$OUTDIR/wpscan_note.txt"
fi
step_done "WPScan step complete"

# OWASP ZAP hint (manual)
print_header "Step 13: OWASP ZAP (manual step)"
if [ "${TOOLSTATUS[zaproxy]:-0}" -eq 1 ]; then
    echo "OWASP ZAP is installed. Start it manually for interactive crawling and active scanning:"
    echo "  - Run: zaproxy"
    echo "  - Configure your browser to use proxy 127.0.0.1:8080 and browse the site to populate ZAP, then run active scan."
    echo "Saved this instruction at $OUTDIR/zap_instructions.txt"
    {
      echo "ZAP instructions:"
      echo "1) Start ZAP (zaproxy)"
      echo "2) Set browser proxy to 127.0.0.1:8080"
      echo "3) Browse site to populate sites tree"
      echo "4) Right-click target > Attack > Active Scan"
    } > "$OUTDIR/zap_instructions.txt"
else
    echo "OWASP ZAP not installed or not available. Manual testing recommended." > "$OUTDIR/zap_instructions.txt"
fi
step_done "OWASP ZAP instruction saved"

# Summarize outputs
print_header "Step 14: Assembling summary and zipping results"
{
  echo "VAPT run summary"
  echo "Target: $TARGET"
  echo "Timestamp: $TIMESTAMP"
  echo "Tools available (quick):"
  for k in "${!TOOLSTATUS[@]}"; do
    echo "$k : ${TOOLSTATUS[$k]}"
  done
  echo ""
  echo "Notes:"
  echo "- Manual follow up is required for OWASP ZAP and deeper manual exploitation (outside scope)."
  echo "- SQLMap was run in low-risk mode. Do not run high risk/dump options without explicit permission."
} > "$OUTDIR/SUMMARY.txt"

zip -r "${OUTDIR}.zip" "$OUTDIR" >/dev/null 2>&1 || tar -czf "${OUTDIR}.tar.gz" "$OUTDIR" >/dev/null 2>&1
step_done "Results zipped"

# Final
print_header "Complete"
echo "All done. Results are in directory: $OUTDIR"
if [ -f "${OUTDIR}.zip" ]; then
    echo "Zip: ${OUTDIR}.zip"
else
    echo "Tarball: ${OUTDIR}.tar.gz"
fi
echo "Next recommended steps:"
echo " - Manually run OWASP ZAP active scan and review findings."
echo " - Review outputs in $OUTDIR and capture screenshots for the report."
echo " - Encrypt $OUTDIR.zip before sending to client (gpg or password zip)."

# End
progress_bar 100 "Finished"
echo
