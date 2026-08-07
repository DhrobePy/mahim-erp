import type { ManualSection } from './types'

// Plain, task-based user manual — English. Written for someone who has
// never used the app before but knows the business (packaging factory,
// LCs, GRNs, payroll). Not a field-by-field spec — that's what the app's
// own tooltips/labels are for.
export const manualEn: ManualSection[] = [
  {
    key: 'executive',
    title: 'Executive',
    modules: [
      {
        key: 'ceo',
        route: '/ceo',
        icon: 'i-heroicons-chart-bar-square',
        title: 'CEO overview',
        purpose: 'A one-screen picture of the whole business right now — cash, receivables, stock, debt, profit, and the sales pipeline. Every figure links through to where it comes from.',
        tasks: [
          {
            heading: 'Read the money position',
            steps: [
              'The "Where the money is" row shows Bank + Cash, Bills Receivable (LC), Delivered-Not-Invoiced, Stock, what you owe suppliers, bank debt, and Net Position (everything added up).',
              'Click any card to jump to the page it came from — e.g. click "Bank Debt" to open Banking.'
            ]
          },
          {
            heading: 'Check the LC contract book',
            steps: [
              'The table in the middle lists every LC, with revenue, cost of goods, bank fees/interest, and profit per contract.',
              'Click an LC number to open its full detail page.'
            ]
          },
          {
            heading: 'Watch the alert strip',
            steps: [
              'Red/amber/purple bars at the top warn about overdue bills, bills maturing soon, and LC document discrepancies.',
              'Click an alert to jump straight to that LC.'
            ]
          }
        ],
        tips: ['Facility headroom bars turn red once a bank facility is over 90% used — that is your warning to slow down before you hit the limit.']
      }
    ]
  },
  {
    key: 'operations',
    title: 'Operations',
    modules: [
      {
        key: 'dashboard',
        route: '/',
        icon: 'i-heroicons-home',
        title: 'Dashboard',
        purpose: 'Your daily landing page — bank, receivables, stock, and production at a glance, plus the latest stock movements and journal entries.',
        tasks: [
          {
            heading: 'Read the stat cards',
            steps: [
              'Each card is clickable and takes you to the page behind that number.',
              'A card turns amber or red when something needs attention (e.g. Low Stock, Delivered-Not-Invoiced).'
            ]
          },
          {
            heading: 'Refresh the numbers',
            steps: ['Click "Refresh" top-right, or just wait — the dashboard refreshes itself every 60 seconds.']
          }
        ]
      },
      {
        key: 'items',
        route: '/items',
        icon: 'i-heroicons-cube',
        title: 'Items',
        purpose: 'The master list of everything you track — raw materials, work-in-progress, finished goods, consumables, and packaging.',
        tasks: [
          {
            heading: 'Add a new item',
            steps: [
              'Click "New Item".',
              'Fill in SKU and Name (required), then Type, Category, Unit of Measure.',
              'For paper reels, fill in GSM (paper weight) — you will need this later if you build a carton recipe from this item.',
              'Set Reorder Level so Stock can warn you when you are running low, and a Standard Cost.',
              'Click Save.'
            ]
          },
          { heading: 'Edit or remove an item', steps: ['Click the pencil icon on a row to edit, or the trash icon to remove it (it goes to the Recycle Bin, not gone forever).'] },
          { heading: 'Find an item fast', steps: ['Type into the search box — it filters by SKU or name as you type.'] }
        ],
        tips: ['Standard Cost here is a fixed reference cost — receiving stock at a different price on a GRN does not change it automatically.']
      },
      {
        key: 'stock',
        route: '/stock',
        icon: 'i-heroicons-archive-box',
        title: 'Stock',
        purpose: 'Shows exactly how much of each item you have right now, in every warehouse. The numbers update automatically whenever a GRN, production order, sale, or manual entry happens.',
        tasks: [
          {
            heading: 'Check what is low',
            steps: ['Look for the "Low" amber badge — it appears when quantity on hand is at or below the Reorder Level you set on the Items page.']
          },
          {
            heading: 'Post a manual stock entry',
            steps: [
              'Click "Stock Entry".',
              'Pick the Item and Warehouse, choose a type (Opening / Adjustment), and enter the quantity — use a negative number to reduce stock.',
              'Click Post.'
            ]
          }
        ],
        tips: [
          'Do not use Stock Entry for normal receiving or selling — those happen automatically from GRNs and Production. Use it only for opening balances and corrections.',
          'Stock never has a "status" — it is always the live, current total after every posted movement.'
        ]
      },
      {
        key: 'boms',
        route: '/boms',
        icon: 'i-heroicons-rectangle-stack',
        title: 'BOMs & Carton Recipes',
        purpose: 'Two tools in one page: a plain Bill of Materials (finished item + its raw components), and the Carton Recipe Wizard — a calculator built specifically for corrugated boxes that works out paper needed and a suggested selling price straight from the box dimensions.',
        tasks: [
          {
            heading: 'Build a carton recipe (the fast way)',
            steps: [
              'Click "New Carton Recipe".',
              'Optionally pick a saved Template to pre-fill layers.',
              'Pick the finished item (or tick "Create new item" and type a new SKU/name).',
              'Enter Length, Width, Height and pick the unit (cm/mm/inch).',
              'Choose 3-ply, 5-ply, or 7-ply board.',
              'For each layer, set the GSM (paper weight) and pick which paper reel (raw material) feeds it; for the middle "flute" layers also pick the Flute Type (A/B/C/E/F).',
              'Check the live preview panel — it shows blank size, paper needed per box, and a full cost + suggested price breakdown.',
              'Click "Save Recipe" — this creates the item (if new) and builds the BOM for you automatically.'
            ]
          },
          {
            heading: 'Build a plain BOM',
            steps: ['Click "New BOM", pick the finished item and output quantity, add each raw-material component with its quantity and wastage %, then Save.']
          },
          { heading: 'Reuse a layer template', steps: ['Click "Recipe Templates" to create or edit reusable ply/GSM/flute presets, so you do not re-type the same construction every time.'] }
        ],
        tips: [
          'The suggested price comes from: paper cost (with wastage%) + other materials + overhead% + margin%. Overhead and margin default from Company settings but you can override them per recipe.',
          'A carton-recipe BOM shows an "Edit Recipe" button instead of a normal component list — always edit it through the wizard, not as a plain BOM.',
          'Flute type changes how much paper the flute layer actually uses (a tighter flute like E uses less paper per box than a coarser flute like A) — the calculator already accounts for this.'
        ]
      },
      {
        key: 'production',
        route: '/production',
        icon: 'i-heroicons-cog-6-tooth',
        title: 'Production',
        purpose: 'Manufacturing orders that turn raw materials into a finished good and post it into stock once complete.',
        statuses: 'planned → released → in progress → completed (or cancelled)',
        tasks: [
          {
            heading: 'Create a production order',
            steps: [
              'Click "New Order".',
              'Pick the finished item, and a BOM if you have one built for it (this is optional).',
              'Enter the Planned Quantity, the output warehouse, and a planned date.',
              'Click Save.'
            ]
          },
          {
            heading: 'Complete an order',
            steps: [
              'Click "Complete" on the order once production is physically finished.',
              'This posts the full Planned Quantity into stock immediately — there is no partial-completion option, so only complete an order once all of it is actually done.'
            ]
          }
        ],
        tips: ['If you skip picking a BOM, no components are automatically consumed — you would need to record any raw-material usage separately.']
      }
    ]
  },
  {
    key: 'procurement',
    title: 'Procurement',
    modules: [
      {
        key: 'parties',
        route: '/parties',
        icon: 'i-heroicons-users',
        title: 'Parties',
        purpose: 'One master list for everyone you deal with outside the company — customers, suppliers, transporters, banks, and foreign counterparties — plus a full 360° history page per party.',
        tasks: [
          {
            heading: 'Add a party',
            steps: [
              'Click "New Party".',
              'Enter a Code and Name, then tick every role that applies (a party can be a Customer AND a Supplier at the same time, for example).',
              'Fill in phone, BIN/TIN, and address if you have them. Tick "Foreign" and pick a country for overseas counterparties.',
              'Save.'
            ]
          },
          {
            heading: 'See a party\'s full history',
            steps: [
              'Click a party name to open its 360° page.',
              'You will see how much they owe you or you owe them, their orders, LCs, invoices, and (for suppliers) their GRN and Debit Note history — all in one place.'
            ]
          }
        ],
        tips: ['The Receivable/Payable figures on a party\'s page are calculated live from the accounts, not from a stored balance — they always reflect the true ledger position.']
      },
      {
        key: 'purchase_orders',
        route: '/procurement/purchase-orders',
        icon: 'i-heroicons-clipboard-document-list',
        title: 'Purchase Orders',
        purpose: 'Formal orders to your suppliers, with an estimate of the true landed cost (price + freight + customs + agent fees) before the goods even arrive.',
        statuses: 'draft → approved → partially received → received → closed (or cancelled)',
        tasks: [
          {
            heading: 'Raise a purchase order',
            steps: [
              'Click "New PO", pick the supplier, currency, and dates.',
              'Add each item, quantity, and unit price.',
              'If you know freight, customs duty, clearing agent fees, or other landed costs, enter them — the form shows a live "landed cost per unit" as you type.',
              'Click "Save as Draft" — every PO starts as a draft, never auto-approved.'
            ]
          },
          { heading: 'Approve a PO', steps: ['Open the PO and click "Approve". Only approved POs can be picked when creating a GRN against them.'] },
          { heading: 'Cancel a PO', steps: ['Click "Cancel" on a draft or approved PO (you will be asked to confirm).'] }
        ]
      },
      {
        key: 'procurement',
        route: '/procurement',
        icon: 'i-heroicons-truck',
        title: 'GRNs (Goods Receipt)',
        purpose: 'Where incoming goods are formally received, weighed, and checked — and where stock and accounting actually get updated. Built with a paper-industry QA step: suppliers bill you on invoice weight, but what actually lands in stock is the true net weight after removing the reel core and any excess moisture.',
        statuses: 'draft → completed (or cancelled)',
        tasks: [
          {
            heading: 'Receive goods',
            steps: [
              'Click "New GRN".',
              'Pick the supplier. If they have an approved Purchase Order, pick it from "Receive Against PO" and the lines fill in automatically.',
              'For each line, enter the Gross Weight, Core/Tare Weight, and Moisture % — the True Net weight is calculated for you live.',
              'If the true net is less than the supplier invoiced, you will see an amber shortfall note — that is normal for paper reels.',
              'Click "Save Draft" to hold it, or "Complete & Post" to finish now.'
            ]
          },
          {
            heading: 'Post a saved draft',
            steps: ['Open the draft GRN and click "Complete & Post". This is the moment stock increases and the supplier bill (Accounts Payable) is booked.']
          },
          {
            heading: 'Understand the Debit Note',
            steps: ['If the true net weight came in short of what the supplier billed, the system automatically creates a Debit Note for the difference — this is the paper trail you hand to the supplier to negotiate the shortfall. No manual step needed.']
          }
        ],
        tips: [
          'Nothing happens to stock or accounts until you click "Complete & Post" — a draft GRN has zero effect.',
          'A moisture reading up to 12% is normal and causes no deduction — only moisture above 12% reduces the true net weight.',
          'Stock is always posted at the True Net weight, never the invoice weight — so the quantity you receive into stock is usually a little less than what the supplier billed, by design.'
        ]
      }
    ]
  },
  {
    key: 'sales',
    title: 'Sales & Local LC',
    modules: [
      {
        key: 'quotations',
        route: '/quotations',
        icon: 'i-heroicons-clipboard-document-list',
        title: 'Quotations / PI',
        purpose: 'Pre-sale paperwork — Quotations, Proforma Invoices (PI), and Contracts — all managed on one page.',
        statuses: 'draft → sent → accepted → converted (or expired / cancelled)',
        tasks: [
          {
            heading: 'Create a quotation',
            steps: ['Click "New Document", pick the type (Quotation/PI/Contract), the buyer, payment and delivery terms, and add item lines. Save.']
          },
          {
            heading: 'Move it forward',
            steps: [
              'Mark it "Sent" once you have shared it with the buyer, then "Accepted" once they confirm.',
              'Use "To PI" or "To Contract" to turn it into the next document type while keeping the link back to the original.',
              'Use "To Order" any time to create the actual Sales Order from it.'
            ]
          }
        ],
        tips: ['"To PI"/"To Contract" and "To Order" are different actions — converting to a PI does not create a Sales Order, and creating an Order does not close the quotation automatically.']
      },
      {
        key: 'sales_orders',
        route: '/sales',
        icon: 'i-heroicons-shopping-cart',
        title: 'Sales Orders',
        purpose: 'The firm order you deliver against — the hub that links your buyer, an LC (if any), deliveries, and invoices together.',
        statuses: 'open → partially delivered → delivered → closed (or cancelled)',
        tasks: [
          {
            heading: 'Create an order',
            steps: ['Click "New Order", pick the buyer, an LC if one is already open (leave blank if not — the order is tagged "Pre-LC" and you can attach an LC later), and add item lines. Save.']
          },
          {
            heading: 'Track delivery progress',
            steps: ['Open the order to see delivered vs. ordered quantity per line, and every Challan and Invoice linked to it.']
          },
          { heading: 'Generate a Proforma Invoice from an order', steps: ['Click "Generate PI" on the order\'s detail page.'] }
        ]
      },
      {
        key: 'challans',
        route: '/challans',
        icon: 'i-heroicons-document-duplicate',
        title: 'Challans',
        purpose: 'The delivery note — it moves stock out the door and is the bridge between a Sales Order and an Invoice.',
        statuses: 'draft → issued → delivered / awaiting LC cover → invoiced (or cancelled)',
        tasks: [
          {
            heading: 'Create and issue a delivery',
            steps: [
              'Click "New Challan", pick the Sales Order — the items, quantities, and LC fill in automatically.',
              'Save as Draft, then click "Issue" when the goods actually leave — this is the moment stock is deducted.'
            ]
          },
          {
            heading: 'Deliver before the LC is ready ("Pre-LC")',
            steps: [
              'If there is no LC yet, the challan is created as an "original"/pre-LC delivery with no LC attached.',
              'Once an LC becomes available, open the challan and click "Cover with LC" — this creates a new linked "covering" challan against that LC.',
              'The covering challan is what you invoice against; the original stays as the physical delivery record.'
            ]
          },
          { heading: 'Turn a delivery into an invoice', steps: ['Click "Invoice" on an issued challan (that is not the pre-LC original) to create the invoice.'] }
        ],
        tips: ['"Awaiting LC Cover" (shown elsewhere as "delivered, unbilled") means goods have gone out but there is still no LC to bill against — fix it with "Cover with LC".']
      },
      {
        key: 'lcs',
        route: '/lcs',
        icon: 'i-heroicons-document-check',
        title: 'Letters of Credit (LCs)',
        purpose: 'Register and track every LC — local back-to-back export, direct foreign export, and import — with full document upload, a timeline, and profit-per-contract.',
        tasks: [
          {
            heading: 'Register a new LC',
            steps: ['Click "Register from PDF" and upload the LC document to auto-fill the form (always double check before saving), or click "Register LC" to fill it in by hand.']
          },
          { heading: 'Amend an LC', steps: ['Open an active LC and click "Amend" to record a new version — amount, quantity, tolerance, or expiry changes.'] },
          { heading: 'See everything about one LC', steps: ['Click the LC number to open its detail page — timeline, bills, documents, alerts, and profit & loss for that contract.'] }
        ]
      },
      {
        key: 'invoices',
        route: '/invoices',
        icon: 'i-heroicons-document-text',
        title: 'Invoices',
        purpose: 'Your revenue invoices, generated from challans, and the starting point for getting paid against an LC.',
        statuses: 'open → billed → settled',
        tasks: [
          { heading: 'Submit an LC bill', steps: ['Click "Submit Bill" on an open, LC-backed invoice — this creates the bank bill that feeds the Banking module.'] },
          { heading: 'Process a sales return', steps: ['Click "Return" on an invoice, enter the item, returned quantity, and scrap value, and confirm.'] }
        ]
      }
    ]
  },
  {
    key: 'finance',
    title: 'Finance',
    modules: [
      {
        key: 'banking',
        route: '/banking',
        icon: 'i-heroicons-banknotes',
        title: 'Banking / LBPD',
        purpose: 'Bank credit facilities, the export bills raised against LCs, and LBPD — getting cash advanced against a bill before it is actually due.',
        statuses: 'Bills: submitted → accepted → discounted → realized (or overdue). Disbursements: open → settled (or forced PAD)',
        tasks: [
          { heading: 'Add a credit facility', steps: ['Click "New Facility", pick the bank, type (LBPD/OD/CC/Term), limit, and interest rate.'] },
          {
            heading: 'Discount a bill (get an advance)',
            steps: [
              'Once a bill is "Accepted", click "Discount".',
              'Pick the facility and the advance % (usually 85%) — the form shows exactly how much cash you will receive now.'
            ]
          },
          { heading: 'Settle a disbursement', steps: ['Click "Settle" and enter any interest charged by the bank.'] },
          { heading: 'When a bill is not repaid on time', steps: ['The bank may force it into "Forced PAD" — a demand loan against the company, usually with a penalty. This shows in red.'] }
        ],
        tips: [
          'LBPD = Local Bill Purchase/Discount: the bank pays you most of the bill value now, in advance, instead of you waiting for the buyer\'s bank to actually settle it.',
          'PAD = Payment Against Documents: if a discounted bill is not realized by its due date, the bank converts it into a forced loan — a sign something went wrong on the buyer/bank side.',
          'Watch the facility exposure bar — it turns red past 90% of your limit.'
        ]
      },
      {
        key: 'accounting',
        route: '/accounting',
        icon: 'i-heroicons-calculator',
        title: 'Accounting',
        purpose: 'The general ledger hub — trial balance at a glance, the journal register, and the one place to post a manual journal entry.',
        tasks: [
          {
            heading: 'Post a manual journal',
            steps: [
              'Click "Manual Journal".',
              'Enter the date and memo, then add account/debit/credit lines with "Add Line".',
              'The Post button only unlocks once your debits exactly equal your credits.'
            ]
          }
        ],
        tips: ['Most modules (challans, cash sales, transfers, bank charges, payroll) post their own journal entries automatically — use Manual Journal only for entries nothing else covers.']
      },
      {
        key: 'bank_accounts',
        route: '/accounting/accounts',
        icon: 'i-heroicons-credit-card',
        title: 'Bank & Cash Accounts',
        purpose: 'Your own company bank accounts and cash tills used for day-to-day postings — different from the credit Facilities on the Banking page.',
        tasks: [
          { heading: 'Add an account', steps: ['Click "New Account", choose Bank Account or Cash Point, and enter the opening balance and as-of date.'] },
          { heading: 'Reconcile a bank account', steps: ['Click a bank account row to open its reconciliation page.'] }
        ]
      },
      {
        key: 'cash_sales',
        route: '/accounting/cash-sales',
        icon: 'i-heroicons-shopping-bag',
        title: 'Cash Sales',
        purpose: 'Record over-the-counter sales that do not go through the normal Sales Order → Challan → Invoice pipeline.',
        statuses: 'draft → completed',
        tasks: [
          { heading: 'Record a cash sale', steps: ['Click "New Sale", choose Walk-in or a registered party, add item lines, and Save Draft.'] },
          { heading: 'Finish it', steps: ['Click "Complete" on the row — saving alone does not post it; Complete is what actually books the sale.'] }
        ]
      },
      {
        key: 'transfers',
        route: '/accounting/transfers',
        icon: 'i-heroicons-arrows-right-left',
        title: 'Transfers',
        purpose: 'Move money between your own bank/cash accounts — e.g. bank to petty cash.',
        tasks: [{ heading: 'Make a transfer', steps: ['Click "New Transfer", pick From and To accounts (they must be different), enter the amount, and confirm — it posts immediately.'] }]
      },
      {
        key: 'bank_charges',
        route: '/accounting/bank-charges',
        icon: 'i-heroicons-currency-dollar',
        title: 'Bank Charges & Fees',
        purpose: 'Log fees the bank has deducted directly — LC fees, SWIFT charges, service charges, legal fees, or Advance Income Tax (AIT) deducted.',
        tasks: [{ heading: 'Log a charge', steps: ['Click "New Entry", pick the account and category, and enter the amount. It posts immediately.'] }],
        tips: ['Entries logged with category "AIT Deducted" automatically feed the AIT Summary report — no extra step needed there.']
      },
      {
        key: 'pnl',
        route: '/accounting/pnl',
        icon: 'i-heroicons-chart-bar',
        title: 'Profit & Loss',
        purpose: 'Your full profit statement — Revenue → Cost of Goods Sold → Gross Profit → Operating & Financial Expenses → Net Profit — for any date range you pick.',
        tasks: [
          { heading: 'Run a report', steps: ['Set a From/To date range (leave blank for all-time), then click any section to expand it into per-account detail.'] },
          { heading: 'Print it', steps: ['Click "Print" for a formal printable statement.'] }
        ]
      },
      {
        key: 'vat_return',
        route: '/accounting/vat-return',
        icon: 'i-heroicons-receipt-percent',
        title: 'VAT Return',
        purpose: 'A ready-made VAT (Mushak) reconciliation — Output VAT you charged, Input VAT you paid, and the Net Payable — for filing.',
        tasks: [{ heading: 'Run it for a period', steps: ['Set the date range, review Output and Input VAT lists side by side, then Print.'] }],
        tips: ['This report is read-only — VAT entries come automatically from your invoices and purchases elsewhere in the app.']
      },
      {
        key: 'ait_summary',
        route: '/accounting/ait-summary',
        icon: 'i-heroicons-document-chart-bar',
        title: 'AIT Summary',
        purpose: 'A running total of Advance Income Tax paid and TDS (tax already deducted by others on your behalf) payable.',
        tasks: [{ heading: 'Add an entry to this report', steps: ['Go to Bank Charges & Fees and log a new entry with category "AIT Deducted" — it will appear here automatically.'] }]
      }
    ]
  },
  {
    key: 'hr',
    title: 'HR',
    modules: [
      {
        key: 'hr',
        route: '/hr',
        icon: 'i-heroicons-identification',
        title: 'Employees',
        purpose: 'Your staff register and each employee\'s full record — personal details, payslips, loans, attendance, stationery usage, and performance reviews.',
        tasks: [
          { heading: 'Add an employee', steps: ['Click "New Employee", fill in name, designation, department, joining date, and salary, then Save.'] },
          { heading: 'Give an employee a loan', steps: ['Click "Disburse Loan", pick the employee, enter the principal, monthly installment, and which account it is paid from.'] },
          { heading: 'View one employee in full', steps: ['Click their name to open their 360° page — payslips, loans, attendance, stationery, and Annual Confidential Reports (ACR).'] }
        ],
        tips: [
          'A loan is capped at 6× the employee\'s basic salary, and an employee can only have one active loan at a time.',
          'Overtime rate is calculated automatically as basic salary ÷ 208 × 2, per the Bangladesh Labour Act.'
        ]
      },
      {
        key: 'attendance',
        route: '/hr/attendance',
        icon: 'i-heroicons-finger-print',
        title: 'Attendance',
        purpose: 'The daily attendance register — one row per active employee for the date you pick.',
        tasks: [
          { heading: 'Mark a day\'s attendance', steps: ['Pick the date, set each employee\'s status (Present/Absent/Leave/Holiday/Weekend), enter OT hours where relevant, tick "Late" if needed, then click "Save day" to save everyone at once.'] }
        ],
        tips: ['Overtime is capped at 4 hours a day — this is enforced automatically to meet Sedex/BSCI ethical-trade audit rules.']
      },
      {
        key: 'payroll',
        route: '/hr/payroll',
        icon: 'i-heroicons-currency-bangladeshi',
        title: 'Payroll',
        purpose: 'Generate, review, post, and pay monthly salary and festival bonus runs — including automatic loan recovery.',
        statuses: 'draft → posted → paid',
        tasks: [
          { heading: 'Run monthly payroll', steps: ['Click "Generate" under Monthly Payroll, pick the year and month, and it builds a draft run for every active employee automatically.'] },
          { heading: 'Run a festival bonus', steps: ['Click "Generate" under Festival Bonus, pick year/month and a label (e.g. "Eid-ul-Fitr 2026").'] },
          { heading: 'Review and post', steps: ['Click a draft run to expand it and check each employee\'s breakdown, then click "Post to GL" to book the accounting entries.'] },
          { heading: 'Pay it out', steps: ['Click "Pay" on a posted run and pick which account the money leaves from.'] }
        ],
        tips: [
          'The system does the math for you: days present/absent, overtime, an attendance allowance (only paid in full with zero absences), and any active loan installment — all pulled in automatically.',
          'Festival bonus is a full month\'s basic salary for staff with 12+ months\' service, prorated for anyone newer.',
          'You can delete a run at any stage to reverse it — the accounting entries get automatically unwound.'
        ]
      },
      {
        key: 'stationery',
        route: '/hr/stationery',
        icon: 'i-heroicons-pencil-square',
        title: 'Office Stationery',
        purpose: 'Track office supplies — receive stock in, issue it to staff, and see who is using how much.',
        tasks: [
          { heading: 'Receive stock', steps: ['Click "Receive Stock", pick the item, quantity, cost, and supplier (leave the account blank if it is on credit).'] },
          { heading: 'Issue to an employee', steps: ['Click "Issue to Employee", pick the item, employee, and quantity.'] }
        ]
      }
    ]
  },
  {
    key: 'admin',
    title: 'Admin',
    modules: [
      {
        key: 'audit',
        route: '/audit',
        icon: 'i-heroicons-shield-check',
        title: 'Audit Trail',
        purpose: 'A read-only log of every important change anyone made anywhere in the system — who, when, what changed.',
        tasks: [{ heading: 'Find a specific change', steps: ['Filter by table name and/or action type (Insert/Update/Delete) at the top.'] }],
        tips: ['This page is visible to Admins only.']
      },
      {
        key: 'recycle_bin',
        route: '/recycle-bin',
        icon: 'i-heroicons-trash',
        title: 'Recycle Bin',
        purpose: 'Every deleted record from anywhere in the app, in one place, with a Restore button.',
        tasks: [
          { heading: 'Restore something', steps: ['Filter by module if you know where it came from, find the record, and click "Restore".'] }
        ],
        tips: [
          'For records that already affected the accounts or stock (a GRN, an invoice, a payroll run, etc.), deleting does not erase the entry — it posts a reversing entry so your books stay correct. Restoring reverses that reversal, bringing everything back exactly as it was.',
          'This is really a "void", not an erase — you will always see a matching entry in Accounting when something like this is deleted.'
        ]
      },
      {
        key: 'company',
        route: '/admin/company',
        icon: 'i-heroicons-building-office-2',
        title: 'Company & Structure',
        purpose: 'Your company\'s legal identity, logo, any subsidiary companies, and the default costing settings used by the Carton Recipe Wizard.',
        tasks: [
          { heading: 'Update company details', steps: ['Edit trading name, legal name, address, BIN, TIN, and logo, then Save.'] },
          { heading: 'Add a subsidiary', steps: ['Click "New Subsidiary" and give it a trading name and code.'] },
          { heading: 'Switch between companies', steps: ['Click "Switch to" next to any company you belong to.'] },
          { heading: 'Set carton costing defaults', steps: ['Enter your typical Reference Material Cost and Reference Factory Cost per box (the page works out the implied overhead % for you), and a Default Margin % — these become the starting point every new carton recipe uses.'] }
        ]
      },
      {
        key: 'directors',
        route: '/admin/directors',
        icon: 'i-heroicons-user-group',
        title: 'Directors & Partners',
        purpose: 'Your register of directors, partners, and company secretary, with shareholding — used to auto-draft two standard RJSC filings.',
        tasks: [
          { heading: 'Add a director', steps: ['Click "New Director", fill in name, designation, NID, shares held, and appointment date.'] },
          { heading: 'Print the RJSC forms', steps: ['Click "Form XII" (return of directors) or "Schedule X" (return of shareholding) to generate a draft.'] }
        ],
        tips: [
          'RJSC = the Registrar of Joint Stock Companies and Firms — the government office every Bangladeshi company must file changes with.',
          'These printouts are drafting aids — always have your company secretary or lawyer review before filing anything with RJSC.'
        ]
      },
      {
        key: 'resolutions',
        route: '/admin/resolutions',
        icon: 'i-heroicons-clipboard-document-check',
        title: 'Board Resolutions',
        purpose: 'A written record of decisions your board formally approved — banks and RJSC often require one before they will act on something.',
        statuses: 'draft → passed (or circulated)',
        tasks: [
          { heading: 'Draft a resolution', steps: ['Click "New Resolution", pick the meeting type and date, tick attendees, then add each agenda item (pick a ready-made template or write your own).'] },
          { heading: 'Finalize it', steps: ['Click "Mark Passed" once the board has actually approved it, then use the print icon for the formal document.'] }
        ]
      },
      {
        key: 'documents',
        route: '/admin/documents',
        icon: 'i-heroicons-folder',
        title: 'Company Documents',
        purpose: 'Every corporate license, certificate, and compliance document in one place, with automatic expiry warnings.',
        tasks: [
          { heading: 'Upload a document', steps: ['Click "Upload", pick the type (trade license, TIN certificate, fire license, BSCI/Sedex audit, FSC certificate, and many more), and attach the file.'] },
          { heading: 'Review a document', steps: ['Click a row to expand it, then use Approve / Flag / Reject to log a review decision.'] }
        ],
        tips: ['Documents are sorted by expiry date automatically, so whatever needs renewing soonest is always at the top. Red means expired, amber means expiring within 30 days.']
      },
      {
        key: 'forwarding',
        route: '/admin/forwarding',
        icon: 'i-heroicons-paper-airplane',
        title: 'Forwarding Pad',
        purpose: 'Official outgoing letters to banks, buyers, or government offices, on your company letterhead, numbered and logged.',
        tasks: [{ heading: 'Write a letter', steps: ['Click "New Letter", pick a topic to auto-fill a standard template (or write your own), fill in the recipient and enclosures, and Save. Use the print icon for the formal letter.'] }]
      },
      {
        key: 'bank_requests',
        route: '/admin/bank-requests',
        icon: 'i-heroicons-building-library',
        title: 'Bank Service Requests',
        purpose: 'Formal requests sent to a specific bank branch — opening an LC, requesting a loan, or asking for a statement — plus your branch contact book.',
        statuses: 'draft → submitted → acknowledged → completed',
        tasks: [
          { heading: 'Add a bank branch', steps: ['Use the branch register card at the top of the page to add contact details for a branch.'] },
          { heading: 'Send a request', steps: ['Click "New Request", pick the branch and service type (this auto-fills a standard letter), fill in the details, and Save.'] },
          { heading: 'Track it', steps: ['Click "Mark Submitted", then "Mark Acknowledged", then "Mark Completed" as the bank responds.'] }
        ]
      },
      {
        key: 'tax_it10b',
        route: '/admin/tax',
        icon: 'i-heroicons-calculator',
        title: 'Tax — IT-10B',
        purpose: 'A drafting tool for IT-10B — the personal wealth statement Bangladesh requires alongside an individual\'s income tax return.',
        tasks: [{ heading: 'Build a statement', steps: ['Click "New Statement", pick a director (or type a name), enter the assessment year and opening net wealth, then list each asset and liability. The net wealth is calculated for you.'] }],
        tips: ['This is a drafting aid only — always verify with a tax practitioner before filing.']
      },
      {
        key: 'tax_corporate',
        route: '/admin/tax/corporate',
        icon: 'i-heroicons-scale',
        title: 'Corporate Tax',
        purpose: 'Turns your accounting profit into taxable income and works out the corporate tax payable.',
        tasks: [
          {
            heading: 'Build a computation',
            steps: [
              'Click "New Computation", pick the assessment year.',
              'Click "Pull from P&L" to bring in net profit automatically, and "Pull from AIT Summary" for advance tax paid.',
              'Add any addback/deduction lines the accountant gives you, and enter TDS credit if any.'
            ]
          }
        ],
        tips: ['This is a working paper, not a filing — review it with a registered tax practitioner first.']
      },
      {
        key: 'access',
        route: '/access',
        icon: 'i-heroicons-key',
        title: 'Access & Roles',
        purpose: 'Where an Admin creates user accounts and decides exactly which pages each person can see and edit.',
        tasks: [
          { heading: 'Create a new user', steps: ['Click "New User", enter their name and email — a password is generated for you (click the refresh icon to regenerate it), then copy the credentials and hand them to the person directly.'] },
          {
            heading: 'Set what someone can access',
            steps: [
              'Click "Permissions" next to their name.',
              'For every module, tick View (they can see/open it) and/or Write (they can create and edit inside it) — ticking Write automatically ticks View too.'
            ]
          },
          { heading: 'Remove access', steps: ['Click "Revoke" to deactivate someone\'s account.'] }
        ],
        tips: [
          'This page is visible to Admins only.',
          'Every new user starts with nothing except the dashboard — access to everything else comes purely from the permission checklist, module by module.'
        ]
      }
    ]
  }
]
