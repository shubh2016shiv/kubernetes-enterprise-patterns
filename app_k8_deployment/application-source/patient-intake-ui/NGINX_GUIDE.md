# NGINX Configuration Guide for Frontend Proxy

## What is This Document?

This guide explains **nginx.conf** line-by-line for someone seeing nginx for the first time. You will learn:

- **Where** nginx.conf lives in the Kubernetes architecture
- **What** each configuration directive does
- **Why** each setting is necessary in a production system
- **How** traffic flows through the frontend tier

---

## Architecture: Where Does nginx.conf Live?

```
┌─────────────────────────────────────────────────────────────────┐
│                     LEARNER'S BROWSER                           │
│                   (On Windows/WSL2 laptop)                      │
└───────────────────────────────┬─────────────────────────────────┘
                                │
                    http://localhost:30001
                                │
                                ▼
┌────────────────────────────────────────────────────────────────┐
│        KUBERNETES KIND CLUSTER                                 │
│                                                                │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  FRONTEND TIER (patient-intake-ui Deployment)           │   │
│  │  ┌───────────────────────────────────────────────────┐  │   │
│  │  │ Container: nginx:alpine                           │  │   │
│  │  │ Working on: /usr/share/nginx/html (static files)  │  │   │
│  │  │ Config file: /etc/nginx/nginx.conf ← YOU ARE HERE │  │   │
│  │  │ Listen on: Port 8080 inside the container         │  │   │
│  │  ├─── Serves static HTML/CSS/JS form                 │  │   │
│  │  └─── Proxies /api/* calls to backend Service        │  │   │
│  │  └───────────────────────────────────────────────────┘  │   │
│  └─────────────────────────────────────────────────────────┘   │
│         │                                                      │
│         │ Service DNS: patient-record-api-service:8080         │
│         ▼                                                      │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  BACKEND TIER (patient-record-api Deployment)           │   │
│  │  FastAPI Python app listening on port 8080              │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

### Key Insight

**nginx.conf is the configuration file that runs INSIDE the frontend container.** It tells nginx:

1. What port to listen on (`listen 8080`)
2. Where static files are stored (`root /usr/share/nginx/html`)
3. How to handle different types of requests (static files vs. API calls)
4. How to forward API requests to the backend (`proxy_pass`)

---

## Line-by-Line Configuration Explanation

### 1. `listen 8080;` — What Port Does nginx Listen On?

```nginx
listen 8080;
```

**What this means:**  
nginx will accept incoming connections on **port 8080 INSIDE the container**.

**Why 8080 and not port 80?**

In Linux, ports below 1024 require **root privileges** to bind. Our nginx container runs as a **non-root user** (security best practice). So we use port 8080, which doesn't require special privileges.

**How does traffic reach this port?**

When you open your browser and visit `http://localhost:30001`:

```
Browser (localhost:30001)
    ↓ [Kubernetes NodePort Service routes to port 8080]
    ↓
nginx container listens on 8080  ← This directive catches it
```

**Analogy:**  
Think of `listen 8080` as "which mailbox do I check?" If requests are letters arriving at your house (NodePort 30001), they get sorted by a postal worker (Kubernetes Service), and then you check mailbox 8080.

**Enterprise Equivalent:**

In production, you might have:
- Multiple ports for different purposes (8080 for HTTP, 8443 for HTTPS)
- Health check ports separate from traffic ports
- Metrics ports for Prometheus scraping

---

### 2. `server_name _;` — What Hostnames to Respond To?

```nginx
server_name _;
```

**What this means:**  
The underscore `_` is a **wildcard** that means "respond to ANY hostname."

**Examples:**

```nginx
server_name localhost;              ← Only responds to localhost
server_name example.com;            ← Only responds to example.com
server_name example.com www.*;      ← Multiple specific hostnames
server_name _;                      ← Respond to ANYTHING (wildcard)
```

**Why use `_` in this lab?**

We use `_` because:
- Browser accesses `http://localhost:30001` → nginx sees hostname: `localhost`
- We don't care about hostname validation, so `_` matches everything
- This is a learning environment, not production

**What happens with a different hostname?**

```
Request 1: http://localhost:30001/           ← Matches server_name _
Request 2: http://patient-intake.local:8080  ← Also matches server_name _
Request 3: http://any-other-name:8080        ← Also matches server_name _
```

**Enterprise Equivalent:**

In production, you'd specify exact hostnames:

```nginx
server_name patient-intake.acme.com www.patient-intake.acme.com;
```

This **prevents accidental hosting** of your app on wrong domain names. If someone points a different domain to your server, nginx rejects it.

---

### 3. `root /usr/share/nginx/html;` — Where Are the Static Files?

```nginx
root /usr/share/nginx/html;
```

**What this means:**  
When someone requests a file like `/index.html`, nginx looks for it in `/usr/share/nginx/html/index.html`.

**Directory structure inside the container:**

```
/usr/share/nginx/html/
├── index.html           (main page)
├── style.css            (CSS styling)
├── app.js               (JavaScript for the form)
├── patient-form.html    (the patient intake form)
└── assets/
    └── logo.png
```

**How it's built:**

In the Dockerfile, we copy files into this directory:

```dockerfile
FROM node:18 AS builder
WORKDIR /app
COPY . .
RUN npm run build          # Creates dist/
FROM nginx:alpine
COPY --from=builder /app/dist /usr/share/nginx/html
#                          ↑ These files go here
```

**Example requests:**

```
Browser requests: /index.html
nginx looks at: /usr/share/nginx/html/index.html
Result: Returns the HTML file

Browser requests: /style.css
nginx looks at: /usr/share/nginx/html/style.css
Result: Returns the CSS file

Browser requests: /assets/logo.png
nginx looks at: /usr/share/nginx/html/assets/logo.png
Result: Returns the image
```

**Analogy:**  
`root` is "where does nginx look for my files?" If you say `root /var/www`, all files come from `/var/www`. If you say `root /usr/share/nginx/html`, all files come from there.

---

### 4. `index index.html;` — What File for Directory Requests?

```nginx
index index.html;
```

**What this means:**  
When someone requests a **directory** (no specific filename), serve the `index.html` file from that directory.

**Example flow:**

```
Browser requests: http://localhost:30001/
                  (empty path = root directory)
nginx thinks: "User asked for '/', which is a directory"
nginx checks: "What file should I serve for a directory?"
nginx sees: index index.html;
nginx serves: /usr/share/nginx/html/index.html
```

**Multiple index files:**

You can specify multiple fallbacks:

```nginx
index index.html index.htm default.html;
```

nginx tries them in order:
1. Try `/usr/share/nginx/html/index.html`
2. If not found, try `/usr/share/nginx/html/index.htm`
3. If not found, try `/usr/share/nginx/html/default.html`

**Enterprise:** This rarely changes. `index.html` is standard.

---

### 5. `location / { ... }` — Static Files Block

```nginx
location / {
    try_files $uri /index.html;
}
```

**What `location /` means:**

This block handles all requests that start with `/` (that don't match more specific blocks).

If a request matches both `/` and `/api/`, the more **specific** one (`/api/`) wins.

**What `try_files` does:**

This is the **Single Page Application (SPA)** pattern. Here's the flow:

```
Request 1: http://localhost:30001/index.html
  ↓
nginx looks for /usr/share/nginx/html/index.html
  ↓
File exists! Serve it

Request 2: http://localhost:30001/patients
  ↓
nginx looks for /usr/share/nginx/html/patients
  ↓
File doesn't exist!
  ↓
try_files says: "Fall back to /index.html instead"
  ↓
Serve /usr/share/nginx/html/index.html
  ↓
JavaScript in index.html examines the URL (/patients)
and renders the appropriate page
```

**Why this pattern?**

**Traditional web app:**
```
/patients → patients.html (separate file on server)
/doctors → doctors.html (separate file on server)
```

**Single Page App (React, Vue, Angular):**
```
All URLs → index.html (same file)
JavaScript inside index.html reads the URL
and decides what to display
```

Benefits:
- Faster page transitions (no full reload)
- Smoother user experience
- Easier state management in JavaScript
- Smaller file transfers

**Enterprise:** This is the standard pattern for modern web apps. Vue, React, Angular all use it.

---

### 6. `location /api/ { ... }` — API Proxy Block

```nginx
location /api/ {
    proxy_pass http://patient-record-api-service:8080/;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

This is the **critical section** for understanding frontend-backend communication in Kubernetes.

#### 6.1 `proxy_pass http://patient-record-api-service:8080/;`

**What this does:**

When nginx receives a request for `/api/...`, it **forwards** that request to a different server (the backend).

```
Browser sends: http://localhost:30001/api/patients
                                       ↓
nginx receives it, matches "location /api/"
                                       ↓
nginx forwards to: http://patient-record-api-service:8080/patients
                       ↑ Backend Service DNS name
                                                       ↑ port
```

**Breakdown:**

- **`patient-record-api-service`**  
  This is the **Kubernetes Service DNS name**. Inside the Kubernetes cluster, DNS automatically resolves this to the Service's ClusterIP, which then load-balances across backend pods.

- **`:8080`**  
  The port the FastAPI backend is listening on.

- **`/` (trailing slash)**  
  **Critical!** This strips `/api` from the path:
  - Browser requests: `/api/patients`
  - Backend receives: `/patients`
  
  Without the trailing slash, the backend would receive `/api/patients`, which doesn't match its routes.

**Complete request flow:**

```
Browser: POST http://localhost:30001/api/patients
    ↓ (NodePort 30001 → ClusterIP Service 8080)
nginx container port 8080
    ↓ (matches location /api/)
proxy_pass forwards to: http://patient-record-api-service:8080/patients
    ↓ (Kubernetes DNS resolves service name to ClusterIP)
Kubernetes ClusterIP Service (hidden load balancer)
    ↓ (routes to backend pods)
FastAPI pod receives: POST /patients
```

**Analogy:**

You're a receptionist.
- Customer: "I need to talk to the IT department's manager about patient records."
- You: "I'll connect you." [transfers call]
- IT department picks up and handles the request directly.

**Enterprise:**

In a service mesh (Istio, Linkerd), this proxying would be **instrumented** for:
- Automatic retries on failure
- Circuit breaking (stop sending requests if backend is down)
- Load balancing across multiple backend pods
- Distributed tracing (tracking a request across services)
- Rate limiting
- Mutual TLS (mTLS) encryption

For this lab, Kubernetes DNS + ClusterIP Service handles the basics.

#### 6.2 `proxy_http_version 1.1;`

**What this means:**

Use **HTTP/1.1** protocol when talking to the backend (not HTTP/1.0).

**Why it matters:**

```
HTTP/1.0: Closes connection after each request (inefficient)
HTTP/1.1: Keeps connection open for multiple requests (efficient)
```

**Performance comparison:**

```
Without HTTP/1.1:
Request 1 → New TCP connection → Sent → Closed
Request 2 → New TCP connection → Sent → Closed
Request 3 → New TCP connection → Sent → Closed
(9 network round-trips for 3 API calls)

With HTTP/1.1:
Request 1 → New TCP connection → Sent → Connection stays open
Request 2 → Reuse connection → Sent → Connection stays open
Request 3 → Reuse connection → Sent → Connection stays open
(3 network round-trips for 3 API calls)
```

**Enterprise:**

Production uses even faster protocols:
```nginx
proxy_http_version 2.0;    # HTTP/2 (multiplexing)
proxy_http_version 3.0;    # HTTP/3 (QUIC, even faster)
```

---

#### 6.3 `proxy_set_header Host $host;`

**What this does:**

Preserve the original `Host` header when forwarding to the backend.

**Without this directive:**

```
Browser sends: Host: localhost:30001
nginx forwards with: Host: patient-record-api-service:8080
Backend sees: "Request came from patient-record-api-service:8080"
```

The backend sees the **wrong hostname**. It might have:
- Host validation rules
- CORS (Cross-Origin Resource Sharing) rules
- Virtual hosting
- Logs that identify the original client

**With this directive:**

```
Browser sends: Host: localhost:30001
nginx forwards with: Host: localhost:30001
Backend sees: "Request came from localhost:30001"
```

The backend sees the **original hostname** and can handle it correctly.

**$host variable:**

`$host` is an nginx variable that means "the original Host header from the browser request."

**Analogy:**

You forward a customer's phone call but you say your own name:
- Department gets confused, thinks you're the real customer

Instead, you forward the call and say the customer's name:
- Department knows who they're actually talking to

---

#### 6.4 `proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;`

**What this does:**

Tell the backend **who the original client is** (the real IP address).

**Without this directive:**

```
Browser IP: 192.168.1.100
Browser → nginx container IP: 172.17.0.2

nginx forwards to backend
Backend sees: "Request came from 172.17.0.2 (nginx's internal IP)"
Backend loses real client IP for:
  - Logging: "Who made this request?"
  - Rate limiting: "Is this IP making too many requests?"
  - Geolocation: "Where is the user?"
  - Security: "Which IPs should we block?"
```

**With this directive:**

```
Browser IP: 192.168.1.100
nginx receives from 192.168.1.100
nginx adds header: X-Forwarded-For: 192.168.1.100
nginx forwards to backend

Backend reads header: "Ah, the real client is 192.168.1.100"
Backend logs: "Patient intake request from 192.168.1.100"
```

**$proxy_add_x_forwarded_for variable:**

This nginx variable:
- Takes the existing `X-Forwarded-For` header (if any)
- Appends the current proxy's IP
- Creates a chain showing all proxies in the path

**Example with multiple proxies:**

```
Browser (203.0.113.10)
  ↓ → Proxy A (10.0.0.1)
  ↓ → Proxy B (10.0.0.2)
  ↓ → Backend

Proxy A sets: X-Forwarded-For: 203.0.113.10
Proxy B appends: X-Forwarded-For: 203.0.113.10, 10.0.0.1
Backend sees: "Real client is 203.0.113.10, went through 10.0.0.1"
```

**Enterprise:**

Every proxy, load balancer, and Ingress controller MUST set `X-Forwarded-For`. Otherwise:
- Backend loses client IP
- Security monitoring fails
- Rate limiting breaks
- Logs become useless

---

#### 6.5 `proxy_set_header X-Forwarded-Proto $scheme;`

**What this does:**

Tell the backend whether the **original connection used HTTP or HTTPS**.

**Without this directive:**

```
Browser: https://example.com/api/patients (encrypted, secure)
    ↓
nginx terminates TLS (SSL/HTTPS)
nginx connects to backend: http://backend:8080/api/... (unencrypted)

Backend sees: "Request used HTTP (not HTTPS)"
Backend has security rule: "Reject HTTP requests, only accept HTTPS"
Backend rejects the LEGITIMATE request!
```

**With this directive:**

```
Browser: https://example.com/api/patients (encrypted)
    ↓
nginx terminates TLS
nginx adds header: X-Forwarded-Proto: https
nginx forwards: http://backend:8080/api/...

Backend reads header: "Original request was HTTPS"
Backend allows it: "Even though my connection is HTTP, the proxy handled encryption"
```

**$scheme variable:**

```
$scheme = https  ← If browser used https://
$scheme = http   ← If browser used http://
```

**Enterprise:**

TLS termination is standard in production:
- Ingress Controller (AWS ALB, GCP Load Balancer, Azure AGW)
- API Gateway
- WAF (Web Application Firewall)
- Service Mesh

All of them:
1. Receive HTTPS from client
2. Decrypt it
3. Forward HTTP to backend
4. Set `X-Forwarded-Proto: https` so backend knows

---

## Quick Reference Table

| Directive | What It Does | Example | Why It Matters |
|-----------|-------------|---------|---|
| `listen 8080` | What port to listen on | `listen 8080;` | Container must listen on non-root port |
| `server_name _` | What hostnames to accept | `server_name example.com;` | Prevent accidental hosting |
| `root /path` | Where static files live | `root /usr/share/nginx/html;` | nginx knows where to find files |
| `index file.html` | Default file for directories | `index index.html;` | `/` request serves index.html |
| `location /api/` | Match specific URL patterns | `location /api/ { ... }` | Route API calls differently |
| `proxy_pass` | Forward to backend | `proxy_pass http://backend:8080/;` | Frontend reaches backend |
| `proxy_http_version 1.1` | HTTP version for proxying | `proxy_http_version 1.1;` | Connection pooling for performance |
| `proxy_set_header Host` | Preserve hostname | `proxy_set_header Host $host;` | Backend sees real hostname |
| `proxy_set_header X-Forwarded-For` | Preserve client IP | `proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;` | Backend knows real client |
| `proxy_set_header X-Forwarded-Proto` | Preserve protocol (HTTP/HTTPS) | `proxy_set_header X-Forwarded-Proto $scheme;` | Backend knows TLS was used |

---

## Traffic Flow Diagram

### Complete Request Journey

```
┌──────────────────────────────────────────────────────────────────────┐
│ BROWSER (on your laptop)                                             │
│ User clicks "Submit Patient Form"                                    │
│ JavaScript sends: POST /api/patients                                 │
└──────────────────────────┬───────────────────────────────────────────┘
                           │
                           ↓
┌──────────────────────────────────────────────────────────────────────┐
│ HTTP Request to: http://localhost:30001/api/patients                │
└──────────────────────────┬───────────────────────────────────────────┘
                           │
                           ↓
┌──────────────────────────────────────────────────────────────────────┐
│ KUBERNETES NETWORKING                                                │
│ NodePort Service (port 30001) ← Kubernetes maps localhost:30001     │
│ ↓ Routes to                                                          │
│ ClusterIP Service: patient-intake-ui-service (port 8080)            │
└──────────────────────────┬───────────────────────────────────────────┘
                           │
                           ↓
┌──────────────────────────────────────────────────────────────────────┐
│ FRONTEND CONTAINER (nginx)                                           │
│ Listens on port 8080                                                │
│ Receives: POST /api/patients                                         │
│ ↓                                                                    │
│ Reads location rules:                                               │
│   "Does /api/patients match location /api/?" → YES                  │
│ ↓                                                                    │
│ Executes: proxy_pass http://patient-record-api-service:8080/        │
│ ↓                                                                    │
│ Adds headers:                                                       │
│   Host: localhost:30001                                            │
│   X-Forwarded-For: 192.168.1.100                                   │
│   X-Forwarded-Proto: http                                          │
│ ↓                                                                    │
│ Forwards to: http://patient-record-api-service:8080/patients       │
└──────────────────────────┬───────────────────────────────────────────┘
                           │
                           ↓
┌──────────────────────────────────────────────────────────────────────┐
│ KUBERNETES NETWORKING (again)                                        │
│ DNS resolves: patient-record-api-service → ClusterIP: 10.96.X.X    │
│ ClusterIP Service load-balances across backend pods                 │
│ ↓ Routes to                                                         │
│ Backend pod (one of possibly many)                                  │
└──────────────────────────┬───────────────────────────────────────────┘
                           │
                           ↓
┌──────────────────────────────────────────────────────────────────────┐
│ BACKEND CONTAINER (FastAPI)                                          │
│ Listens on port 8080                                                │
│ Receives:                                                           │
│   POST /patients                                                    │
│   Host: localhost:30001                                            │
│   X-Forwarded-For: 192.168.1.100                                   │
│   X-Forwarded-Proto: http                                          │
│ ↓                                                                    │
│ Reads headers:                                                      │
│   "Original request was from 192.168.1.100"                        │
│   "Original hostname was localhost:30001"                          │
│   "Original protocol was HTTP"                                     │
│ ↓                                                                    │
│ Process business logic:                                            │
│   1. Validate input                                                │
│   2. Connect to database                                           │
│   3. Insert patient record                                         │
│   4. Return response: HTTP 201 Created                             │
└──────────────────────────┬───────────────────────────────────────────┘
                           │
                           ↓ (Response travels back)
┌──────────────────────────────────────────────────────────────────────┐
│ nginx receives response from backend                                 │
│ Forwards response to browser                                        │
└──────────────────────────┬───────────────────────────────────────────┘
                           │
                           ↓
┌──────────────────────────────────────────────────────────────────────┐
│ BROWSER                                                              │
│ Receives: HTTP 201 Created + JSON response                          │
│ JavaScript processes response                                       │
│ User sees: "Patient record saved successfully!"                     │
└──────────────────────────────────────────────────────────────────────┘
```

---

## Why This Matters

A learner who understands this nginx.conf understands:

✅ **Frontend-backend communication in Kubernetes**  
How requests travel from browser through Kubernetes networking to backend

✅ **Service discovery (DNS inside clusters)**  
How `patient-record-api-service` resolves to the right backend pods

✅ **Reverse proxy pattern**  
Why and how frontend proxies requests to backend

✅ **Header manipulation**  
Why `X-Forwarded-*` headers exist and what they do

✅ **Static file serving vs. dynamic API calls**  
How to differentiate between `/` (static) and `/api/` (dynamic)

✅ **Port binding and networking in containers**  
How ports map through Kubernetes Services

✅ **TLS termination**  
Why `X-Forwarded-Proto` is necessary when encryption is involved

---

## Enterprise Equivalents

| What We Do Here | Enterprise Does | Why It Differs |
|---|---|---|
| nginx as proxy | API Gateway / Ingress Controller | Gateway handles TLS, auth, rate limiting, WAF |
| `proxy_pass` to Service DNS | Load Balancer (AWS ALB, GCP LB) | Cloud load balancers handle auto-scaling, health checks |
| Plain HTTP for internal calls | mTLS through Service Mesh (Istio, Linkerd) | Encryption + authentication for all inter-pod traffic |
| No retry logic | Automatic retries + circuit breaking | Fault tolerance built into platform |
| Kubernetes DNS | Service discovery + service mesh | Instrumented for metrics, tracing, security |
| Static files in container | CDN (CloudFront, Cloud CDN) | Serves from edge, not from container |

---

## Common Troubleshooting

### Browser shows 503 Service Unavailable

**Check:**
```bash
# Is nginx running?
kubectl logs -n patient-record-system deployment/patient-intake-ui

# Can nginx reach the backend?
kubectl exec -it <frontend-pod> -n patient-record-system -- \
  curl -v http://patient-record-api-service:8080/livez
```

### Browser shows 404 Not Found for static files

**Check:**
- Does `/usr/share/nginx/html/` exist in the container?
- Are files copied into the image?
- Use `kubectl exec` and run `ls -la /usr/share/nginx/html/`

### API requests hang or timeout

**Check:**
- Is `proxy_http_version 1.1` set? (prevents connection pooling without it)
- Are backend pods Ready?
- `kubectl get pods -n patient-record-system`

### Backend receives wrong hostname

**Check:**
- Is `proxy_set_header Host $host;` present?
- Without it, backend sees `patient-record-api-service` instead of original host

### Backend doesn't know real client IP

**Check:**
- Is `proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;` present?
- Backend should read `request.headers['X-Forwarded-For']`

---

## For the Curious: How to Test Locally

**Test static file serving:**
```bash
kubectl exec -it <frontend-pod> -n patient-record-system -- \
  curl -v http://localhost:8080/index.html
```

**Test API proxying:**
```bash
kubectl exec -it <frontend-pod> -n patient-record-system -- \
  curl -v http://localhost:8080/api/livez
```

**Inspect nginx configuration:**
```bash
kubectl exec <frontend-pod> -n patient-record-system -- \
  cat /etc/nginx/nginx.conf
```

**View nginx logs:**
```bash
kubectl logs <frontend-pod> -n patient-record-system -f
```

---

## Summary

**nginx.conf is a reverse proxy configuration.** It:

1. **Serves static files** (HTML, CSS, JS) from `/usr/share/nginx/html/`
2. **Routes API requests** to the backend Service
3. **Preserves client information** (hostname, IP, protocol) in headers
4. **Enables frontend-backend communication** through Kubernetes DNS and Services

This is the **frontend tier of a three-tier application** and the pattern used by:
- Traditional reverse proxies (nginx, Apache)
- API Gateways (Kong, AWS API Gateway)
- Ingress Controllers (nginx-ingress, AWS LBC)
- Load Balancers (AWS ALB, GCP LB, Azure AGW)

Understanding nginx.conf = Understanding how modern web applications route traffic.
