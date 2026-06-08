# Dynamic Pricing Proxy: Architecture & Design Considerations

This document details the architectural decisions, trade-offs, and design considerations for optimizing the Dynamic Pricing Proxy service to operate reliably under strict production constraints.

---

## 1. Context & Constraints

The proxy sits between our users and an expensive, rate-limited upstream Pricing Model API. The key constraints are:
- **Upstream Rate Limit:** 1,000 requests per day.
- **Rate Validity:** A rate is valid for up to 5 minutes after it is fetched.
- **Proxy Traffic:** Must handle at least 10,000 requests per day (10x the upstream limit).
- **Attribute Combinations:** The query parameters have a closed, small set of valid values:
  - `period`: Summer, Autumn, Winter, Spring (4 values)
  - `hotel`: FloatingPointResort, GitawayHotel, RecursionRetreat (3 values)
  - `room`: SingletonRoom, BooleanTwin, RestfulKing (3 values)
  - **Total combinations:** $4 \times 3 \times 3 = 36$ distinct combinations.

---

## 2. Capacity Planning & Concurrency Calculations

We perform capacity planning using systems architecture principles to determine if a single pod (container instance) is sufficient and if Redis is strictly necessary.

### Concurrency Estimation (Little's Law)
Little's Law defines the relation between average concurrency ($L$), throughput ($\lambda$), and latency ($W$):
$$L = \lambda \times W$$

1. **Daily Volume:** $10,000$ requests/day.
2. **Average Throughput ($\lambda_{\text{avg}}$):**
   $$\lambda_{\text{avg}} = \frac{10000 \text{ requests}}{86400 \text{ seconds}} \approx 0.116 \text{ requests per second (RPS)}$$
3. **Peak Throughput ($\lambda_{\text{peak}}$):**
   Applying a standard industry peak-to-average traffic multiplier of **10x** to account for high-volatility peak periods (e.g. promotions, morning rushes):
   $$\lambda_{\text{peak}} = 0.116 \times 10 \approx 1.16 \text{ RPS}$$
4. **Cache Read Latency ($W$):**
   Reading cached prices from local memory (`ActiveSupport::Cache::MemoryStore`) takes less than **$1 \text{ ms}$** ($0.001$ seconds). To be conservative, we assume an average cache read latency of **$5 \text{ ms}$** ($0.005$ seconds).
5. **Peak Concurrency ($L_{\text{peak}}$):**
   $$L_{\text{peak}} = 1.16 \text{ RPS} \times 0.005 \text{ seconds} \approx 0.0058 \text{ concurrent requests}$$
   Even under a massive flash spike of 100 requests arriving in the exact same second, peak concurrency is only $1.0$ concurrent request.

### Pod Capacity Capability
A single Puma process running Rails with the default pool of 5 threads can process:
$$\text{Max Throughput} = \frac{5 \text{ threads}}{0.005 \text{ seconds latency}} = 1,000 \text{ RPS}$$

- **Conclusion:** A single pod running the proxy can easily handle up to $1,000$ requests per second. With a peak requirement of only $1.16$ RPS, **1 pod is more than sufficient** to handle the 10,000 daily requests.
- **Redis Decision:** Since 1 pod is sufficient, a distributed cache layer like **Redis is NOT strictly needed**. We can use Rails' local cache (`ActiveSupport::Cache::MemoryStore` or `FileStore`) and local memory locks to keep our infrastructure footprint minimal, robust, and cost-effective.

---

## 3. Core Architecture: Proactive Bulk Pre-fetching

### Why a Refresh Job is Better than Cache-Aside
In a standard **Cache-Aside (Lazy Loading)** implementation:
- A user request triggers an API call on a cache miss.
- When cache expires, a burst of concurrent requests causes **Cache Stampede (Thundering Herd)** where multiple threads fetch the same data concurrently, exhausting the 1,000 requests/day quota in a few minutes.
- Uptime is dependent on upstream API availability at the moment of the cache miss.

### Proactive Background Refresh
Because the upstream API supports querying an array of attributes, we fetch all 36 combinations in a **single bulk API request**.
- **Number of Daily API Calls:**
  If we run our background refresh job every **4 minutes**:
  $$\text{Daily API Calls} = \frac{24 \text{ hours} \times 60 \text{ minutes}}{4 \text{ minutes}} = 360 \text{ requests/day}$$
- This consumes only **36%** of our daily quota (1,000 requests), leaving plenty of buffer for startup runs and retries.
- User requests experience **100% cache hits** with sub-millisecond latency.

### Handling Overlapping/Concurrent Refresh Jobs
* **Scenario:** If a background refresh is triggered while another fetch is already running (e.g. a previous job is hung or slow, or a cold-start sync fetch is underway).
* **Mitigation:**
  - Before starting the fetch, the refresh scheduler tries to acquire a lock (`dynamic_pricing:refresh_lock`) with a short TTL (e.g., 2 minutes).
  - If a fetch is already in progress, the lock will be held.
  - The new refresh job will **fail to acquire the lock and exit immediately (cancels itself)**, preventing duplicate/overlapping API requests.

---

## 4. Provider Pattern for Caching & Locking

Although Redis is not required for the single-pod setup, we design the caching and locking layers using a **Provider Pattern**. This ensures we can switch between local memory caching and Redis with a single configuration toggle if the service needs to scale to multiple pods in the future.

### Interface & Adaptors
We define a common interface for caching and locking operations:
- `CacheProviders::BaseProvider`: Interface defining `read_rates`, `write_rates`, `acquire_lock`, and `release_lock`.
- `CacheProviders::RailsCacheProvider`: Implementation using `Rails.cache` (ideal for single-pod deployments using MemoryStore/FileStore).
- `CacheProviders::RedisProvider`: Implementation using direct `Redis` connections (for multi-pod distributed environments).

### Cache Key Structure & Lookup Example
To optimize cache lookup times and minimize roundtrips (especially for network-based stores like Redis), we cache the entire rates map under a single parent key:
- **Cache Key:** `dynamic_pricing:rates_map`
- **Cached Value Payload:**
  ```ruby
  {
    rates: {
      "Summer:FloatingPointResort:SingletonRoom" => 76600,
      "Summer:FloatingPointResort:BooleanTwin" => 44200,
      # ... (all 36 combinations)
    },
    fetched_at: 2026-06-03 08:30:00 UTC
  }
  ```

#### Example Key Lookup for an Input Request
When a user queries the proxy endpoint with:
- **Period:** `Summer`
- **Hotel:** `FloatingPointResort`
- **Room:** `SingletonRoom`

1. The proxy reads the payload from the cache provider under the key `"dynamic_pricing:rates_map"`.
2. It generates a query string by joining the request parameters with colons:
   `"#{period}:#{hotel}:#{room}"` $\rightarrow$ `"Summer:FloatingPointResort:SingletonRoom"`.
3. It fetches the rate value directly from the `rates` map:
   `payload[:rates]["Summer:FloatingPointResort:SingletonRoom"]` $\rightarrow$ returns `76600`.

---

## 5. Edge Cases & Resiliency

### 1. Cold Start Cache Warmup
If the cache is empty on server boot and a user request arrives before the first scheduler cycle:
- The request sees a cache miss.
- It attempts to acquire the refresh lock.
- **Lock Acquired:** The process runs the bulk API call, warms up the cache for all 36 combinations, and serves the rate.
- **Lock Held (Concurrency):** Other requests enter a **spin-lock with backoff** (sleeping for 100ms and checking the cache, up to 1 second) rather than calling the API. They resolve directly from the warmed cache.

### 2. Upstream API Downtime (Expired Cache & Resiliency)
* **Strategy (Resilient with Disclaimer & Indefinite Cache):**
  - If the upstream API is down, the background job will fail.
  - Retries with exponential backoff (up to 3 attempts, waiting 2s, then 4s between attempts) will run to recover from transient glitches and socket errors.
  - We store cached rates **indefinitely** (with no cache TTL expiration). This is a deliberate resilience decision: if the API suffers an extended outage (e.g., lasting more than a day), the proxy can continue to serve the last known rates alongside the stale rate disclaimer rather than returning a 503 error page, ensuring business continuity.
  - If the 5-minute validity window passes:
    - **If stale rates exist:** We return the stale rate with a warning disclaimer:
      ```json
      {
        "resultInfo": {
          "code": "S",
          "message": "Success",
          "codeId": "1"
        },
        "data": {
          "rate": "12000",
          "disclaimer": "Rates are expired, please retry again in at least 5 minutes to get latest rate"
        }
      }
      ```
      This ensures high availability during transient API outages. We also write a warning to the Rails logger.
    - **If no stale rates exist (Cold Start + API Outage):** We return a `503 Service Unavailable` error:
      ```json
      {
        "resultInfo": {
          "code": "F",
          "message": "Rates are unavailable and cache is empty. Please retry in 5 minutes.",
          "codeId": "SERVICE_UNAVAILABLE"
        },
        "data": null
      }
      ```

### 3. Synchronous-First Cache Expiration & Locking (Real-World Resiliency)
We implement a defensive **Synchronous-First Cache Expiration** pattern to handle cases where the cache has expired but the background scheduler has not started a refresh cycle yet:

#### Scenario A: Cache is expired, background refresh has not run, lock is free, user request arrives
1. The user request reads the cached rates and detects that they are expired (> 5 minutes old).
2. Since the refresh lock is free, the proxy **synchronously triggers the refresh job** (`RefreshRatesJob.new.perform`) inline.
3. Inside `RefreshRatesJob`, it **acquires the distributed lock** (`dynamic_pricing:refresh_lock`) to prevent any other concurrent process from triggering duplicate calls.
4. **On Success:** The API call finishes, updates the cache with fresh rates, releases the lock, and the user receives the **latest, 100% accurate rate** immediately (no stale disclaimer).
5. **On Failure (Upstream API offline/timeout):** If the synchronous fetch fails (after retrying 3 times with exponential backoff), the lock is released. The proxy falls back to serving the cached **stale rate** (with the expired disclaimer) and enqueues an asynchronous background job (`RefreshRatesJob.perform_later`) to retry later.

#### Scenario B: Cache is expired, background refresh has not run, lock is held (concurrency), user request arrives
1. The user request detects that the cache is expired.
2. It checks the provider and sees that the refresh lock is **already held** (meaning another worker is currently executing the fetch).
3. To prevent thread starvation and keep latency low ($<10\text{ ms}$), the proxy **skips spin-locking** and immediately falls back to serving the cached **stale rate** and disclaimer.
4. The user request returns immediately, ensuring that web worker threads are not blocked.

---

### 4. API Cool-Down & Circuit Breaker (Quota Outage Protection)

* **The Outage Quota Exhaustion Risk:**
  When the upstream API is offline, a sync or async fetch fails and releases the refresh lock. The cache is not updated and remains expired. Since the cache is still expired and the lock is free, the next user request will immediately trigger another synchronous fetch attempt (with 3 retries). Under moderate traffic (e.g. 100 requests/minute), this loop would exhaust the 1,000 requests/day quota in less than 10 minutes of API downtime.

* **API Cool-Down Guard:**
  To solve this, we implement a Cool-Down (Circuit Breaker) key `dynamic_pricing:api_cool_down` in the cache provider:
  1. When `RefreshRatesJob` fails after all 3 retries, it writes the cool-down key to the cache with a **10-minute expiry (TTL)**.
  2. Before any API calls are made, the background scheduler thread checks this key and exits immediately if active.
  3. Before triggering any synchronous fetch, `PricingService` checks this key. If active, it skips the sync fetch attempt, avoids hitting the API, and serves the cached stale rates immediately.

* **Outage Quota Calculation:**
  During an outage, we make at most 3 API requests (1 attempt + 2 retries) every 10 minutes.
  $$\text{Max Outage Calls} = \frac{24 \text{ hours} \times 60 \text{ minutes}}{10 \text{ minutes}} \times 3 \text{ requests} = 432 \text{ requests/day}$$
  This guarantees that even during a continuous, full 24-hour upstream API outage, the proxy consumes at most **43.2%** of the 1,000 requests/day quota, leaving 568 requests for normal operation.

---

### 5. Automated API Documentation & Testing (RSpec & Rswag)

* **The Problem:**
  Writing Swagger/OpenAPI documentation manually can lead to drift between the code implementation and the documentation specs, causing integration bugs.
* **The Solution (Spec-Driven Documentation):**
  We fully migrated the test suite from Minitest to **RSpec** and **Rswag**. 
  - The request spec (`spec/requests/api/v1/pricing_spec.rb`) is written using the Rswag DSL.
  - Running Rswag specs dynamically verifies endpoint responses against defined schemas *and* generates the complete `swagger/v1/swagger.yaml` OpenAPI 3.0 specification.
  - The interactive Swagger UI is served natively at `/api-docs` using mounted Rails engines, making it easy to test endpoints live.
* **Unification Benefits:**
  By removing Minitest and adopting RSpec globally, we maintain a clean testing environment with a single, highly extensible framework, covering both unit specs and API schema validation tests in a unified pipeline.
