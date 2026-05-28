# Manual Trust Install — Koala Root CA

If the in-app automatic installer fails (e.g. AppleScript disabled by MDM, or Gatekeeper policy), run these commands in Terminal.

## Install (trust root CA in System Keychain)

```
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ~/Library/Application\ Support/Koala/KoalaRootCA.pem
```

You will be prompted for your macOS admin password.

## Uninstall (remove from System Keychain)

```
sudo security delete-certificate -c "Koala Root CA" /Library/Keychains/System.keychain
```

## Verify

```
security find-certificate -c "Koala Root CA" /Library/Keychains/System.keychain
```

Exit code 0 = certificate is trusted. Non-zero = not found.

---

## Verify HTTPS interception works

Once the root CA is installed and trusted, Koala can MITM HTTPS traffic in forward-proxy mode.

### Step 1 — Start Koala in forward-proxy mode

1. Open Koala.
2. Go to the Recording tab.
3. Set Mode to **Forward Proxy**.
4. Click **Start** (default port 8080).

### Step 2 — Configure macOS system proxy

Open **System Settings → Network → Wi-Fi (or Ethernet) → Details → Proxies**.

Enable **Web Proxy (HTTP)** and **Secure Web Proxy (HTTPS)**:
- Server: `127.0.0.1`
- Port: `8080`

Click OK and Apply.

### Step 3 — Visit any HTTPS site

Open Safari or another browser and navigate to any HTTPS URL (e.g. `https://httpbin.org/get`).

### Step 4 — Check Koala captures

Switch back to Koala. The request should appear in the Captures list with:
- Method: `GET`
- URL: `https://httpbin.org/get`
- Status: `200`
- Decrypted response body visible

If the request appears, HTTPS interception is working correctly.

### Troubleshooting

**Browser shows certificate warning:**
The root CA is not yet trusted. Re-run the install command above and ensure the certificate has the "Always Trust" setting in Keychain Access for SSL.

**No captures appear:**
Confirm the system proxy is set and the proxy is running. Check Activity Monitor for the Koala process.

**`502 Bad Gateway` in browser:**
The upstream host is unreachable from the mac, or the proxy encountered a cert-minting error. Check Koala's proxy state label.

### Unset system proxy

After testing, remove the proxy configuration in System Settings → Network to restore normal networking.
