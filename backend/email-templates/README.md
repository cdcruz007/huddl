# Huddl Connect Email Templates

All transactional email templates are defined inline in `src/services/email-service.js`
using branded HTML with the Huddl colour palette.

## Template List

| Template                        | Trigger                              | When Sent                      |
|---------------------------------|--------------------------------------|--------------------------------|
| Welcome                        | User sign-up                         | Immediately after registration |
| Subscription Confirmation       | checkout.session.completed webhook   | After first payment            |
| Payment Receipt                 | invoice.payment_succeeded webhook    | Every successful payment       |
| Payment Failed Warning          | invoice.payment_failed webhook       | On payment failure             |
| Trial Ending Reminder (Day 5)   | Daily cron job                       | 2 days before trial ends       |
| Cancellation Confirmation       | customer.subscription.deleted webhook| When subscription is cancelled |

## Email Provider

Emails are sent via **Hostinger SMTP** using nodemailer.
Set `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, and `SMTP_PASS` in your environment.

In development (no SMTP credentials set), emails are logged to the console
instead of sent.

## Brand Colours

- Primary: #6C63FF
- Secondary: #FF6584
- Accent: #43B581
- Dark: #2D2D3F
- Light: #F8F9FE
