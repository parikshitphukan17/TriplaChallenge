<div align="center">
   <img src="/img/logo.svg?raw=true" width=600 style="background-color:white;">
</div>

# Backend Engineering Take-Home Assignment: Dynamic Pricing Proxy

Welcome to the Tripla backend engineering take-home assignment\! 🧑‍💻 This exercise is designed to simulate a real-world problem you might encounter as part of our team.

⚠️ **Before you begin**, please review the main [FAQ](/README.md#frequently-asked-questions). It contains important information, **including our specific guidelines on how to submit your solution.**

## The Challenge

At Tripla, we use a dynamic pricing model for hotel rooms. Instead of static, unchanging rates, our model uses a real-time algorithm to adjust prices based on market demand and other data signals. This helps us maximize both revenue and occupancy.

Our Data and AI team built a powerful model to handle this, but its inference process is computationally expensive to run. To make this product more cost-effective, we analyzed the model's output and found that a calculated room rate remains effective for up to 5 minutes.

This insight presents a great optimization opportunity, and that's where you come in.

## Your Mission

Your mission is to build an efficient service that acts as an intermediary to our dynamic pricing model. This service will be responsible for providing rates to our users while respecting the operational constraints of the expensive model behind it.

You will start with a Ruby on Rails application that is already integrated with our dynamic pricing model. However, the current implementation fetches a new rate for every single request. Your mission is to ensure this service handles the pricing models' constraints.

## Core Requirements

1. Review the pricing model's API and its constraints. The model's docker image and documentation are hosted on dockerhub:  [tripladev/rate-api](https://hub.docker.com/r/tripladev/rate-api).

2. Ensure rate validity. A rate fetched from the pricing model is considered valid for 5 minutes. Your service must ensure that any rate it provides for a given set of parameters (`period`, `hotel`, `room`) is no older than this 5-minute window.

3. Honor throughput requirements. Your solution must be able to handle at least 10,000 requests per day from our users while using a single API token.

## How We'll Evaluate Your Work

This isn't just about getting the right answer. We're excited to see how you approach the problem. Treat this as you would a production-ready feature.

  * We'll be looking for clean, well-structured, and testable code. Feel free to add dependencies or refactor the existing scaffold as you see fit.
  * How do you decide on your approach to meeting the performance and cost requirements? Documenting your thought process is a great way to share this.
  * A reliable service anticipates failure. How does your service behave if the pricing model is slow, or returns an error? Providing descriptive error messages to the end-user is a key part of a robust API.
  * We want to see how you work around constraints and navigate an existing codebase to deliver a solution.


## Minimum Deliverables

1.  A link to your Git repository containing the complete solution.
2.  Clear instructions in the `README.md` on how to build, test, and run your service.

We highly value seeing your thought process. A great submission will also include documentation (e.g., in the `README.md`) discussing the design choices you made. Consider outlining different approaches you considered, their potential tradeoffs, and a clear rationale for why you chose your final solution.

## Development Environment Setup

The project scaffold is a minimal Ruby on Rails application with a `/api/v1/pricing` endpoint. While you're free to configure your environment as you wish, this repository is pre-configured for a Docker-based workflow that supports live reloading for your convenience.

The provided `Dockerfile` builds a container with all necessary dependencies. Your local code is mounted directly into the container, so any changes you make on your machine will be reflected immediately. Your application will need to communicate with the external pricing model, which also runs in its own Docker container.

### Quick Start Guide

Follow these steps to run, test, and view the API documentation of the proxy service.

#### Step 1: Start the Service
Build and boot the Docker containerized environment. This command runs the Rails proxy application on port `3000` and the mock upstream pricing API on port `8080`:
```bash
docker compose up -d --build
```

#### Step 2: Verify the Pricing Endpoint
Send a sample GET request to verify the service is successfully reading rates from the cache:
```bash
curl 'http://localhost:3000/api/v1/pricing?period=Summer&hotel=FloatingPointResort&room=SingletonRoom'
```
*Note: The first request triggers a cold-start sync fetch to populate the cache. Subsequent requests will be served under 10ms.*

#### Step 3: Run the RSpec Test Suite
Run the automated RSpec tests to verify all caching, locking, retries, Cartesian mappings, and error status code handling:
```bash
# Run the full RSpec test suite
docker compose exec interview-dev env RAILS_ENV=test bundle exec rspec

# Run service unit specs only
docker compose exec interview-dev env RAILS_ENV=test bundle exec rspec spec/services/api/v1/pricing_service_spec.rb

# Run request integration specs only
docker compose exec interview-dev env RAILS_ENV=test bundle exec rspec spec/requests/api/v1/pricing_spec.rb
```

#### Step 4: Update the Swagger Documentation
If you make changes to endpoint routes, parameters, or JSON schemas, you can update the OpenAPI specifications by executing our Swagger generation helper script. The script detects if you are running it on the host or inside the container and runs Rswag:
```bash
# Execute the swagger update helper script from the host terminal
./bin/update_swagger.sh
```

#### Step 5: Check the Swagger UI
Access the interactive Swagger documentation page in your web browser:
```
http://localhost:3000/api-docs
```
From here, you can explore schemas for success or error responses (`INVALID_PARAMETERS`, `RATE_NOT_FOUND`, etc.) and test the live API directly using the "Try it out" feature.

---

#### Configuration Options
By default, the app uses a file-based cache and local locking. You can configure the application behavior by passing environment variables:
* `CACHE_PROVIDER_TYPE`: Toggle the caching backend (`redis` or `rails_cache`).
* `REDIS_URL`: Redis connection URL (e.g. `redis://localhost:6379/0`).
* `RATE_API_TIMEOUT_SECONDS`: Dynamic upstream API timeout in seconds (default: `3.0`).
* `PROMETHEUS_COLLECTOR_URL`: Custom URL pointing to the Prometheus Exporter server (default: `http://localhost:9394`).
* `OTEL_EXPORTER_OTLP_ENDPOINT`: Target OpenTelemetry collector URL (e.g., `http://localhost:4317`).
* `OTEL_SERVICE_NAME`: Service name identifier for OTel traces (default: `dynamic-pricing-proxy`).

---

#### Observability & Observability Telemetry
The application includes a built-in production-grade observability stack:
1. **JSON Logs (`lograge`)**: Rails logs are formatted as single-line JSON payloads and automatically append OpenTelemetry `trace_id` and `span_id` context details.
2. **HTTP Traces (`opentelemetry`)**: Automatically traces inbound HTTP requests, database SQL operations, and outbound client calls.
3. **Prometheus Metrics (`prometheus_exporter`)**:
   - Spins up a local metrics aggregator container.
   - Access metrics locally by scraping: `curl http://localhost:9394/metrics`.
   - Metrics include: cache hits/misses, circuit breaker state, upstream failures (timeout, connection failed, etc.), and job execution duration.



---

## 🛠️ Optimization Details & Architecture Decisions

We have fully optimized the proxy service to handle 10,000+ daily requests within the 1,000 requests/day upstream API limit. Below is an overview of the design choices made. For a deep-dive technical analysis (including concurrency mathematics, Little's Law, and thread safety), please refer to **[README_CONSIDERATIONS.md](file:///Users/parikshitphukan/Desktop/Repo/interview/dynamic-pricing/README_CONSIDERATIONS.md)**.

### 1. Capacity Planning & Single-Pod Setup
* **The Calculations:**
  - **Volume:** 10,000 requests/day $\approx$ $0.116$ requests/sec (RPS) on average.
  - **Peak Volume (10x):** $1.16$ RPS.
  - **Cache Read Latency:** $< 5 \text{ ms}$.
  - **Peak Concurrency (Little's Law):** $L = 1.16 \text{ RPS} \times 0.005 \text{ seconds} \approx 0.0058$ concurrent requests.
  - **Conclusion:** A single container pod running Puma (5 threads) can handle up to **1,000 RPS** when reading from cache. Therefore, **1 pod is more than sufficient**, and a distributed cache like Redis is not required for the initial setup.

### 2. Proactive Bulk Pre-fetching
* **Why it beats Cache-Aside:**
  - Standard lazy-loading (Cache-Aside) suffers from **Cache Stampede (Thundering Herd)** where multiple concurrent requests on a cache miss hit the upstream API at the same time, quickly exhausting the quota.
  - The parameter space is closed and small: $4 \text{ periods} \times 3 \text{ hotels} \times 3 \text{ rooms} = 36$ total combinations.
  - The Pricing Model API supports querying an array of attributes in a single request.
  - **Our Solution:** A background scheduler thread runs every **4 minutes** to trigger `RefreshRatesJob`, which queries all 36 combinations in a **single bulk API request** and caches them.
  - **Quota Consumption:** $\frac{24 \times 60}{4} = 360$ API requests/day (only **36%** of the 1,000 requests/day quota), ensuring users experience **100% cache hits** with sub-10ms response times.

### 3. Provider Pattern for Cache & Locks
* Even though Redis is not required for a single-pod setup, we implemented a modular **Provider Pattern** defining a standard interface for caching and locking operations:
  - `RailsCacheProvider`: Wraps `Rails.cache` (default `:file_store` in development/production for sharing cache between server and console processes).
  - `RedisProvider`: Direct connection using the `redis` client (with lazy loading to prevent boot crashes if the gem is not bundled).
* Easily switch providers via the `CACHE_PROVIDER_TYPE` environment variable.

### 4. Real-World Resiliency & Defensive Coding
* **Synchronous-First Cache Expiration:** If the cache is expired (> 5 minutes old) but the scheduler hasn't updated it yet, incoming user requests try to acquire the refresh lock to fetch fresh rates synchronously (returning them immediately with no disclaimer on success). If the API is offline, they gracefully fall back to stale cached rates (with a warning disclaimer) and enqueue an asynchronous refresh job. If another worker is already fetching rates (lock is held), the request immediately serves the stale rate fallback without spin-locking, preventing web server thread starvation.
* **Locking & Concurrency:** Both background jobs and cold-start requests utilize a provider lock key `dynamic_pricing:refresh_lock` with atomic writes (`unless_exist: true`) to prevent multiple processes from spamming the API simultaneously. If a request arrives on a cold start and the lock is held, it spin-locks (sleeps 100ms and retries, up to 1 second) and resolves from the cache warmed by the active fetcher. For expired but populated cache reads, if the lock is held, stale rates are served immediately with no spin-locking.
* **API Outages & Socket Errors:** `RefreshRatesJob` sets a configurable HTTP timeout (defaulting to **3 seconds**, customizable via `RATE_API_TIMEOUT_SECONDS`) and handles socket errors, retrying up to 3 times with exponential backoff (sleeping 2s, then 4s). If all retries are exhausted, the proxy activates a **10-minute API Cool-Down (Circuit Breaker)**. During this cool-down, any scheduler cycles or user request sync-refreshes skip calling the upstream API to protect the 1,000 requests/day quota. If the API remains down, the proxy continues serving stale cached rates indefinitely (deliberate design choice for maximum availability) rather than failing user booking funnels. If the cache is completely empty (e.g. cold start + API down), the proxy returns a `503 Service Unavailable`.

