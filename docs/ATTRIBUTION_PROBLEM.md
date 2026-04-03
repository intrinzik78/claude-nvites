{
  "problem": {
    "name": "Offline-to-Online Attribution Gap",
    "summary": "QR codes bridge physical to digital, but there is no reliable, low-friction way to tie a scan to downstream conversions and revenue across arbitrary customer-owned systems.",
    "core_issue": "Attribution breaks across domain boundaries, system boundaries, and identity persistence, preventing a clean scan → session → conversion → revenue chain."
  },
  "root_causes": [
    {
      "category": "browser_security_model",
      "description": "Cookies are domain-scoped. A third-party redirect service cannot set a first-party cookie on a customer’s domain, breaking attribution continuity unless additional integration is performed."
    },
    {
      "category": "system_fragmentation",
      "description": "Scan events, web sessions, and conversions live in separate systems (QR platform, analytics, CRM/booking/POS) with no shared identifier by default."
    },
    {
      "category": "identity_persistence",
      "description": "There is no durable, guaranteed identity across scan → browse → conversion, especially across devices, shared links, or privacy-restricted environments."
    },
    {
      "category": "integration_requirement",
      "description": "Reliable attribution requires integration into the destination system (frontend, backend, or CRM), which increases implementation complexity and friction."
    },
    {
      "category": "privacy_constraints",
      "description": "Modern browser privacy controls reduce reliability of cookies and cross-site tracking, making passive attribution approaches less effective."
    }
  ],
  "current_market_behavior": {
    "standard_solution": [
      "dynamic QR codes",
      "scan analytics (count, device, location)",
      "UTM parameter passthrough to analytics platforms"
    ],
    "why_it_stops_here": [
      "no integration required",
      "works across any destination URL",
      "low technical complexity",
      "fits self-serve SaaS model"
    ],
    "result": "Most QR platforms provide scan-level insights and basic analytics integration but do not solve end-to-end revenue attribution."
  },
  "attribution_gap": {
    "expected_chain": [
      "scan",
      "session",
      "user",
      "conversion",
      "revenue"
    ],
    "actual_state": {
      "scan": "captured by QR platform",
      "session": "captured by analytics platform",
      "conversion": "captured by website or backend system",
      "revenue": "captured by CRM/POS/booking system"
    },
    "failure_mode": "No shared, persistent identifier links all stages together reliably."
  },
  "available_solutions": [
    {
      "solution": "same_root_domain_control",
      "description": "Use a tracking subdomain under the customer’s root domain to set first-party cookies directly.",
      "tradeoffs": [
        "requires DNS configuration",
        "requires customer trust and setup",
        "adds onboarding friction"
      ]
    },
    {
      "solution": "token_pass_through",
      "description": "Mint an attribution token and pass it via URL; destination system must capture and persist it.",
      "tradeoffs": [
        "requires frontend/backend integration",
        "can be lost without proper handling",
        "depends on customer implementation quality"
      ]
    },
    {
      "solution": "hosted_funnel",
      "description": "Own the landing page and capture identity or conversion events before redirecting downstream.",
      "tradeoffs": [
        "changes product scope",
        "may reduce customer flexibility",
        "introduces UX and brand considerations"
      ]
    },
    {
      "solution": "server_to_server_integration",
      "description": "Integrate with CRM/booking/POS systems via APIs or webhooks to receive conversion events tied to attribution tokens.",
      "tradeoffs": [
        "requires system integration",
        "varies widely by customer stack",
        "higher implementation cost"
      ]
    }
  ],
  "why_qr_companies_avoid_solving": [
    {
      "reason": "product_scope_expansion",
      "description": "Solving attribution turns a simple QR generator into a complex integration and data platform."
    },
    {
      "reason": "onboarding_friction",
      "description": "DNS setup, code changes, or system integrations reduce self-serve adoption."
    },
    {
      "reason": "support_complexity",
      "description": "Attribution issues become harder to debug across multiple systems and environments."
    },
    {
      "reason": "market_tolerance",
      "description": "Most customers accept scan counts and basic analytics as 'good enough'."
    },
    {
      "reason": "pricing_misalignment",
      "description": "Commodity QR pricing does not support the cost of building and supporting deep attribution systems."
    }
  ],
  "implication": {
    "product_shift": "Moving beyond scan analytics requires building a first-party attribution and integration layer, not just a QR tool.",
    "opportunity": "High-value customers who need ROI clarity are underserved.",
    "constraint": "Any solution must balance attribution accuracy with minimal integration friction."
  }
}