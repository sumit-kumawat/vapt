# VAPT-AutoScanner

A fully automated **Vulnerability Assessment & Penetration Testing (VAPT)** script for Ubuntu 24.04 LTS.  
Performs recon, automated scanning, OWASP Top 10 checks, and basic infrastructure scanning.  
Generates a complete set of logs and outputs for client reporting.

---

## Features
- **Basic VAPT**: Automated + light manual, single website, no infra testing.
- **Intermediate VAPT**: Automated + full manual checks, OWASP Top 10, basic infrastructure scan.
- Live **progress bar** in terminal for tracking scan progress.
- Organizes all outputs in a **timestamped folder** for easy report creation.
- Supports multiple tools: `nmap`, `nikto`, `wapiti`, `sqlmap`, `wpscan`, `whatweb`, `sublist3r`, and `whois`.

---

## Requirements
Tested on **Ubuntu 24.04 LTS**.

### Install Dependencies
Run:
```bash
sudo apt update
sudo apt install nmap nikto wapiti sqlmap whatweb sublist3r ruby-full build-essential patch ruby-dev zlib1g-dev liblzma-dev libffi-dev libcurl4-openssl-dev libssl-dev whois -y
sudo gem install wpscan

chmod +x intermediate.sh
./intermediate.sh
