# Usage Examples

Real-world scenarios demonstrating the cc-sessions + Superpowers workflow.

## Table of Contents

1. [Complete E-commerce Feature](#1-complete-e-commerce-feature-email-notifications)
2. [Simple Utility Function](#2-simple-utility-function-date-formatter)
3. [Debugging Production Issue](#3-debugging-production-issue)
4. [Refactoring Legacy Code](#4-refactoring-legacy-code)
5. [Parallel Feature Development](#5-parallel-feature-development-git-worktrees)
6. [TDD Implementation](#6-tdd-implementation)
7. [Production Deployment](#7-production-deployment)

---

## 1. Complete E-commerce Feature: Email Notifications

**Scenario:** Add email notifications for order confirmations with proper testing and deployment.

### Full DAIC Workflow

#### Discussion Phase

```bash
mek: Add email notifications for order confirmations
```

**Refine with brainstorming:**
```
/superpowers:brainstorm

# Questions asked:
- Email service provider? (SendGrid, AWS SES, SMTP?)
- Template engine? (Handlebars, React Email?)
- What triggers the email?
- Include order details? Invoice PDF?
- Retry logic for failed sends?
- Rate limiting needed?
- Testing strategy?

# Your answers:
- Use SendGrid
- React Email for templates
- Trigger on order status = "confirmed"
- Include order summary, no PDF for now
- 3 retry attempts with exponential backoff
- No rate limiting needed yet
- Use Ethereal for testing
```

**Output:** Requirements saved to `docs/vision.md`

---

#### Alignment Phase

**Load context:**
```bash
start^:

# cc-sessions analyzes:
- Found existing EmailService base class
- Located email templates directory
- Identified retry logic pattern
- Loaded 3 relevant past session summaries
```

**Generate plan:**
```
/superpowers:write-plan
```

**Plan generated:**
1. Infrastructure Setup (dependencies, env variables)
2. Email Templates (React Email component)
3. Email Service (SendGrid integration)
4. Retry Logic (exponential backoff)
5. Integration Point (order service hook)
6. Testing (unit + integration)
7. Monitoring (logging, metrics)
8. Documentation (README, env vars)

**Approve:**
```bash
yert  # Locks plan as approved scope
```

---

#### Implementation Phase

```
/superpowers:execute-plan
```

**Checkpoint 1: Infrastructure**
```typescript
// Installs dependencies
npm install @sendgrid/mail react-email @react-email/components

// Creates src/services/email.service.ts
export class EmailService {
  private client: MailService;

  constructor() {
    this.client = new MailService();
    this.client.setApiKey(process.env.SENDGRID_API_KEY);
  }
}
```

```
✅ Checkpoint 1 complete: Infrastructure setup done
Continue? (type 'continue')
```

**Checkpoint 2: Email Templates**
```tsx
// Creates src/emails/OrderConfirmation.tsx
import { Html, Head, Body, Container, Text } from '@react-email/components';

interface OrderConfirmationProps {
  orderNumber: string;
  customerName: string;
  items: Array<{ name: string; quantity: number; price: number }>;
  total: number;
}

export default function OrderConfirmation(props: OrderConfirmationProps) {
  return (
    <Html>
      <Body style={{ fontFamily: 'Arial, sans-serif' }}>
        <Container>
          <Text>Hi {props.customerName},</Text>
          <Text>Thank you for your order #{props.orderNumber}!</Text>
          {props.items.map(item => (
            <Text key={item.name}>
              {item.name} x{item.quantity} - ${item.price}
            </Text>
          ))}
          <Text>Total: ${props.total}</Text>
        </Container>
      </Body>
    </Html>
  );
}
```

**TDD skill auto-activates:**
```typescript
// Creates tests FIRST
test('renders order confirmation email', () => {
  const html = render(<OrderConfirmation
    orderNumber="ORD-12345"
    customerName="John Doe"
    items={[{ name: 'Product A', quantity: 2, price: 29.99 }]}
    total={59.98}
  />);
  expect(html).toMatchSnapshot();
});
```

```
✅ Checkpoint 2 complete: Templates with tests
Continue? (y/n)
```

**Checkpoint 3: Retry Logic**
```typescript
export class EmailService {
  async sendOrderConfirmation(orderId: string): Promise<void> {
    const maxRetries = 3;
    const baseDelay = 1000;

    for (let attempt = 0; attempt < maxRetries; attempt++) {
      try {
        const order = await this.db.orders.findById(orderId);
        const html = render(<OrderConfirmation {...order} />);

        await this.client.send({
          to: order.customerEmail,
          from: process.env.FROM_EMAIL,
          subject: `Order Confirmation #${order.orderNumber}`,
          html
        });

        await this.logger.info('Email sent', { orderId });
        return;
      } catch (error) {
        const delay = baseDelay * Math.pow(2, attempt);

        if (attempt < maxRetries - 1) {
          await this.sleep(delay);
        } else {
          await this.dlq.add({ orderId, error });
          throw error;
        }
      }
    }
  }
}
```

**Error-fix skill auto-activates:**
```
⚠️ Detected: Missing network timeout handling
Adding timeout configuration...
```

```
✅ Checkpoint 3 complete: Service with retry logic
Continue? (y/n)
```

**Checkpoint 4: Integration**
```typescript
// Updates src/services/order.service.ts
export class OrderService {
  async confirmOrder(orderId: string): Promise<Order> {
    const order = await this.db.orders.update(orderId, {
      status: 'confirmed'
    });

    // Async email via job queue (doesn't block order confirmation)
    await this.queue.add('send-order-email', { orderId });

    return order;
  }
}
```

**Checkpoint 5: Full Test Suite**
```typescript
describe('EmailService', () => {
  it('should send email', async () => { /* ... */ });
  it('should retry on failure', async () => { /* ... */ });
  it('should add to DLQ after 3 failures', async () => { /* ... */ });
});
```

```
✅ All tests passing (18/18)
✅ Checkpoint 5 complete
```

---

#### Check Phase

```bash
finito
```

**Verification:**
```
🔍 Running checks:
✅ All tests passing (18/18)
✅ No console.logs or debug code
✅ TypeScript compilation successful
✅ No security vulnerabilities
✅ ESLint: 0 errors
```

**Auto-commit:**
```bash
git commit -m "feat: Add email notifications for order confirmations

- Implemented EmailService with SendGrid integration
- Created React Email template for order confirmations
- Added retry logic with exponential backoff (3 attempts)
- Integrated with order service via Bull job queue
- Added comprehensive test suite (18 tests)
- Configured Ethereal for testing
- Documented environment variables

Tested: All tests passing
Verified: No security vulnerabilities

🤖 Generated with Claude Code + cc-sessions
Co-Authored-By: Claude <noreply@anthropic.com>"
```

**Session summary saved:** `sessions/logs/email-notifications-summary.md`

**Result:**
- ⏱️ 67 minutes total (vs ~2 hours ad-hoc)
- ✅ 1 implementation pass (no refactors)
- ✅ Tests built-in via TDD
- ✅ Summary for future reference
- 📊 ~40% time savings

---

## 2. Simple Utility Function: Date Formatter

**Scenario:** Add date formatter utility using TDD

### Quick Workflow

```bash
# Discussion
mek: Add date formatter utility function
/superpowers:brainstorm
# Answers: ISO/US/EU formats, UTC default, null handling

# Alignment
start^:
/superpowers:write-plan
yert

# Implementation
/superpowers:execute-plan
```

**TDD skill guides:**
```typescript
// 1. RED: Write failing test
test('formats US date', () => {
  expect(formatDate('2025-11-23', 'us')).toBe('11/23/2025');
});

// 2. GREEN: Minimal implementation
export function formatDate(date: string, format: 'iso' | 'us' | 'eu'): string {
  if (format === 'us') {
    const [y, m, d] = date.split('-');
    return `${m}/${d}/${y}`;
  }
  // ... other formats
}

// 3. REFACTOR: Clean up
// 4. Repeat for edge cases
```

```bash
finito  # Verify + commit
```

**Time:** 15 minutes (vs 30-40 minutes ad-hoc)

---

## 3. Debugging Production Issue

**Scenario:** Intermittent 500 errors on `/api/orders`

```bash
You: Getting 500 errors on /api/orders endpoint intermittently
```

**Debugging skill auto-activates:**

```
🔍 Systematic Debugging Workflow:

1. Reading error logs...
   Found: UnhandledPromiseRejectionWarning in payment processing

2. Pattern analysis...
   Occurs during high concurrency (>50 req/s)

3. Code analysis...
   Found: Uncaught promise rejection in PaymentService.charge()

4. Root cause:
   Race condition - payment gateway returns before DB transaction commits

5. Fix suggestion:
   Add error boundaries and proper await chain

6. Implementation:
   - Wrap payment call in try-catch
   - Add transaction rollback on failure
   - Log all payment attempts

7. Regression test:
   - Simulate concurrent payment requests
   - Verify error handling
```

**Result:**
- ✅ Root cause identified in 10 minutes
- ✅ Fix implemented with proper error handling
- ✅ Regression test prevents recurrence

**vs ad-hoc debugging:**
- ❌ 1-2 hours of trial-and-error
- ❌ No systematic approach
- ❌ No regression test

---

## 4. Refactoring Legacy Code

**Scenario:** 500-line `processOrder` god-function needs splitting

```bash
mek: Refactor processOrder function in orders.service.ts
```

**Code-review skill auto-activates:**

```
📊 Analyzing processOrder function...

Current responsibilities (SRP violations):
1. Order validation
2. Pricing calculation
3. Discount application
4. Payment processing
5. Inventory updates
6. Email notifications
7. Logging

Suggested split (6 functions):
- validateOrder(order): ValidationResult
- calculatePricing(items): PricingDetails
- applyDiscounts(pricing, customer): FinalPrice
- processPayment(price, paymentMethod): PaymentResult
- updateInventory(items): InventoryResult
- sendConfirmation(order, payment): void

Using /superpowers:write-plan to create refactor steps...
```

**Plan generated (8 steps):**
1. Extract validateOrder (with tests)
2. Extract calculatePricing (with tests)
3. Extract applyDiscounts (with tests)
4. Extract processPayment (with tests)
5. Extract updateInventory (with tests)
6. Extract sendConfirmation (with tests)
7. Update processOrder to orchestrate
8. Verify all original tests still pass

**TDD enforced at each step** - ensures no regressions

**Result:**
- ✅ 500 lines → 6 focused functions (~80 lines each)
- ✅ All tests passing after each extraction
- ✅ No regressions
- ⏱️ 2 hours (vs 4-6 hours ad-hoc with multiple bugs)

---

## 5. Parallel Feature Development: Git Worktrees

**Scenario:** Work on `user-profiles` while `auth` is in review

```bash
You: I need to start user-profiles feature while auth is in review
```

**Worktrees skill auto-activates:**

```
🌳 Creating isolated worktree...

1. Creating directory: ../user-profiles-worktree
2. Creating branch: feature/user-profiles
3. Copying minimal context (excludes node_modules, .git, dist)
4. Setting up new Claude Code session
5. Opening in new window

✅ Worktree ready at: ../user-profiles-worktree
✅ Branch: feature/user-profiles
✅ Clean state, ready for work
```

**Benefits:**
- ✅ No git stashing
- ✅ No context switching
- ✅ Parallel development
- ✅ Each worktree has clean state

**When done:**
```bash
# In original worktree
git checkout main
git merge feature/user-profiles
git worktree remove ../user-profiles-worktree
```

---

## 6. TDD Implementation

**Scenario:** Add password strength validator

```bash
mek: Add password strength validator with TDD
```

**TDD skill enforces red-green-refactor:**

**Cycle 1: Minimum length**
```typescript
// RED: Write failing test
test('requires minimum 8 characters', () => {
  expect(validatePassword('short')).toEqual({
    valid: false,
    reason: 'Minimum 8 characters required'
  });
});

// GREEN: Minimal implementation
function validatePassword(password: string) {
  if (password.length < 8) {
    return { valid: false, reason: 'Minimum 8 characters required' };
  }
  return { valid: true };
}

// REFACTOR: (nothing to refactor yet)
```

**Cycle 2: Uppercase requirement**
```typescript
// RED
test('requires uppercase letter', () => {
  expect(validatePassword('lowercase123')).toEqual({
    valid: false,
    reason: 'Must contain uppercase letter'
  });
});

// GREEN
function validatePassword(password: string) {
  if (password.length < 8) {
    return { valid: false, reason: 'Minimum 8 characters required' };
  }
  if (!/[A-Z]/.test(password)) {
    return { valid: false, reason: 'Must contain uppercase letter' };
  }
  return { valid: true };
}

// REFACTOR
function validatePassword(password: string) {
  const checks = [
    { test: () => password.length >= 8, message: 'Minimum 8 characters' },
    { test: () => /[A-Z]/.test(password), message: 'Uppercase letter' },
  ];

  for (const check of checks) {
    if (!check.test()) {
      return { valid: false, reason: check.message };
    }
  }
  return { valid: true };
}
```

**Repeat for:** numbers, special characters, common passwords blacklist

**Result:**
- ✅ Full test coverage (written FIRST)
- ✅ No "code first, test later (never)"
- ✅ Incremental complexity
- ✅ Refactoring safe (tests catch regressions)

---

## 7. Production Deployment

**Scenario:** Auth feature ready for production

```bash
You: Ready to deploy auth feature to production
```

**Deploy-production skill auto-activates:**

```
🚀 Production Deployment Checklist

Pre-deployment:
✅ All tests passing? (142/142)
✅ No console.logs or debug code?
✅ Environment variables documented?
✅ Database migrations ready?
✅ Rollback plan exists?
✅ Monitoring configured?
✅ Team notified?

Deployment steps:
1. Build production bundle
   npm run build:prod

2. Run database migrations (with backup)
   pg_dump production > backup-2025-11-23.sql
   npm run migrate:prod

3. Deploy to staging first
   deploy staging

4. Smoke tests on staging
   ✅ Health check: /api/health
   ✅ Auth flow: login/logout/refresh
   ✅ Error handling: invalid credentials

5. Deploy to production
   deploy production

6. Monitor error rates (15 min)
   grafana dashboard: error-rates
   ✅ Error rate: 0.01% (baseline: 0.01%)

7. Send deployment notification
   Slack: #deployments
   "✅ Auth feature deployed to production"
```

**Benefits:**
- ✅ No missed steps (checklist enforced)
- ✅ Staging validation before production
- ✅ Rollback plan ready
- ✅ Monitoring confirms success
- ✅ Team aware

---

## Key Takeaways

### Time Savings by Scenario

| Scenario | With DAIC | Ad-hoc | Savings |
|----------|-----------|--------|---------|
| Complete feature | 67 min | 120 min | 44% |
| Simple utility | 15 min | 35 min | 57% |
| Debugging | 25 min | 90 min | 72% |
| Refactoring | 120 min | 300 min | 60% |

### Quality Improvements

- **Tests:** Built-in via TDD (not afterthought)
- **Documentation:** Auto-generated summaries
- **Commits:** Descriptive with full context
- **Scope:** Controlled (no feature creep)

### Context Preservation

Every session produces:
- Session summary (what/why/how)
- Test suite (verification)
- Proper commit (git history)
- Future warm-start capability

---

## Next Steps

- Pick one scenario similar to your work
- Run through full DAIC workflow
- Compare time and quality to your usual process
- Review your session summary

See [Getting Started](getting-started.md) for step-by-step first workflow.
