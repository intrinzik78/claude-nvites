# Accounts
1. Accounts are owned by adults (parent / guardian / participant)
2. All accounts must be email verified

# Waivers
1. Full waivers are created for the account owner first
2. Child waivers can be added to an account with name and birthday and consent to participate
3. Waivers are read-only after creation

# Pre-paid bookings
1. Have an order receipt
2. Date
3. Time
4. Player count
5. Product ID
6. UUID

# UUID
1. Unique identifier
2. Format is XXX-XXX where X[0..2] is [A..Z] and [3..5] is [0..9]
3. Parents || Players can add their waiver to the booking with the UUID (QR Code / shortlink)

# Prepaid Bookings / Digital Queue Workflow
1. Booking owner creates an event
2. UUID is generated, shortlink / button / QR code is sent to the customer encouraging them to complete waivers prior to the event
3. Booking owner shares the link with all invited guests
4. Guest has an account
   1. login, add to account with query string
5. Guest does not have an account
   1. guest creates an account
   2. guest adds waivers with query string
6. Waiver count is incremented in the command center (n+1 of x)


# Edge cases
1. Guest doesn't have access to event link?
   1. Command center pulls up the UUID and staff manually gives UUID
   2. Guest goes to website, creates an account / logs in, uses UUID to attach waiver to booking
2. Guest doesn't have digital access?
   1. Editor splits booking
   2. Editor approves digitally checked in and completed guest
   3. Editor collects a paper waiver from the split off guest
   4. Editor uses the command center to "create paper waiver"
   5. Editor enters username / pw to confirm 
   6. The split guest is then approved as if they had a digital waive